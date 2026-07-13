import XCTest
@testable import Marker

final class PasteQueueTests: XCTestCase {
    private var queue = PasteQueue()
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func tick(_ seconds: TimeInterval = 1) {
        clock = clock.addingTimeInterval(seconds)
    }

    func testBurstPastesInSelectionOrder() {
        queue.captured("name", at: clock); tick()
        queue.captured("address", at: clock); tick()
        queue.captured("tracking", at: clock); tick()

        XCTAssertEqual(queue.nextForPaste(at: clock), .init(text: "name", index: 1, total: 3)); tick()
        XCTAssertEqual(queue.nextForPaste(at: clock), .init(text: "address", index: 2, total: 3)); tick()
        XCTAssertEqual(queue.nextForPaste(at: clock), .init(text: "tracking", index: 3, total: 3)); tick()
        XCTAssertNil(queue.nextForPaste(at: clock), "exhausted queue falls back to latest")
    }

    func testSingleCaptureBehavesLikePasteLatest() {
        queue.captured("only", at: clock); tick()

        XCTAssertEqual(queue.nextForPaste(at: clock), .init(text: "only", index: 1, total: 1))
        XCTAssertNil(queue.nextForPaste(at: clock.addingTimeInterval(1)))
    }

    func testGapStartsNewBurst() {
        queue.captured("morning", at: clock)
        tick(300) // long gap
        queue.captured("evening", at: clock); tick()

        XCTAssertEqual(queue.nextForPaste(at: clock)?.text, "evening")
        tick()
        XCTAssertNil(queue.nextForPaste(at: clock), "morning selection must not fire later")
    }

    func testStaleQueueExpires() {
        queue.captured("a", at: clock); tick()
        queue.captured("b", at: clock)

        XCTAssertNil(queue.nextForPaste(at: clock.addingTimeInterval(300)), "old burst never pastes")
    }

    func testRefinementReplacesTail() {
        queue.captured("name", at: clock); tick()
        queue.captured("Оформить", at: clock); tick(2)
        queue.captured("Оформить таблицу", at: clock); tick()

        XCTAssertEqual(queue.nextForPaste(at: clock)?.text, "name"); tick()
        XCTAssertEqual(queue.nextForPaste(at: clock)?.text, "Оформить таблицу"); tick()
        XCTAssertNil(queue.nextForPaste(at: clock))
    }

    func testCaptureAfterPartialPasteExtendsBurst() {
        queue.captured("a", at: clock); tick()
        queue.captured("b", at: clock); tick()
        XCTAssertEqual(queue.nextForPaste(at: clock)?.text, "a"); tick()

        queue.captured("c", at: clock); tick()
        XCTAssertEqual(queue.nextForPaste(at: clock), .init(text: "b", index: 2, total: 3)); tick()
        XCTAssertEqual(queue.nextForPaste(at: clock)?.text, "c")
    }
}