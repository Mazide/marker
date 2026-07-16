import Foundation
import SQLite3

/// History storage in a SQLite file. Case-insensitive search works for
/// non-ASCII (SQLite's LOWER is ASCII-only), because lowercasing happens
/// in Swift into the *_lc columns at insert time.
final class SQLiteHistoryDatabase: HistoryDatabase {
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var db: OpaquePointer?

    static func defaultURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    init(url: URL = SQLiteHistoryDatabase.defaultURL()) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            markerLog.error("sqlite open failed: \(url.path, privacy: .public)")
            sqlite3_close(db)
            db = nil
            return
        }
        // A second connection (a stray second Marker instance, sqlite3 in a
        // terminal) must not turn into dropped writes or an empty-looking
        // history: wait out short locks, and WAL lets readers coexist with
        // the writer instead of failing with SQLITE_BUSY.
        sqlite3_busy_timeout(db, 5000)
        exec("PRAGMA journal_mode=WAL")
        exec("""
        CREATE TABLE IF NOT EXISTS items(
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            text_lc TEXT NOT NULL,
            date REAL NOT NULL,
            appName TEXT NOT NULL,
            appName_lc TEXT NOT NULL,
            bundleID TEXT NOT NULL
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_items_date ON items(date DESC)")
        exec("CREATE INDEX IF NOT EXISTS idx_items_text ON items(text)")
        migrateLegacyJSONIfNeeded(next(to: url))
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - HistoryDatabase

    @discardableResult
    func insert(_ item: SelectionItem) -> Bool {
        execute("""
        INSERT OR REPLACE INTO items(id, text, text_lc, date, appName, appName_lc, bundleID)
        VALUES(?,?,?,?,?,?,?)
        """) { statement in
            bind(statement, 1, item.id.uuidString)
            bind(statement, 2, item.text)
            bind(statement, 3, item.text.lowercased())
            sqlite3_bind_double(statement, 4, item.date.timeIntervalSince1970)
            bind(statement, 5, item.appName)
            bind(statement, 6, item.appName.lowercased())
            bind(statement, 7, item.bundleID)
        }
    }

    func delete(id: UUID) {
        execute("DELETE FROM items WHERE id = ?") { statement in
            bind(statement, 1, id.uuidString)
        }
    }

    func deleteAll(text: String) {
        execute("DELETE FROM items WHERE text = ?") { statement in
            bind(statement, 1, text)
        }
    }

    func deleteOlderThan(_ date: Date) {
        execute("DELETE FROM items WHERE date < ?") { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        }
    }

    func clear() {
        exec("DELETE FROM items")
    }

    func recent(limit: Int, offset: Int) -> [SelectionItem] {
        var result: [SelectionItem] = []
        withStatement("SELECT id, text, date, appName, bundleID FROM items ORDER BY date DESC LIMIT ? OFFSET ?") { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            sqlite3_bind_int(statement, 2, Int32(offset))
            result = rows(statement)
        }
        return result
    }

    func query(text: String?, bundleID: String?, limit: Int) -> [SelectionItem] {
        var sql = "SELECT id, text, date, appName, bundleID FROM items WHERE 1=1"
        if text != nil { sql += " AND (text_lc LIKE ? ESCAPE '\\' OR appName_lc LIKE ? ESCAPE '\\')" }
        if bundleID != nil { sql += " AND bundleID = ?" }
        sql += " ORDER BY date DESC LIMIT ?"

        var result: [SelectionItem] = []
        withStatement(sql) { statement in
            var index: Int32 = 1
            if let text {
                let pattern = "%" + escapeLike(text.lowercased()) + "%"
                bind(statement, index, pattern); index += 1
                bind(statement, index, pattern); index += 1
            }
            if let bundleID {
                bind(statement, index, bundleID); index += 1
            }
            sqlite3_bind_int(statement, index, Int32(limit))
            result = rows(statement)
        }
        return result
    }

    func apps() -> [(bundleID: String, name: String)] {
        var result: [(String, String)] = []
        withStatement("""
        SELECT bundleID, appName FROM items
        WHERE bundleID != '' GROUP BY bundleID ORDER BY appName_lc
        """) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append((column(statement, 0), column(statement, 1)))
            }
        }
        return result
    }

    func count() -> Int {
        var total = 0
        withStatement("SELECT COUNT(*) FROM items") { statement in
            if sqlite3_step(statement) == SQLITE_ROW {
                total = Int(sqlite3_column_int(statement, 0))
            }
        }
        return total
    }

    // MARK: - Legacy JSON migration (pre-0.3)

    private func next(to url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    private func migrateLegacyJSONIfNeeded(_ jsonURL: URL) {
        var legacy: [SelectionItem] = []
        if let data = try? Data(contentsOf: jsonURL),
           let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            legacy = saved
        } else if let data = UserDefaults.standard.data(forKey: "selectionHistory"),
                  let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            legacy = saved
        }
        guard !legacy.isEmpty, count() == 0 else { return }
        for item in legacy {
            insert(item)
        }
        try? FileManager.default.moveItem(
            at: jsonURL,
            to: jsonURL.appendingPathExtension("migrated")
        )
        UserDefaults.standard.removeObject(forKey: "selectionHistory")
        markerLog.info("migrated \(legacy.count) history items to sqlite")
    }

    // MARK: - SQLite helpers

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            markerLog.error("sqlite exec failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
        }
    }

    /// Run a data-changing statement; true only when it ran to completion.
    @discardableResult
    private func execute(_ sql: String, _ bindings: (OpaquePointer?) -> Void) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            markerLog.error("sqlite prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return false
        }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            markerLog.error("sqlite step failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return false
        }
        return true
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            markerLog.error("sqlite prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
        body(statement)
        sqlite3_finalize(statement)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func rows(_ statement: OpaquePointer?) -> [SelectionItem] {
        var result: [SelectionItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(SelectionItem(
                id: UUID(uuidString: column(statement, 0)) ?? UUID(),
                text: column(statement, 1),
                date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                appName: column(statement, 3),
                bundleID: column(statement, 4)
            ))
        }
        return result
    }

    private func escapeLike(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}