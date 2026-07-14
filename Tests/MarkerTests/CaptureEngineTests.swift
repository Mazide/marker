import XCTest
@testable import Marker

@MainActor
final class CaptureEngineTests: XCTestCase {
    private var pasteboard: FakePasteboard!
    private var keys: FakeKeys!
    private var reader: FakeSelectionReader!
    private var frontmost: FakeFrontmost!
    private var scheduler: FakeScheduler!
    private var engine: CaptureEngine!
    private var captures: [(text: String, app: SourceApp, viaAX: Bool)] = []
    private var capturedContents: [RichText] = []
    private var clock: Date!

    override func setUp() async throws {
        pasteboard = FakePasteboard()
        keys = FakeKeys()
        reader = FakeSelectionReader()
        frontmost = FakeFrontmost()
        scheduler = FakeScheduler()
        clock = Date(timeIntervalSince1970: 1_000_000)
        captures = []
        capturedContents = []
        engine = CaptureEngine(
            selection: reader,
            pasteboard: pasteboard,
            keys: keys,
            frontmost: frontmost,
            scheduler: scheduler,
            now: { [unowned self] in self.clock }
        )
        engine.onCapture = { [unowned self] content, app, viaAX in
            self.captures.append((content.plain, app, viaAX))
            self.capturedContents.append(content)
        }
    }

    // MARK: - Gesture: AX-first

    func testGestureCapturesAXSelection() {
        engine.mouseDown()
        reader.selection = "  hello world \n" // selected during the drag
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].text, "hello world")
        XCTAssertTrue(captures[0].viaAX)
        XCTAssertEqual(keys.copyCount, 0, "no Cmd+C when AX delivered")
    }

    func testEmptyAXInProvenAppNeverFallsBack() {
        // Prove AX support first.
        engine.mouseDown()
        reader.selection = "first"
        engine.selectionGesture()
        scheduler.runAll()

        // Now an empty-selection drag (e.g. scroll) in the same app.
        reader.selection = nil
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(keys.copyCount, 0, "proven-AX app must not trigger Cmd+C")
    }

    func testEditableFieldCaptureDoesNotDisableFallback() {
        // Hybrid app (Telegram): the input box is AX-visible, the message
        // list is not. A capture from the input box must not mark the app
        // AX-proven, or list selections lose the Cmd+C fallback.
        engine.mouseDown()
        reader.selection = "typed draft"
        reader.focusedRole = "AXTextArea"
        engine.selectionGesture()
        scheduler.runAll()
        XCTAssertEqual(captures.count, 1)

        // Selection in the AX-blind message list.
        reader.selection = nil
        reader.focusedRole = nil
        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message text")
        }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(keys.copyCount, 1, "fallback must survive an input-box capture")
        XCTAssertEqual(captures.map(\.text), ["typed draft", "message text"])
    }

    func testStaleFocusedFieldSelectionDoesNotShadowFallback() {
        // The input box keeps focus and keeps reporting its old selection
        // while the user drags in the AX-blind message list. The stale
        // (deduped) AX read must fall through to the Cmd+C fallback.
        engine.mouseDown()
        reader.selection = "draft"
        reader.focusedRole = "AXTextArea"
        engine.selectionGesture()
        scheduler.runAll()
        XCTAssertEqual(captures.map(\.text), ["draft"])

        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message text")
        }
        engine.mouseDown()
        engine.selectionGesture() // AX still reports "draft"
        scheduler.runAll()

        XCTAssertEqual(keys.copyCount, 1, "stale AX text must not block the fallback")
        XCTAssertEqual(captures.map(\.text), ["draft", "message text"])
    }

    func testStaleNotificationAfterGestureCaptureIsSuppressed() {
        // Dragging in the AX-blind list triggers the input box to re-report
        // its old selection; the debounced notification lands right after
        // the fallback capture and must not clobber it.
        engine.mouseDown()
        reader.selection = "old input text"
        reader.focusedRole = "AXTextArea"
        engine.selectionGesture()
        scheduler.runAll()

        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message text")
        }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll() // fallback captures the list selection

        // The input box re-reported during the drag; the debounced
        // notification lands after the fallback capture.
        engine.axSelectionChanged()
        scheduler.runAll()

        XCTAssertEqual(
            captures.map(\.text), ["old input text", "message text"],
            "the stale notification must not re-capture the input text")

        // A genuinely new selection after the quiet window still lands.
        clock = clock.addingTimeInterval(2)
        reader.selection = "fresh keyboard selection"
        engine.axSelectionChanged()
        scheduler.runAll()
        XCTAssertEqual(captures.last?.text, "fresh keyboard selection")
    }

    func testLateReReportedSelectionIsSuppressed() {
        // Clicking around the app makes the focused input re-report its
        // old selection long after the quiet window; only a changed text
        // counts as a user selection.
        reader.selection = "old input text"
        reader.focusedRole = "AXTextArea"
        engine.axSelectionChanged()
        scheduler.runAll()
        XCTAssertEqual(captures.map(\.text), ["old input text"])

        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message text")
        }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()
        XCTAssertEqual(captures.map(\.text), ["old input text", "message text"])

        // Same stale text re-reported seconds later.
        clock = clock.addingTimeInterval(3)
        engine.axSelectionChanged()
        scheduler.runAll()
        XCTAssertEqual(captures.count, 2, "re-report must not clobber the capture")

        // A genuinely new selection in the input still lands.
        reader.selection = "new input text"
        engine.axSelectionChanged()
        scheduler.runAll()
        XCTAssertEqual(captures.last?.text, "new input text")

        // The old stale text keeps coming back after new captures land in
        // between; it stays suppressed (recent-captures ring, not a
        // single-slot memory).
        clock = clock.addingTimeInterval(3)
        reader.selection = "old input text"
        engine.axSelectionChanged()
        scheduler.runAll()
        XCTAssertEqual(
            captures.last?.text, "new input text",
            "a re-report of any recently captured text must be suppressed")
    }

    func testGestureIgnoresSelectionItDidNotChange() {
        // Input box holds "draft". Other captures happened since, so plain
        // dedupe does not protect. A drag in the AX-blind list still reads
        // "draft" from the focused input — unchanged across the gesture,
        // so it must be distrusted and the fallback must win.
        engine.mouseDown()
        reader.selection = "draft"
        reader.focusedRole = "AXTextArea"
        engine.selectionGesture()
        scheduler.runAll()

        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message one")
        }
        engine.mouseDown() // input still reports "draft": snapshot taken
        engine.selectionGesture()
        scheduler.runAll()
        XCTAssertEqual(captures.map(\.text), ["draft", "message one"])

        // lastReported is now "message one"; the stale "draft" would pass
        // dedupe — the mouse-down snapshot must stop it.
        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message two")
        }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(
            captures.map(\.text), ["draft", "message one", "message two"],
            "the unchanged focused-field text must never win over the fallback")
    }

    func testContentCaptureStillProvesApp() {
        // A read-only AX capture (browser page) proves the app: later
        // empty drags must not synthesize Cmd+C.
        engine.mouseDown()
        reader.selection = "page text"
        reader.focusedRole = "AXWebArea"
        engine.selectionGesture()
        scheduler.runAll()

        reader.selection = nil
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(keys.copyCount, 0)
        XCTAssertEqual(captures.count, 1)
    }

    // MARK: - Rich flavors

    func testAXCaptureCarriesMatchingRichFlavors() {
        let rtf = Data("rtf-bytes".utf8)
        engine.mouseDown()
        reader.selection = "  hello world \n"
        reader.richSelection = RichText(plain: "hello world", rtf: rtf, html: "<b>hello world</b>")
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(capturedContents.count, 1)
        XCTAssertEqual(capturedContents[0].plain, "hello world")
        XCTAssertEqual(capturedContents[0].rtf, rtf)
        XCTAssertEqual(capturedContents[0].html, "<b>hello world</b>")
    }

    func testMismatchedRichReadIsDropped() {
        engine.mouseDown()
        reader.selection = "hello world"
        reader.richSelection = RichText(plain: "something else", rtf: Data("x".utf8))
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(capturedContents.count, 1)
        XCTAssertNil(capturedContents[0].rtf, "flavors for a different text must not attach")
        XCTAssertNil(capturedContents[0].html)
    }

    func testFallbackCaptureCarriesPasteboardFlavors() {
        let rtf = Data("telegram-rtf".utf8)
        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("message text", rtf: rtf, html: "<i>message text</i>")
        }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(capturedContents.count, 1)
        XCTAssertEqual(capturedContents[0].rtf, rtf)
        XCTAssertEqual(capturedContents[0].html, "<i>message text</i>")
        XCTAssertEqual(pasteboard.currentRTF, nil, "previous clipboard must be restored")
    }

    func testDelayedEditableCommitKeepsFlavors() {
        engine.mouseDown()
        reader.selection = "draft"
        reader.richSelection = RichText(plain: "draft", rtf: Data("d".utf8))
        reader.focusedRole = "AXTextArea"
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(capturedContents.count, 1)
        XCTAssertEqual(capturedContents[0].rtf, Data("d".utf8))
    }

    // MARK: - Gesture: self-copy-on-select apps

    func testSelfCopyIsCapturedAndClipboardRestored() {
        pasteboard.externalWrite("user's clipboard")
        reader.selection = nil

        engine.mouseDown() // snapshot taken here
        pasteboard.externalWrite("terminal selection") // app copies on select
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].text, "terminal selection")
        XCTAssertFalse(captures[0].viaAX)
        XCTAssertEqual(pasteboard.current, "user's clipboard", "clipboard must be restored")
        XCTAssertEqual(keys.copyCount, 0)
    }

    // MARK: - Gesture: Cmd+C fallback

    func testFallbackCopiesAndRestoresClipboard() {
        pasteboard.externalWrite("user's clipboard")
        reader.selection = nil
        keys.onCopy = { [unowned self] in
            self.pasteboard.externalWrite("fallback text")
        }

        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(keys.copyCount, 1)
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].text, "fallback text")
        XCTAssertEqual(pasteboard.current, "user's clipboard")
    }

    func testFallbackGivesUpWhenClipboardNeverChanges() {
        pasteboard.externalWrite("user's clipboard")
        reader.selection = nil

        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(keys.copyCount, 1)
        XCTAssertTrue(captures.isEmpty)
        XCTAssertEqual(pasteboard.current, "user's clipboard", "clipboard untouched")
        XCTAssertTrue(pasteboard.restoredValues.isEmpty, "no restore when nothing changed")
    }

    func testFallbackSkipsFileCopies() {
        reader.selection = nil
        keys.onCopy = { [unowned self] in
            self.pasteboard.fileURLsOnBoard = true
            self.pasteboard.externalWrite("/Users/x/file.png")
        }

        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertTrue(captures.isEmpty, "Finder file copies are not selections")
    }

    func testNonTextRoleUnderCursorSkipsFallback() {
        reader.selection = nil
        reader.roleAtMouse = "AXScrollBar"

        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(keys.copyCount, 0, "drag on a scrollbar must not synthesize Cmd+C")
        XCTAssertTrue(captures.isEmpty)
    }

    // MARK: - AX notifications and keystroke intent

    func testProgrammaticSelectionAfterPlainKeystrokeIsSkipped() {
        reader.selection = "https://url-selected-by-cmd-l.example"
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true) // e.g. Cmd+L
        engine.axSelectionChanged()
        scheduler.runAll()

        XCTAssertTrue(captures.isEmpty)
    }

    func testSelectionIntentKeystrokeIsCaptured() {
        reader.selection = "selected via shift+arrows"
        engine.keyDown(isSelectionIntent: true, isPlainTyping: false)
        engine.axSelectionChanged()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].text, "selected via shift+arrows")
    }

    func testMouseSelectionLongAfterKeystrokeIsCaptured() {
        reader.selection = "mouse selection"
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)
        clock = clock.addingTimeInterval(5) // intent window passed
        engine.axSelectionChanged()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
    }

    func testDebounceCoalescesNotificationBursts() {
        reader.selection = "final"
        engine.axSelectionChanged()
        engine.axSelectionChanged()
        engine.axSelectionChanged()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1, "one capture per burst")
    }

    // MARK: - Dedupe

    func testSameTextIsNotCapturedTwice() {
        engine.mouseDown()
        reader.selection = "same"
        engine.selectionGesture()
        scheduler.runAll()

        // Re-drag over the same text: the click collapses the selection,
        // the drag re-creates it.
        reader.selection = nil
        engine.mouseDown()
        reader.selection = "same"
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
    }

    func testGestureInOwnAppIsIgnored() {
        frontmost.app = SourceApp(pid: 99, bundleID: "dev.looseconfetti.marker", name: "Marker", isSelf: true)
        reader.selection = "own popover text"
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertTrue(captures.isEmpty)
    }

    // MARK: - Select-to-edit suppression (delayed commit)

    private func gestureCapture(_ text: String, focusedRole: String) {
        reader.selection = nil // the click collapses any previous selection
        engine.mouseDown()
        reader.selection = text
        reader.focusedRole = focusedRole
        engine.selectionGesture()
    }

    func testEditableCaptureCommitsAfterQuietDelay() {
        gestureCapture("draft sentence", focusedRole: "AXTextArea")
        scheduler.runNext() // settle -> schedules delayed commit
        XCTAssertTrue(captures.isEmpty, "not committed before the delay")
        scheduler.runAll()  // delay elapses

        XCTAssertEqual(captures.map(\.text), ["draft sentence"])
    }

    func testTypingDuringDelayDropsCaptureSilently() {
        gestureCapture("draft sentence", focusedRole: "AXTextArea")
        scheduler.runNext() // settle -> pending commit
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)
        scheduler.runAll()

        XCTAssertTrue(captures.isEmpty)
    }

    func testDroppedTextCanBeCapturedAgainLater() {
        gestureCapture("same words", focusedRole: "AXTextArea")
        scheduler.runNext()
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)
        scheduler.runAll()

        gestureCapture("same words", focusedRole: "AXTextArea")
        scheduler.runAll()
        XCTAssertEqual(captures.map(\.text), ["same words"], "dedupe must not eat the re-selection")
    }

    func testShortcutDuringDelayStillCommits() {
        gestureCapture("copied via cmd+c", focusedRole: "AXTextArea")
        scheduler.runNext()
        engine.keyDown(isSelectionIntent: false, isPlainTyping: false) // ⌘C
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
    }

    func testReadOnlyContextCommitsInstantly() {
        gestureCapture("article text", focusedRole: "AXWebArea")
        scheduler.runNext() // settle job only

        XCTAssertEqual(captures.count, 1, "no delay outside editable fields")
    }

    func testFallbackCaptureCommitsInstantly() {
        reader.selection = nil
        reader.focusedRole = "AXTextArea"
        engine.mouseDown()
        pasteboard.externalWrite("ls -la output")
        engine.selectionGesture()
        scheduler.runNext() // settle: self-copy path

        XCTAssertEqual(captures.count, 1, "terminal self-copy is never delayed")
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)
        XCTAssertEqual(captures.count, 1, "typing after commit changes nothing")
    }
}
