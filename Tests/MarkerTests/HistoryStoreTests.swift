import XCTest
@testable import Marker

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var db: InMemoryHistoryDatabase!
    private var store: HistoryStore!
    private var clock: Date!

    private let telegram = SourceApp(pid: 1, bundleID: "org.telegram", name: "Telegram", isSelf: false)
    private let chrome = SourceApp(pid: 2, bundleID: "com.google.Chrome", name: "Google Chrome", isSelf: false)

    override func setUp() async throws {
        db = InMemoryHistoryDatabase()
        clock = Date(timeIntervalSince1970: 1_000_000)
        store = HistoryStore(db: db, now: { [unowned self] in self.clock })
    }

    func testTrimsAndDedupesWhitespaceVariants() {
        store.push(text: "hello", app: telegram)
        store.push(text: "hello \n", app: telegram)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(db.count(), 1)
        XCTAssertEqual(store.items[0].text, "hello")
    }

    func testRefinementExtendReplacesPreviousEntry() {
        store.push(text: "Оформить", app: telegram)
        clock = clock.addingTimeInterval(2)
        store.push(text: "Оформить таблицу по полям расчета", app: telegram)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(db.count(), 1, "replaced entry must be deleted from the database too")
        XCTAssertEqual(store.items[0].text, "Оформить таблицу по полям расчета")
    }

    func testRefinementShrinkReplacesPreviousEntry() {
        store.push(text: "hello world", app: telegram)
        clock = clock.addingTimeInterval(2)
        store.push(text: "hello", app: telegram)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].text, "hello")
    }

    func testRefinementWindowExpires() {
        store.push(text: "Оформить", app: telegram)
        clock = clock.addingTimeInterval(60)
        store.push(text: "Оформить таблицу", app: telegram)

        XCTAssertEqual(store.items.count, 2, "old entry survives outside the window")
    }

    func testRefinementRequiresSameApp() {
        store.push(text: "hello", app: telegram)
        clock = clock.addingTimeInterval(2)
        store.push(text: "hello world", app: chrome)

        XCTAssertEqual(store.items.count, 2)
    }

    func testDuplicateTextMovesToTopAndStaysUniqueInDB() {
        store.push(text: "first", app: telegram)
        clock = clock.addingTimeInterval(60)
        store.push(text: "second", app: telegram)
        clock = clock.addingTimeInterval(60)
        store.push(text: "first", app: chrome)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(db.count(), 2)
        XCTAssertEqual(store.items[0].text, "first")
        XCTAssertEqual(store.items[0].appName, "Google Chrome")
    }

    func testLoadsRecentWindowAndPaginates() {
        for i in 0..<45 {
            db.insert(SelectionItem(
                id: UUID(), text: "item \(i)",
                date: clock.addingTimeInterval(Double(i)),
                appName: "Telegram", bundleID: "org.telegram"
            ))
        }
        let paged = HistoryStore(db: db, pageSize: 20, now: { self.clock })

        XCTAssertEqual(paged.items.count, 20)
        XCTAssertTrue(paged.canLoadMore)
        XCTAssertEqual(paged.items.first?.text, "item 44", "newest first")

        paged.loadMore()
        XCTAssertEqual(paged.items.count, 40)
        paged.loadMore()
        XCTAssertEqual(paged.items.count, 45)
        XCTAssertFalse(paged.canLoadMore)
    }

    func testSearchHitsWholeDatabaseNotJustWindow() {
        for i in 0..<30 {
            db.insert(SelectionItem(
                id: UUID(), text: "entry \(i)",
                date: clock.addingTimeInterval(Double(i)),
                appName: "Telegram", bundleID: "org.telegram"
            ))
        }
        db.insert(SelectionItem(
            id: UUID(), text: "ancient needle",
            date: clock.addingTimeInterval(-100_000),
            appName: "Telegram", bundleID: "org.telegram"
        ))
        let paged = HistoryStore(db: db, pageSize: 10, now: { self.clock })

        XCTAssertEqual(paged.items.count, 10, "window is small")
        let hits = paged.search(text: "needle", bundleID: nil)
        XCTAssertEqual(hits.map(\.text), ["ancient needle"], "search reaches beyond the window")
    }

    func testClearEmptiesStoreAndDatabase() {
        store.push(text: "a", app: telegram)
        store.clear()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(db.count(), 0)
        XCTAssertFalse(store.canLoadMore)
    }
}