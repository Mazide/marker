import AppKit
import Foundation
import SQLite3

/// `marker-cli` — terminal access to Marker's selection history, in the
/// spirit of xclip/xsel. Talks to the app's SQLite file directly (WAL
/// keeps this reader safe next to the app's writer), so it works even
/// when Marker isn't running. Deliberately standalone: the schema below
/// is the contract with the app, nothing else is shared.

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct Entry {
    let text: String
    let date: Date
    let appName: String
    let bundleID: String
    let rtf: Data?
    let html: String?
}

func databaseURL() -> URL {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Marker/history.sqlite")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func openDatabase(readOnly: Bool) -> OpaquePointer {
    let url = databaseURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        fail("no history database at \(url.path) — has Marker run yet?")
    }
    var db: OpaquePointer?
    let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
    guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
        fail("could not open \(url.path)")
    }
    sqlite3_busy_timeout(db, 5000)
    return db
}

func fetch(sql: String, bind: (OpaquePointer?) -> Void = { _ in }) -> [Entry] {
    let db = openDatabase(readOnly: true)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        fail("query failed: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    bind(statement)
    var result: [Entry] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let text = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let appName = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let bundleID = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
        var rtf: Data?
        if let blob = sqlite3_column_blob(statement, 4) {
            rtf = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 4)))
        }
        let html = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        result.append(Entry(text: text, date: date, appName: appName, bundleID: bundleID, rtf: rtf, html: html))
    }
    return result
}

let baseSelect = "SELECT text, date, appName, bundleID, rtf, html FROM items"

func recent(limit: Int) -> [Entry] {
    fetch(sql: "\(baseSelect) ORDER BY date DESC LIMIT ?") { statement in
        sqlite3_bind_int(statement, 1, Int32(limit))
    }
}

func search(_ query: String, limit: Int) -> [Entry] {
    let escaped = query.lowercased()
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")
    let pattern = "%\(escaped)%"
    return fetch(sql: """
    \(baseSelect) WHERE text_lc LIKE ? ESCAPE '\\' OR appName_lc LIKE ? ESCAPE '\\'
    ORDER BY date DESC LIMIT ?
    """) { statement in
        sqlite3_bind_text(statement, 1, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, Int32(limit))
    }
}

// MARK: - Output

func printJSON(_ entries: [Entry]) {
    let formatter = ISO8601DateFormatter()
    let objects: [[String: Any]] = entries.map { entry in
        var object: [String: Any] = [
            "text": entry.text,
            "date": formatter.string(from: entry.date),
            "app": entry.appName,
            "bundleID": entry.bundleID,
        ]
        if let html = entry.html { object["html"] = html }
        return object
    }
    let data = try! JSONSerialization.data(
        withJSONObject: objects,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    print(String(decoding: data, as: UTF8.self))
}

func printList(_ entries: [Entry]) {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    for (index, entry) in entries.enumerated() {
        let snippet = entry.text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ⏎ ")
            .prefix(100)
        print("\(index + 1)\t\(formatter.string(from: entry.date))\t\(entry.appName)\t\(snippet)")
    }
}

// MARK: - Commands

func intFlag(_ name: String, in arguments: inout [String], default defaultValue: Int) -> Int {
    guard let index = arguments.firstIndex(of: name) else { return defaultValue }
    guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else {
        fail("\(name) needs a number")
    }
    arguments.removeSubrange(index...(index + 1))
    return value
}

func boolFlag(_ name: String, in arguments: inout [String]) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

let usage = """
marker-cli — Marker's selection history from the terminal

USAGE
  marker-cli latest              print the most recent selection
  marker-cli history [-n 20] [--json]
                                 list recent selections, newest first
  marker-cli search <query> [-n 20] [--json]
                                 case-insensitive search in text and app name
  marker-cli copy [N]            put the Nth newest entry on the clipboard
                                 (1 = newest, default), with RTF/HTML intact
  marker-cli add                 read stdin into Marker's history

EXAMPLES
  marker-cli latest | pbcopy
  marker-cli search "TODO" --json | jq -r '.[0].text'
  git log --oneline -1 | marker-cli add
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let json = boolFlag("--json", in: &arguments)
let limit = intFlag("-n", in: &arguments, default: 20)
let command = arguments.first ?? "--help"

switch command {
case "latest":
    guard let entry = recent(limit: 1).first else { fail("history is empty") }
    if json { printJSON([entry]) } else { print(entry.text) }

case "history":
    let entries = recent(limit: limit)
    json ? printJSON(entries) : printList(entries)

case "search":
    guard arguments.count >= 2 else { fail("search needs a query") }
    let entries = search(arguments[1], limit: limit)
    json ? printJSON(entries) : printList(entries)

case "copy":
    let index = arguments.count >= 2 ? Int(arguments[1]) ?? 0 : 1
    guard index >= 1 else { fail("copy takes a 1-based index") }
    let entries = recent(limit: index)
    guard entries.count == index else { fail("only \(entries.count) entries in history") }
    let entry = entries[index - 1]
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(entry.text, forType: .string)
    if let rtf = entry.rtf { pasteboard.setData(rtf, forType: .rtf) }
    if let html = entry.html { pasteboard.setString(html, forType: .html) }

case "add":
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let raw = String(data: data, encoding: .utf8) else { fail("stdin is not UTF-8") }
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { fail("nothing on stdin") }
    let db = openDatabase(readOnly: false)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    let sql = """
    INSERT OR REPLACE INTO items(id, text, text_lc, date, appName, appName_lc, bundleID)
    VALUES(?,?,?,?,?,?,?)
    """
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        fail("insert failed: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 2, text, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 3, text.lowercased(), -1, SQLITE_TRANSIENT)
    sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
    sqlite3_bind_text(statement, 5, "Terminal", -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 6, "terminal", -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 7, "cli.marker.add", -1, SQLITE_TRANSIENT)
    guard sqlite3_step(statement) == SQLITE_DONE else {
        fail("insert failed: \(String(cString: sqlite3_errmsg(db)))")
    }

case "--help", "-h", "help":
    print(usage)

default:
    fail("unknown command '\(command)'\n\n\(usage)")
}
