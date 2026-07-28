import Foundation
import SQLite3

/// History storage in a SQLite file. Case-insensitive search works for
/// non-ASCII (SQLite's LOWER is ASCII-only), because lowercasing happens
/// in Swift into the *_lc columns at insert time.
final class SQLiteHistoryDatabase: HistoryDatabase {
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let url: URL
    private let busyTimeoutMilliseconds: Int32
    private var db: OpaquePointer?
    private var schemaReady = false

    static func defaultURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    static func recoveryURL() -> URL {
        defaultURL().deletingLastPathComponent()
            .appendingPathComponent("history-recovery.json")
    }

    init(
        url: URL = SQLiteHistoryDatabase.defaultURL(),
        busyTimeoutMilliseconds: Int32 = 5000
    ) {
        self.url = url
        self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
        if openIfNeeded() {
            migrateLegacyJSONIfNeeded(next(to: url))
        }
    }

    deinit {
        close()
    }

    // MARK: - HistoryDatabase

    /// Delete superseded rows and insert their replacement as one commit. A
    /// failed INSERT rolls the deletes back, so refinement/dedupe can never
    /// destroy the last durable copy.
    @discardableResult
    func save(_ item: SelectionItem, deletingIDs: Set<UUID>) -> Bool {
        guard openIfNeeded(), execRaw("BEGIN IMMEDIATE") else { return false }
        var committed = false
        defer {
            if !committed {
                _ = execRaw("ROLLBACK")
            }
        }

        for id in deletingIDs {
            guard executeRaw("DELETE FROM items WHERE id = ?", { statement in
                bind(statement, 1, id.uuidString)
            }) else { return false }
        }
        guard executeRaw("DELETE FROM items WHERE text = ?", { statement in
            bind(statement, 1, item.text)
        }) else { return false }
        guard insertRaw(item) else { return false }
        guard execRaw("COMMIT") else { return false }
        committed = true
        return true
    }

    @discardableResult
    func insert(_ item: SelectionItem) -> Bool {
        save(item, deletingIDs: [])
    }

    private func insertRaw(_ item: SelectionItem) -> Bool {
        executeRaw("""
        INSERT OR REPLACE INTO items(id, text, text_lc, date, appName, appName_lc, bundleID, rtf, html)
        VALUES(?,?,?,?,?,?,?,?,?)
        """) { statement in
            bind(statement, 1, item.id.uuidString)
            bind(statement, 2, item.text)
            bind(statement, 3, item.text.lowercased())
            sqlite3_bind_double(statement, 4, item.date.timeIntervalSince1970)
            bind(statement, 5, item.appName)
            bind(statement, 6, item.appName.lowercased())
            bind(statement, 7, item.bundleID)
            if let rtf = item.rtf {
                rtf.withUnsafeBytes { buffer in
                    _ = sqlite3_bind_blob(statement, 8, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(statement, 8)
            }
            if let html = item.html {
                bind(statement, 9, html)
            } else {
                sqlite3_bind_null(statement, 9)
            }
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
        _ = exec("DELETE FROM items")
    }

    func recent(limit: Int, offset: Int) -> [SelectionItem]? {
        withStatement("SELECT id, text, date, appName, bundleID, rtf, html FROM items ORDER BY date DESC LIMIT ? OFFSET ?") { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            sqlite3_bind_int(statement, 2, Int32(offset))
            return rows(statement)
        }
    }

    func query(text: String?, bundleID: String?, limit: Int) -> [SelectionItem]? {
        var sql = "SELECT id, text, date, appName, bundleID, rtf, html FROM items WHERE 1=1"
        if text != nil { sql += " AND (text_lc LIKE ? ESCAPE '\\' OR appName_lc LIKE ? ESCAPE '\\')" }
        if bundleID != nil { sql += " AND bundleID = ?" }
        sql += " ORDER BY date DESC LIMIT ?"

        return withStatement(sql) { statement in
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
            return rows(statement)
        }
    }

    func apps() -> [(bundleID: String, name: String)]? {
        var result: [(String, String)] = []
        return withStatement("""
        SELECT bundleID, appName FROM items
        WHERE bundleID != '' GROUP BY bundleID ORDER BY appName_lc
        """) { statement in
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    result.append((column(statement, 0), column(statement, 1)))
                case SQLITE_DONE:
                    return result
                default:
                    logCurrentError("sqlite apps read failed")
                    return nil
                }
            }
        }
    }

    func count() -> Int? {
        withStatement("SELECT COUNT(*) FROM items") { statement in
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                return Int(sqlite3_column_int(statement, 0))
            default:
                logCurrentError("sqlite count read failed")
                return nil
            }
        }
    }

    // MARK: - Legacy JSON migration (pre-0.3)

    private func next(to url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    private func migrateLegacyJSONIfNeeded(_ jsonURL: URL) {
        var legacy: [SelectionItem] = []
        let cameFromFile: Bool
        if let data = try? Data(contentsOf: jsonURL),
           let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            legacy = saved
            cameFromFile = true
        } else if let data = UserDefaults.standard.data(forKey: "selectionHistory"),
                  let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            legacy = saved
            cameFromFile = false
        } else {
            cameFromFile = false
        }
        guard !legacy.isEmpty, let existingCount = count(), existingCount == 0 else { return }
        guard insertLegacyBatch(legacy) else {
            markerLog.error("legacy history migration incomplete; source retained for retry")
            return
        }
        if cameFromFile {
            do {
                try FileManager.default.moveItem(
                    at: jsonURL,
                    to: jsonURL.appendingPathExtension("migrated")
                )
            } catch {
                markerLog.error("legacy history archive failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "selectionHistory")
        }
        markerLog.info("migrated \(legacy.count) history items to sqlite")
    }

    private func insertLegacyBatch(_ items: [SelectionItem]) -> Bool {
        guard openIfNeeded(), execRaw("BEGIN IMMEDIATE") else { return false }
        var committed = false
        defer {
            if !committed {
                _ = execRaw("ROLLBACK")
            }
        }
        guard items.allSatisfy({ insertRaw($0) }),
              execRaw("COMMIT")
        else { return false }
        committed = true
        return true
    }

    // MARK: - SQLite helpers

    /// Open and fully migrate the schema before exposing the connection. Any
    /// failure closes it so the next read/write retries from a clean handle
    /// instead of leaving the app in a permanently empty-looking session.
    private func openIfNeeded() -> Bool {
        if schemaReady, db != nil { return true }
        close()

        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            db = handle
            logCurrentError("sqlite open failed")
            close()
            return false
        }
        db = handle
        sqlite3_busy_timeout(db, busyTimeoutMilliseconds)

        guard execRaw("PRAGMA journal_mode=WAL"),
              migrateSchema()
        else {
            close()
            return false
        }
        schemaReady = true
        return true
    }

    /// Existing databases predate the rich-text columns (0.9.x). Schema
    /// changes are one transaction: readers see either the old schema or the
    /// complete new one, never a half-migrated database.
    private func migrateSchema() -> Bool {
        guard execRaw("BEGIN IMMEDIATE") else { return false }
        var committed = false
        defer {
            if !committed {
                _ = execRaw("ROLLBACK")
            }
        }

        guard execRaw("""
        CREATE TABLE IF NOT EXISTS items(
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            text_lc TEXT NOT NULL,
            date REAL NOT NULL,
            appName TEXT NOT NULL,
            appName_lc TEXT NOT NULL,
            bundleID TEXT NOT NULL,
            rtf BLOB,
            html TEXT
        )
        """),
        execRaw("CREATE INDEX IF NOT EXISTS idx_items_date ON items(date DESC)"),
        execRaw("CREATE INDEX IF NOT EXISTS idx_items_text ON items(text)"),
        let columns = tableColumnsRaw()
        else { return false }

        if !columns.contains("rtf"), !execRaw("ALTER TABLE items ADD COLUMN rtf BLOB") {
            return false
        }
        if !columns.contains("html"), !execRaw("ALTER TABLE items ADD COLUMN html TEXT") {
            return false
        }
        guard execRaw("COMMIT") else { return false }
        committed = true
        return true
    }

    private func tableColumnsRaw() -> Set<String>? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(items)", -1, &statement, nil) == SQLITE_OK else {
            logCurrentError("sqlite schema read failed")
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                columns.insert(column(statement, 1))
            case SQLITE_DONE:
                return columns
            default:
                logCurrentError("sqlite schema step failed")
                return nil
            }
        }
    }

    private func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
        schemaReady = false
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard openIfNeeded() else { return false }
        return execRaw(sql)
    }

    @discardableResult
    private func execRaw(_ sql: String) -> Bool {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            logCurrentError("sqlite exec failed")
            return false
        }
        return true
    }

    @discardableResult
    private func execute(_ sql: String, _ bindings: (OpaquePointer?) -> Void) -> Bool {
        guard openIfNeeded() else { return false }
        return executeRaw(sql, bindings)
    }

    /// Run a data-changing statement; true only when it ran to completion.
    @discardableResult
    private func executeRaw(_ sql: String, _ bindings: (OpaquePointer?) -> Void) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logCurrentError("sqlite prepare failed")
            return false
        }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logCurrentError("sqlite step failed")
            return false
        }
        return true
    }

    private func withStatement<T>(
        _ sql: String,
        _ body: (OpaquePointer?) -> T?
    ) -> T? {
        guard openIfNeeded() else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logCurrentError("sqlite prepare failed")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        return body(statement)
    }

    private func logCurrentError(_ prefix: String) {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database handle"
        markerLog.error("\(prefix, privacy: .public): \(message, privacy: .public)")
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func rows(_ statement: OpaquePointer?) -> [SelectionItem]? {
        var result: [SelectionItem] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append(SelectionItem(
                    id: UUID(uuidString: column(statement, 0)) ?? UUID(),
                    text: column(statement, 1),
                    date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    appName: column(statement, 3),
                    bundleID: column(statement, 4),
                    rtf: blobColumn(statement, 5),
                    html: optionalColumn(statement, 6)
                ))
            case SQLITE_DONE:
                return result
            default:
                logCurrentError("sqlite row read failed")
                return nil
            }
        }
    }

    private func blobColumn(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, index)
        else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func optionalColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: cString)
    }

    private func escapeLike(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
