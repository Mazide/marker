import XCTest
@testable import Marker

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var persistence: InMemoryPersistence!
    private var store: HistoryStore!
    private var clock: Date!

    private let telegram = SourceApp(pid: 1, bundleID: "org.telegram", name: "Telegram", isSelf: false)
    private let chrome = SourceApp(pid: 2, bundleID: "com.google.Chrome", name: "Google Chrome", isSelf: false)

    override func setUp() async throws {
        persistence = InMemoryPersistence()
        clock = Date(timeIntervalSince1970: 1_000_000)
        store = HistoryStore(persistence: persistence, now: { [unowned self] in self.clock })
    }

    func testTrimsAndDedupesWhitespaceVariants() {
        store.push(text: "hello", app: telegram)
        store.push(text: "hello \n", app: telegram)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].text, "hello")
    }

    func testRefinementExtendReplacesPreviousEntry() {
        store.push(text: "Оформить", app: telegram)
        clock = clock.addingTimeInterval(2)
        store.push(text: "Оформить таблицу по полям расчета", app: telegram)

        XCTAssertEqual(store.items.count, 1)
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

    func testDuplicateTextMovesToTop() {
        store.push(text: "first", app: telegram)
        clock = clock.addingTimeInterval(60)
        store.push(text: "second", app: telegram)
        clock = clock.addingTimeInterval(60)
        store.push(text: "first", app: chrome)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].text, "first")
        XCTAssertEqual(store.items[0].appName, "Google Chrome")
    }

    func testAppsListIsUniqueAndSorted() {
        store.push(text: "a", app: telegram)
        clock = clock.addingTimeInterval(60)
        store.push(text: "b", app: chrome)
        clock = clock.addingTimeInterval(60)
        store.push(text: "c", app: telegram)

        XCTAssertEqual(store.apps.map(\.name), ["Google Chrome", "Telegram"])
    }

    func testPersistsAcrossInstances() {
        store.push(text: "persisted", app: telegram)
        let reloaded = HistoryStore(persistence: persistence, now: { self.clock })

        XCTAssertEqual(reloaded.items.map(\.text), ["persisted"])
    }
}