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
        /// How long a shift+click legitimizes a selection-changed
        /// notification. Long enough to cover the debounce plus a slow
        /// app's re-report, short enough that a tab switch seconds later
        /// cannot ride on stale intent.
        var intentWindow: TimeInterval = 1.5
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
        /// Capturing the same text again within this window is event
        /// double-fire (gesture + notification); after it, it's the user
        /// re-selecting on purpose — recapture so the clipboard is
        /// rewritten even though history and toast stay put.
        var recaptureWindow: TimeInterval = 2.0
        /// AX notifications within this window after one of our own
        /// pastes are the target field reacting to the insert (some
        /// fields select or re-report their content) — capturing that
        /// echo poisons the history with pasted-into text.
        var pasteQuiet: TimeInterval = 2.0
    }

    /// Browsers: their AX attributed reads are near-empty (Chromium
    /// reports colors only and glues paragraphs together), but their own
    /// Cmd+C puts the real HTML on the pasteboard — mouse selections in
    /// these apps capture via synthesized copy, with the AX text as a
    /// backstop when the page suppresses copying.
    static let richViaCopyApps: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser",
        "org.chromium.Chromium",
    ]

    /// Element roles where a drag is not a text selection.
    static let nonTextRoles: Set<String> = [
        "AXScrollBar", "AXSlider", "AXButton", "AXMenuItem", "AXMenu",
        "AXMenuBar", "AXMenuBarItem", "AXPopUpButton", "AXCheckBox",
        "AXRadioButton", "AXToolbar", "AXTabGroup", "AXDisclosureTriangle",
    ]

    var onCapture: ((_ content: RichText, _ app: SourceApp, _ viaAX: Bool) -> Void)?
    /// Delay-and-drop select-to-edit filtering for editable fields.
    var retractionEnabled = true
    /// Rich capture through a synthesized ⌘C in browsers and web views
    /// (their AX attributed reads are near-empty). Off: AX-only capture.
    var richViaCopyEnabled = true
    /// Selections in these apps are never captured. Checked at the entry
    /// gates so the ⌘C fallback can't fire either — synthesizing Copy in
    /// a password manager would put the secret on the clipboard.
    var excludedBundleIDs: Set<String> = []

    private let selection: SelectionReading
    private let pasteboard: PasteboardControlling
    private let keys: KeyEventSynthesizing
    private let frontmost: FrontmostAppProviding
    private let scheduler: Scheduling
    private let config: Config
    private let now: () -> Date

    private var debounceToken: SchedulerToken?
    private var lastReported: String?
    private var lastReportedAt = Date.distantPast
    private var lastExternalPaste = Date.distantPast
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

    /// One of our own pastes just went out; the target field's AX churn
    /// (selecting the inserted text, re-reporting content) must not be
    /// captured as a new selection.
    func externalPasteOccurred() {
        lastExternalPaste = now()
        // Pasting over a pending selection is select-to-replace, the paste
        // flavor of select-to-edit — the selection was a target, not a
        // capture. Drop it before it reaches history (and the toast).
        if let pending = pendingCommit,
           frontmost.frontmostApp()?.bundleID == pending.app.bundleID {
            pending.token.cancel()
            pendingCommit = nil
            lastReported = nil
            markerLog.info("dropped select-to-replace capture (paste)")
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
        guard let app = frontmost.frontmostApp(), !app.isSelf,
              !excludedBundleIDs.contains(app.bundleID)
        else { return }
        let downCount = downChangeCount
        // Give the app a beat to finalize the selection after mouse-up.
        scheduler.schedule(after: config.settleDelay) { [weak self] in
            self?.resolveGesture(app: app, downCount: downCount)
        }
    }

    // MARK: - Decision flow

    private func captureFromAXNotification() {
        if now().timeIntervalSince(lastGestureCapture) < config.notificationQuiet {
            markerLog.debug("skip: notification right after a gesture capture")
            return
        }
        if now().timeIntervalSince(lastExternalPaste) < config.pasteQuiet {
            markerLog.info("skip: notification right after our own paste")
            return
        }
        // Capture is mouse-only: drags and multi-clicks arrive via the
        // gesture path, and the sole selection that exists purely as a
        // notification is a shift+click extension. Keyboard selections
        // (shift+arrows, ⌘A) are deliberately not captured — that is what
        // ⌘C is for. Everything else the notification path delivers — a
        // tab or app switch revealing an old selection, an address bar
        // selecting itself on focus, a page selecting content on load —
        // is the app's doing, not the user's.
        let shiftClickIntent = lastMouseDownWasShift
            && now().timeIntervalSince(lastMouseDown) < config.intentWindow
        guard shiftClickIntent else {
            markerLog.debug("skip: notification without a shift+click behind it")
            return
        }
        guard let app = frontmost.frontmostApp(), !app.isSelf,
              !excludedBundleIDs.contains(app.bundleID),
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
        // Browsers and other web-content hosts: the AX read only confirms
        // the gesture selected text; the flavors (and a plain text with
        // real line breaks) come from the app's own copy.
        if capturesViaCopy(app),
           let text = selection.currentSelection() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != downSelection {
                fallbackCopy(app: app, backstop: text)
                return
            }
        }

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
        // Copy-preferred apps stay fallback-eligible even once proven:
        // a browser can prove AX on one page and go AX-blind on the next
        // (PDF viewer, canvas apps) — without this, captures there are
        // dead until relaunch.
        guard !axProvenApps.contains(app.bundleID) || capturesViaCopy(app) else { return }

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

    /// Whether rich content for this app comes from a synthesized copy
    /// rather than the AX attributed read.
    private func capturesViaCopy(_ app: SourceApp, role: String? = nil) -> Bool {
        guard richViaCopyEnabled else { return false }
        if Self.richViaCopyApps.contains(app.bundleID) { return true }
        // Web content hosted outside a browser (Electron, WKWebView apps)
        // has the same near-empty AX attributes and the same safe Cmd+C.
        return (role ?? selection.focusedElementRole()) == "AXWebArea"
    }

    /// Synthesize Cmd+C, poll for the clipboard to change, grab the text,
    /// restore the previous contents. `backstop` is an already-confirmed
    /// AX selection to commit if the copy never lands (page suppresses
    /// Cmd+C) — plain beats losing the capture.
    private func fallbackCopy(app: SourceApp, backstop: String? = nil) {
        markerLog.debug("fallback Cmd+C for \(app.name, privacy: .public)")
        let before = pasteboard.changeCount
        let saved = pasteboard.snapshot()
        keys.postCopy()
        poll(app: app, before: before, saved: saved, attemptsLeft: config.pollAttempts, backstop: backstop)
    }

    private func poll(app: SourceApp, before: Int, saved: PasteboardSnapshot, attemptsLeft: Int, backstop: String?) {
        scheduler.schedule(after: config.pollInterval) { [weak self] in
            guard let self else { return }
            if self.pasteboard.changeCount != before {
                // A file copy (e.g. Finder) is not a text selection.
                let content = self.pasteboard.containsFileURLs() ? nil : self.pasteboard.readContent()
                self.pasteboard.restore(saved)
                if let content {
                    markerLog.info("fallback captured \(content.plain.count) chars")
                    self.captureFromGesture(content.plain, app: app, viaAX: false, flavors: content)
                } else if let backstop {
                    self.captureFromGesture(backstop, app: app, viaAX: true)
                }
            } else if attemptsLeft > 0 {
                self.poll(app: app, before: before, saved: saved, attemptsLeft: attemptsLeft - 1, backstop: backstop)
            } else {
                // Nothing was copied; clipboard untouched, nothing to restore.
                markerLog.debug("fallback: clipboard never changed")
                if let backstop {
                    self.captureFromGesture(backstop, app: app, viaAX: true)
                }
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

    /// Returns false when the text was empty or a fresh duplicate of the
    /// last capture — the caller may then try other capture paths. The
    /// duplicate check is time-bounded: past recaptureWindow, the same
    /// text is the user re-selecting it to copy it again (their clipboard
    /// may hold something else by now), not an event double-fire.
    /// `flavors` carries rich pasteboard content from the fallback paths;
    /// AX captures fetch their rich version here, after the guards, so a
    /// rejected capture never pays for the attributed AX read.
    @discardableResult
    private func capture(_ rawText: String, app: SourceApp, viaAX: Bool, flavors: RichText? = nil) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text == lastReported,
           now().timeIntervalSince(lastReportedAt) < config.recaptureWindow {
            return false
        }
        lastReported = text
        lastReportedAt = now()
        recentCaptures.removeAll { $0 == text }
        recentCaptures.append(text)
        if recentCaptures.count > recentCapturesLimit {
            recentCaptures.removeFirst()
        }

        let role = selection.focusedElementRole()
        let editable = MiddlePastePolicy.shouldPaste(role: role)

        // An AX capture proves the app only when it came from the app's
        // content, not an editable field. Hybrid apps (Telegram) expose
        // their input box to AX but hide the message list — a capture from
        // the input box must not disable the Cmd+C fallback for the list.
        // Copy-preferred apps never prove: their captures should keep
        // flowing through the synthesized copy.
        if viaAX, !editable, !app.bundleID.isEmpty, !capturesViaCopy(app, role: role) {
            axProvenApps.insert(app.bundleID)
        }

        var content = RichText(plain: text)
        if let flavors {
            content.rtf = flavors.rtf
            content.html = flavors.html
        } else if viaAX, let rich = selection.currentSelectionRich() {
            // Attach only when the attributed read describes the same text;
            // a mismatch means the selection moved on — plain is the truth.
            if rich.plain == text {
                content.rtf = rich.rtf
                content.html = rich.html
            } else {
                markerLog.info("rich: plain mismatch, ax=\(text.count) rich=\(rich.plain.count)")
            }
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