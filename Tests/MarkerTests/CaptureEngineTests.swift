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
    private var clock: Date!

    override func setUp() async throws {
        pasteboard = FakePasteboard()
        keys = FakeKeys()
        reader = FakeSelectionReader()
        frontmost = FakeFrontmost()
        scheduler = FakeScheduler()
        clock = Date(timeIntervalSince1970: 1_000_000)
        captures = []
        engine = CaptureEngine(
            selection: reader,
            pasteboard: pasteboard,
            keys: keys,
            frontmost: frontmost,
            scheduler: scheduler,
            now: { [unowned self] in self.clock }
        )
        engine.onCapture = { [unowned self] text, app, viaAX in
            self.captures.append((text, app, viaAX))
        }
    }

    // MARK: - Gesture: AX-first

    func testGestureCapturesAXSelection() {
        reader.selection = "  hello world \n"
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].text, "hello world")
        XCTAssertTrue(captures[0].viaAX)
        XCTAssertEqual(keys.copyCount, 0, "no Cmd+C when AX delivered")
    }

    func testEmptyAXInProvenAppNeverFallsBack() {
        // Prove AX support first.
        reader.selection = "first"
        engine.mouseDown()
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
        reader.selection = "same"
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()
        engine.mouseDown()
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

    // MARK: - Select-to-edit retraction

    private var retracted: [String] = []

    private func captureEditable(_ text: String) {
        reader.selection = text
        reader.focusedRole = "AXTextArea"
        engine.onRetract = { [unowned self] in self.retracted.append($0) }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()
    }

    func testTypingRightAfterEditableCaptureRetracts() {
        captureEditable("draft sentence")
        clock = clock.addingTimeInterval(0.5)
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)

        XCTAssertEqual(retracted, ["draft sentence"])
    }

    func testTypingAfterWindowDoesNotRetract() {
        captureEditable("keeper")
        clock = clock.addingTimeInterval(5)
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)

        XCTAssertTrue(retracted.isEmpty)
    }

    func testShortcutAfterCaptureDoesNotRetract() {
        captureEditable("copied via cmd+c")
        clock = clock.addingTimeInterval(0.3)
        engine.keyDown(isSelectionIntent: false, isPlainTyping: false) // e.g. ⌘C

        XCTAssertTrue(retracted.isEmpty)
    }

    func testNonEditableCaptureNeverRetracts() {
        reader.selection = "article text"
        reader.focusedRole = "AXWebArea"
        engine.onRetract = { [unowned self] in self.retracted.append($0) }
        engine.mouseDown()
        engine.selectionGesture()
        scheduler.runAll()
        clock = clock.addingTimeInterval(0.3)
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)

        XCTAssertTrue(retracted.isEmpty, "read-only pages: space-to-scroll must not eat history")
    }

    func testFallbackCaptureNeverRetracts() {
        // terminal-style: AX empty, app self-copied
        reader.selection = nil
        reader.focusedRole = "AXTextArea"
        engine.onRetract = { [unowned self] in self.retracted.append($0) }
        engine.mouseDown()
        pasteboard.externalWrite("ls -la output")
        engine.selectionGesture()
        scheduler.runAll()
        clock = clock.addingTimeInterval(0.3)
        engine.keyDown(isSelectionIntent: false, isPlainTyping: true)

        XCTAssertTrue(retracted.isEmpty, "select output then keep typing is normal terminal use")
    }
}
