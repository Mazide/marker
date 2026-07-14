import Foundation

/// All capture decision-making, free of AppKit/AX types:
/// - debounces AX selection notifications
/// - filters programmatic selections (Cmd+L, autocomplete, bookmark
///   clicks) by keystroke and click intent
/// - on mouse gestures: AX first, then self-copy detection, then Cmd+C
///   fallback with clipboard restore
@MainActor
final class CaptureEngine {
    struct Config {
        var debounce: TimeInterval = 0.4
        var keyIntentWindow: TimeInterval = 0.8
        var settleDelay: TimeInterval = 0.15
        var pollInterval: TimeInterval = 0.05
        var pollAttempts: Int = 16
        /// Captures from editable fields wait this long before committing;
        /// typing within the window means select-to-edit and the capture is
        /// silently dropped (no toast, no history churn).
        var commitDelay: TimeInterval = 0.5
        /// After a mouse gesture captured, AX notifications are ignored for
        /// this long: a focused text field re-reporting its old selection
        /// during a drag elsewhere (Telegram) must not clobber the capture.
        var notificationQuiet: TimeInterval = 1.0
        /// AX notifications within this window after a plain click are the
        /// app selecting text by itself (clicking a bookmark puts the page
        /// URL selected into the address bar) — real mouse selections
        /// arrive via the gesture path, real keyboard selections carry a
        /// selection-intent keystroke after the click.
        var clickQuiet: TimeInterval = 1.5
    }

    /// Element roles where a drag is not a text selection.
    static let nonTextRoles: Set<String> = [
        "AXScrollBar", "AXSlider", "AXButton", "AXMenuItem", "AXMenu",
        "AXMenuBar", "AXMenuBarItem", "AXPopUpButton", "AXCheckBox",
        "AXRadioButton", "AXToolbar", "AXTabGroup", "AXDisclosureTriangle",
    ]

    var onCapture: ((_ content: RichText, _ app: SourceApp, _ viaAX: Bool) -> Void)?
    /// Delay-and-drop select-to-edit filtering for editable fields.
    var retractionEnabled = true

    private let selection: SelectionReading
    private let pasteboard: PasteboardControlling
    private let keys: KeyEventSynthesizing
    private let frontmost: FrontmostAppProviding
    private let scheduler: Scheduling
    private let config: Config
    private let now: () -> Date

    private var debounceToken: SchedulerToken?
    private var lastKeyDown = Date.distantPast
    private var lastKeyWasSelectionIntent = false
    private var lastReported: String?
    /// Apps that have proven they report selections via AX; for these an
    /// empty AX read means "nothing selected", so never fall back to Cmd+C.
    private var axProvenApps: Set<String> = []
    private var downChangeCount = 0
    private var downSnapshot: PasteboardSnapshot?
    private var downSelection: String?
    private var lastMouseDown = Date.distantPast
    private var lastMouseDownWasShift = false
    private var lastGestureCapture = Date.distantPast
    /// Ring of recently captured texts. Focused text fields re-report
    /// their old selection whenever the user clicks elsewhere in the app
    /// (Telegram's input box) — that text was captured when originally
    /// selected, so a notification matching the ring is a re-report, not
    /// a user selection.
    private var recentCaptures: [String] = []
    private let recentCapturesLimit = 12

    private struct PendingCommit {
        let content: RichText
        let app: SourceApp
        let viaAX: Bool
        let token: SchedulerToken
    }
    private var pendingCommit: PendingCommit?

    init(
        selection: SelectionReading,
        pasteboard: PasteboardControlling,
        keys: KeyEventSynthesizing,
        frontmost: FrontmostAppProviding,
        scheduler: Scheduling,
        config: Config = Config(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.selection = selection
        self.pasteboard = pasteboard
        self.keys = keys
        self.frontmost = frontmost
        self.scheduler = scheduler
        self.config = config
        self.now = now
    }

    // MARK: - Inputs from the system layer

    func keyDown(isSelectionIntent: Bool, isPlainTyping: Bool) {
        lastKeyDown = now()
        lastKeyWasSelectionIntent = isSelectionIntent

        // Typing while an editable-field capture is pending: the selection
        // was made to replace/delete, not to copy — drop it silently.
        if isPlainTyping,
           let pending = pendingCommit,
           frontmost.frontmostApp()?.bundleID == pending.app.bundleID {
            pending.token.cancel()
            pendingCommit = nil
            // Allow the same text to be captured again later on purpose.
            lastReported = nil
            markerLog.info("dropped select-to-edit capture")
        }
    }

    /// AX selection-changed notification; fires on every caret move while
    /// dragging, so debounce until the user settles.
    func axSelectionChanged() {
        debounceToken?.cancel()
        debounceToken = scheduler.schedule(after: config.debounce) { [weak self] in
            self?.captureFromAXNotification()
        }
    }

    func mouseDown(shiftClick: Bool = false) {
        downChangeCount = pasteboard.changeCount
        downSnapshot = nil
        lastMouseDown = now()
        // Shift+click extends a selection: that IS selection intent, and
        // it arrives only as a notification (no drag, no multi-click).
        lastMouseDownWasShift = shiftClick
        // A selection produced by this gesture must differ from whatever
        // the focused element reported before it: a focused text field
        // keeps reporting its old selection while the user drags in an
        // AX-blind part of the app (Telegram input box vs. message list).
        downSelection = selection.currentSelection()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app = frontmost.frontmostApp(), !app.isSelf,
              !axProvenApps.contains(app.bundleID)
        else { return }
        // Snapshot only in fallback-eligible apps so we don't copy
        // pasteboard data on every click system-wide.
        downSnapshot = pasteboard.snapshot()
    }

    /// Mouse-up after a drag or a multi-click.
    func selectionGesture() {
        guard let app = frontmost.frontmostApp(), !app.isSelf else { return }
        let downCount = downChangeCount
        // Give the app a beat to finalize the selection after mouse-up.
        scheduler.schedule(after: config.settleDelay) { [weak self] in
            self?.resolveGesture(app: app, downCount: downCount)
        }
    }

    // MARK: - Decision flow

    private func captureFromAXNotification() {
        if now().timeIntervalSince(lastKeyDown) < config.keyIntentWindow,
           !lastKeyWasSelectionIntent {
            markerLog.debug("skip: selection right after non-selection keystroke")
            return
        }
        if now().timeIntervalSince(lastGestureCapture) < config.notificationQuiet {
            markerLog.debug("skip: notification right after a gesture capture")
            return
        }
        // A plain click just before this notification: the selection is the
        // app's own doing (bookmark click, focus change re-selecting a
        // field). A selection-intent keystroke after the click (shift+arrow
        // following a caret click) or a shift+click still counts as the
        // user selecting.
        if now().timeIntervalSince(lastMouseDown) < config.clickQuiet,
           !lastMouseDownWasShift,
           !(lastKeyDown >= lastMouseDown && lastKeyWasSelectionIntent) {
            markerLog.debug("skip: notification right after a plain click")
            return
        }
        guard let app = frontmost.frontmostApp(), !app.isSelf,
              let text = selection.currentSelection()
        else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recentCaptures.contains(trimmed) else {
            markerLog.info("skip: re-reported selection (\(trimmed.count) chars)")
            return
        }
        capture(text, app: app, viaAX: true)
    }

    private func resolveGesture(app: SourceApp, downCount: Int) {
        // Trust the AX read only when this gesture changed it; an AX text
        // identical to the mouse-down snapshot is a focused field's old
        // selection, not the drag's result. Stale or deduped: keep going —
        // the fallback paths see the real selection.
        if let text = selection.currentSelection() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != downSelection,
               captureFromGesture(text, app: app, viaAX: true) {
                return
            }
            if trimmed == downSelection {
                markerLog.info("gesture: AX text unchanged since mouse-down, trying fallback")
            }
        }
        guard !axProvenApps.contains(app.bundleID) else { return }

        // The app copy-on-selected by itself (terminals, TUIs): the
        // selection is already on the clipboard. Take it, then put the
        // user's previous clipboard back.
        if pasteboard.changeCount != downCount {
            let content = pasteboard.readContent()
            if let snapshot = downSnapshot {
                pasteboard.restore(snapshot)
                downSnapshot = nil
            }
            if let content {
                markerLog.info("app self-copied \(content.plain.count) chars")
                captureFromGesture(content.plain, app: app, viaAX: false, flavors: content)
            }
            return
        }

        if let role = selection.roleAtMouseLocation(),
           Self.nonTextRoles.contains(role) {
            return
        }
        fallbackCopy(app: app)
    }

    /// Synthesize Cmd+C, poll for the clipboard to change, grab the text,
    /// restore the previous contents.
    private func fallbackCopy(app: SourceApp) {
        markerLog.debug("fallback Cmd+C for \(app.name, privacy: .public)")
        let before = pasteboard.changeCount
        let saved = pasteboard.snapshot()
        keys.postCopy()
        poll(app: app, before: before, saved: saved, attemptsLeft: config.pollAttempts)
    }

    private func poll(app: SourceApp, before: Int, saved: PasteboardSnapshot, attemptsLeft: Int) {
        scheduler.schedule(after: config.pollInterval) { [weak self] in
            guard let self else { return }
            if self.pasteboard.changeCount != before {
                // A file copy (e.g. Finder) is not a text selection.
                let content = self.pasteboard.containsFileURLs() ? nil : self.pasteboard.readContent()
                self.pasteboard.restore(saved)
                if let content {
                    markerLog.info("fallback captured \(content.plain.count) chars")
                    self.captureFromGesture(content.plain, app: app, viaAX: false, flavors: content)
                }
            } else if attemptsLeft > 0 {
                self.poll(app: app, before: before, saved: saved, attemptsLeft: attemptsLeft - 1)
            } else {
                // Nothing was copied; clipboard untouched, nothing to restore.
                markerLog.debug("fallback: clipboard never changed")
            }
        }
    }

    /// Gesture-path capture: on success, AX notifications are silenced for
    /// notificationQuiet so a stale re-report cannot clobber this capture.
    @discardableResult
    private func captureFromGesture(_ text: String, app: SourceApp, viaAX: Bool, flavors: RichText? = nil) -> Bool {
        guard capture(text, app: app, viaAX: viaAX, flavors: flavors) else { return false }
        lastGestureCapture = now()
        return true
    }

    /// Returns false when the text was empty or a duplicate of the last
    /// capture — the caller may then try other capture paths. `flavors`
    /// carries rich pasteboard content from the fallback paths; AX captures
    /// fetch their rich version here, after the guards, so a rejected
    /// capture never pays for the attributed AX read.
    @discardableResult
    private func capture(_ rawText: String, app: SourceApp, viaAX: Bool, flavors: RichText? = nil) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastReported else { return false }
        lastReported = text
        recentCaptures.removeAll { $0 == text }
        recentCaptures.append(text)
        if recentCaptures.count > recentCapturesLimit {
            recentCaptures.removeFirst()
        }

        let editable = MiddlePastePolicy.shouldPaste(role: selection.focusedElementRole())

        // An AX capture proves the app only when it came from the app's
        // content, not an editable field. Hybrid apps (Telegram) expose
        // their input box to AX but hide the message list — a capture from
        // the input box must not disable the Cmd+C fallback for the list.
        if viaAX, !editable, !app.bundleID.isEmpty {
            axProvenApps.insert(app.bundleID)
        }

        var content = RichText(plain: text)
        if let flavors {
            content.rtf = flavors.rtf
            content.html = flavors.html
        } else if viaAX, let rich = selection.currentSelectionRich(),
                  rich.plain == text {
            // Attach only when the attributed read describes the same text;
            // a mismatch means the selection moved on — plain is the truth.
            content.rtf = rich.rtf
            content.html = rich.html
        }

        // Editable fields: hold the commit briefly. Typing in the window
        // cancels it (select-to-edit); silence commits it. Fallback
        // (terminal) captures and read-only contexts commit instantly.
        if retractionEnabled, viaAX, editable {
            pendingCommit?.token.cancel()
            let token = scheduler.schedule(after: config.commitDelay) { [weak self] in
                guard let self, let pending = self.pendingCommit else { return }
                self.pendingCommit = nil
                self.commit(pending.content, app: pending.app, viaAX: pending.viaAX)
            }
            pendingCommit = PendingCommit(content: content, app: app, viaAX: viaAX, token: token)
        } else {
            commit(content, app: app, viaAX: viaAX)
        }
        return true
    }

    private func commit(_ content: RichText, app: SourceApp, viaAX: Bool) {
        markerLog.info("captured \(content.plain.count) chars viaAX=\(viaAX) rich=\(content.hasFlavors)")
        onCapture?(content, app, viaAX)
    }
}