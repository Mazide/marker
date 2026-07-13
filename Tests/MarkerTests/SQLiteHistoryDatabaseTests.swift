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