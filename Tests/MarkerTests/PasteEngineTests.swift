import XCTest
@testable import Marker

@MainActor
final class PasteEngineTests: XCTestCase {
    private var pasteboard: FakePasteboard!
    private var keys: FakeKeys!
    private var scheduler: FakeScheduler!
    private var engine: PasteEngine!
    private var clock: Date!

    override func setUp() async throws {
        pasteboard = FakePasteboard()
        keys = FakeKeys()
        scheduler = FakeScheduler()
        clock = Date(timeIntervalSince1970: 1_000_000)
        engine = PasteEngine(
            pasteboard: pasteboard,
            keys: keys,
            scheduler: scheduler,
            now: { [unowned self] in self.clock }
        )
    }

    func testPastesImmediatelyWhenModifiersAlreadyReleased() {
        pasteboard.writeString("previous")
        keys.modifiersHeld = false

        engine.pasteIntoActiveApp("new selection")

        XCTAssertEqual(pasteboard.current, "new selection")
        XCTAssertEqual(keys.pasteCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 1, "only the restore job should be queued")
    }

    func testRestoresPreviousClipboardAfterDelay() {
        pasteboard.writeString("previous")
        keys.modifiersHeld = false

        engine.pasteIntoActiveApp("new selection")
        scheduler.runAll()

        XCTAssertEqual(pasteboard.restoredValues, ["previous"])
        XCTAssertEqual(pasteboard.current, "previous")
    }

    func testWaitsForModifierReleaseBeforePasting() {
        pasteboard.writeString("previous")
        keys.modifiersHeld = true

        engine.pasteIntoActiveApp("new selection")

        XCTAssertEqual(pasteboard.current, "previous", "must not paste while modifiers still held")
        XCTAssertEqual(keys.pasteCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1, "should be polling, not pasting yet")

        keys.modifiersHeld = false
        scheduler.runNext()

        XCTAssertEqual(pasteboard.current, "new selection")
        XCTAssertEqual(keys.pasteCount, 1)
    }

    func testKeepsPollingWhileModifiersStayHeld() {
        keys.modifiersHeld = true

        engine.pasteIntoActiveApp("new selection")
        scheduler.runNext() // still held
        scheduler.runNext() // still held

        XCTAssertEqual(keys.pasteCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1, "each poll re-schedules exactly one more poll")
    }

    func testForcesPasteAfterDeadlineEvenIfModifiersStillHeld() {
        var config = PasteEngine.Config()
        config.modifierWait = 1.0
        engine = PasteEngine(
            pasteboard: pasteboard,
            keys: keys,
            scheduler: scheduler,
            config: config,
            now: { [unowned self] in self.clock }
        )
        keys.modifiersHeld = true

        engine.pasteIntoActiveApp("new selection")
        XCTAssertEqual(keys.pasteCount, 0)

        clock = clock.addingTimeInterval(1.1) // past the deadline
        scheduler.runNext()

        XCTAssertEqual(keys.pasteCount, 1, "deadline must win over still-held modifiers")
        XCTAssertEqual(pasteboard.current, "new selection")
    }

    func testPastesRichContentAndRestoresPlainBoard() {
        pasteboard.writeString("previous")
        keys.modifiersHeld = false
        let rtf = Data("rtf".utf8)

        engine.pasteIntoActiveApp(RichText(plain: "styled", rtf: rtf, html: "<b>styled</b>"))

        XCTAssertEqual(pasteboard.current, "styled")
        XCTAssertEqual(pasteboard.currentRTF, rtf)
        XCTAssertEqual(pasteboard.currentHTML, "<b>styled</b>")

        scheduler.runAll()
        XCTAssertEqual(pasteboard.current, "previous")
        XCTAssertNil(pasteboard.currentRTF, "restore must bring back the pre-paste flavors")
    }

    func testSnapshotIsTakenBeforeWritingNewText() {
        pasteboard.writeString("previous")
        keys.modifiersHeld = false

        engine.pasteIntoActiveApp("new selection")
        scheduler.runAll()

        // If the snapshot were taken after the write, restore would put back "new selection" instead.
        XCTAssertEqual(pasteboard.restoredValues, ["previous"])
    }

    func testDiagnosticsCorrelateDelayedPasteWithoutRecordingContent() {
        var events: [String] = []
        engine = PasteEngine(
            pasteboard: pasteboard,
            keys: keys,
            scheduler: scheduler,
            now: { [unowned self] in self.clock },
            log: { [unowned self] message in
                if message.hasPrefix("paste.committed") {
                    XCTAssertEqual(self.keys.pasteCount, 1, "Commit must follow event dispatch")
                }
                events.append(message)
            }
        )
        pasteboard.writeString("private previous clipboard")
        keys.modifiersHeld = true

        engine.pasteIntoActiveApp(
            RichText(plain: "private selected content"),
            operationID: "repro-123"
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].hasPrefix("paste.scheduled operation=repro-123"))
        XCTAssertEqual(keys.pasteCount, 0)

        keys.modifiersHeld = false
        scheduler.runNext()
        XCTAssertEqual(events.last, "paste.committed operation=repro-123")
        scheduler.runAll()
        XCTAssertEqual(events.last, "paste.clipboard_restored operation=repro-123")
        XCTAssertEqual(pasteboard.current, "private previous clipboard")
        XCTAssertFalse(events.joined().contains("private"))
    }

    func testInvalidTargetRejectsWithoutConsumingClickOrTouchingClipboard() {
        pasteboard.writeString("previous")
        var committed = false
        let accepted = engine.pasteIntoActiveApp(
            RichText(plain: "selection"),
            ifStillValid: { false },
            onCommit: { committed = true }
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(pasteboard.current, "previous")
        XCTAssertEqual(keys.pasteCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(committed)
    }

    func testFocusChangeDuringModifierWaitCancelsWithoutRetractionOrFeedback() {
        pasteboard.writeString("previous")
        keys.modifiersHeld = true
        var valid = true
        var committed = false
        var feedback = false
        engine.onPaste = { feedback = true }

        XCTAssertTrue(engine.pasteIntoActiveApp(
            RichText(plain: "selection"),
            ifStillValid: { valid },
            onCommit: { committed = true }
        ))
        valid = false
        keys.modifiersHeld = false
        scheduler.runAll()

        XCTAssertEqual(keys.pasteCount, 0)
        XCTAssertEqual(pasteboard.current, "previous")
        XCTAssertTrue(pasteboard.restoredValues.isEmpty, "Cancellation should not write clipboard")
        XCTAssertFalse(committed, "History retraction must only run after dispatch")
        XCTAssertFalse(feedback)
    }

    func testFocusChangeDuringSnapshotDoesNotWriteClipboard() {
        pasteboard.writeString("previous")
        var valid = true
        pasteboard.onSnapshot = { valid = false }

        XCTAssertFalse(engine.pasteIntoActiveApp(
            RichText(plain: "selection"),
            ifStillValid: { valid },
            onCommit: { XCTFail("Cancelled paste must not commit") }
        ))

        XCTAssertEqual(pasteboard.current, "previous")
        XCTAssertEqual(keys.pasteCount, 0)
        XCTAssertTrue(pasteboard.restoredValues.isEmpty)
    }

    func testFocusChangeDuringTemporaryWriteRestoresClipboardWithoutPasting() {
        pasteboard.writeString("previous")
        var valid = true
        pasteboard.onWriteContent = { valid = false }

        XCTAssertFalse(engine.pasteIntoActiveApp(
            RichText(plain: "selection"),
            ifStillValid: { valid },
            onCommit: { XCTFail("Cancelled paste must not commit") }
        ))

        XCTAssertEqual(keys.pasteCount, 0)
        XCTAssertEqual(pasteboard.current, "previous")
        XCTAssertEqual(pasteboard.restoredValues, ["previous"])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testCommitAndFeedbackRunOnlyAfterPasteDispatch() {
        var events: [String] = []
        engine.onPaste = { [unowned self] in
            XCTAssertEqual(self.keys.pasteCount, 1)
            events.append("feedback")
        }

        XCTAssertTrue(engine.pasteIntoActiveApp(
            RichText(plain: "selection"),
            ifStillValid: { true },
            onCommit: { [unowned self] in
                XCTAssertEqual(self.keys.pasteCount, 1)
                events.append("commit")
            }
        ))

        XCTAssertEqual(events, ["commit", "feedback"])
    }
}
