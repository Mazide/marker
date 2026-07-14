import SQLite3
import XCTest
@testable import Marker

final class SQLiteHistoryDatabaseTests: XCTestCase {
    private var url: URL!
    private var db: SQLiteHistoryDatabase!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-test-\(UUID().uuidString).sqlite")
        db = SQLiteHistoryDatabase(url: url)
    }

    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func item(_ text: String, app: String = "Telegram", bundleID: String = "org.telegram", offset: TimeInterval = 0) -> SelectionItem {
        SelectionItem(
            id: UUID(), text: text,
            date: Date(timeIntervalSince1970: 1_000_000 + offset),
            appName: app, bundleID: bundleID
        )
    }

    func testInsertAndRecentOrdering() {
        db.insert(item("old", offset: 0))
        db.insert(item("new", offset: 10))

        XCTAssertEqual(db.recent(limit: 10, offset: 0).map(\.text), ["new", "old"])
        XCTAssertEqual(db.count(), 2)
    }

    func testPaginationOffsets() {
        for i in 0..<10 {
            db.insert(item("item \(i)", offset: Double(i)))
        }
        let page2 = db.recent(limit: 3, offset: 3)
        XCTAssertEqual(page2.map(\.text), ["item 6", "item 5", "item 4"])
    }

    func testCaseInsensitiveCyrillicSearch() {
        db.insert(item("Оформить Таблицу"))
        db.insert(item("другое"))

        XCTAssertEqual(db.query(text: "оформить", bundleID: nil, limit: 10).count, 1)
        XCTAssertEqual(db.query(text: "ТАБЛИЦУ", bundleID: nil, limit: 10).count, 1)
    }

    func testSearchMatchesAppName() {
        db.insert(item("some text", app: "Google Chrome", bundleID: "com.google.Chrome"))
        XCTAssertEqual(db.query(text: "chrome", bundleID: nil, limit: 10).count, 1)
    }

    func testLikeWildcardsAreEscaped() {
        db.insert(item("100% done"))
        db.insert(item("100 percent"))

        XCTAssertEqual(db.query(text: "100%", bundleID: nil, limit: 10).map(\.text), ["100% done"])
    }

    func testBundleFilter() {
        db.insert(item("a", app: "Telegram", bundleID: "org.telegram"))
        db.insert(item("b", app: "Chrome", bundleID: "com.google.Chrome", offset: 1))

        XCTAssertEqual(db.query(text: nil, bundleID: "org.telegram", limit: 10).map(\.text), ["a"])
    }

    func testDeleteAllByText() {
        db.insert(item("dup", offset: 0))
        db.insert(item("keep", offset: 1))
        db.deleteAll(text: "dup")

        XCTAssertEqual(db.recent(limit: 10, offset: 0).map(\.text), ["keep"])
    }

    func testRichFlavorsRoundTrip() {
        let rtf = Data("rtf-bytes".utf8)
        db.insert(SelectionItem(
            id: UUID(), text: "styled",
            date: Date(timeIntervalSince1970: 1_000_000),
            appName: "Safari", bundleID: "com.apple.Safari",
            rtf: rtf, html: "<b>styled</b>"
        ))
        db.insert(item("plain", offset: 10))

        let loaded = db.recent(limit: 10, offset: 0)
        XCTAssertNil(loaded[0].rtf)
        XCTAssertNil(loaded[0].html)
        XCTAssertEqual(loaded[1].rtf, rtf)
        XCTAssertEqual(loaded[1].html, "<b>styled</b>")

        let queried = db.query(text: "styled", bundleID: nil, limit: 10)
        XCTAssertEqual(queried.first?.rtf, rtf)
    }

    func testOpensPreRichSchemaAndAddsColumns() {
        // Recreate the 0.9.x schema (no rtf/html), insert a row, then let
        // SQLiteHistoryDatabase migrate it on open.
        db = nil
        try? FileManager.default.removeItem(at: url)
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        sqlite3_exec(raw, """
        CREATE TABLE items(
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            text_lc TEXT NOT NULL,
            date REAL NOT NULL,
            appName TEXT NOT NULL,
            appName_lc TEXT NOT NULL,
            bundleID TEXT NOT NULL
        )
        """, nil, nil, nil)
        sqlite3_exec(raw, """
        INSERT INTO items VALUES('00000000-0000-0000-0000-000000000001',
            'legacy', 'legacy', 1000000, 'Telegram', 'telegram', 'org.telegram')
        """, nil, nil, nil)
        sqlite3_close(raw)

        db = SQLiteHistoryDatabase(url: url)

        let loaded = db.recent(limit: 10, offset: 0)
        XCTAssertEqual(loaded.map(\.text), ["legacy"])
        XCTAssertNil(loaded[0].rtf)

        db.insert(SelectionItem(
            id: UUID(), text: "new",
            date: Date(timeIntervalSince1970: 1_000_100),
            appName: "Safari", bundleID: "com.apple.Safari",
            rtf: Data("r".utf8), html: nil
        ))
        XCTAssertEqual(db.recent(limit: 10, offset: 0).first?.rtf, Data("r".utf8))
    }

    func testDeleteOlderThanCutoff() {
        db.insert(item("old", offset: 0))
        db.insert(item("new", offset: 100))

        db.deleteOlderThan(Date(timeIntervalSince1970: 1_000_000 + 50))

        XCTAssertEqual(db.recent(limit: 10, offset: 0).map(\.text), ["new"])
        XCTAssertEqual(db.count(), 1)
    }

    func testAppsAreDistinct() {
        db.insert(item("a", offset: 0))
        db.insert(item("b", offset: 1))
        db.insert(item("c", app: "Chrome", bundleID: "com.google.Chrome", offset: 2))

        XCTAssertEqual(db.apps().map(\.bundleID).sorted(), ["com.google.Chrome", "org.telegram"])
    }

    func testPersistsAcrossReopen() {
        db.insert(item("survives"))
        db = nil
        db = SQLiteHistoryDatabase(url: url)

        XCTAssertEqual(db.recent(limit: 10, offset: 0).map(\.text), ["survives"])
    }
}