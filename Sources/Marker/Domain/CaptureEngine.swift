import Foundation

/// All capture decision-making, free of AppKit/AX types:
/// - debounces AX selection notifications
/// - filters programmatic selections (Cmd+L, autocomplete) by keystroke intent
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
    }

    /// Element roles where a drag is not a text selection.
    static let nonTextRoles: Set<String> = [
        "AXScrollBar", "AXSlider", "AXButton", "AXMenuItem", "AXMenu",
        "AXMenuBar", "AXMenuBarItem", "AXPopUpButton", "AXCheckBox",
        "AXRadioButton", "AXToolbar", "AXTabGroup", "AXDisclosureTriangle",
    ]

    var onCapture: ((_ text: String, _ app: SourceApp, _ viaAX: Bool) -> Void)?
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

    private struct PendingCommit {
        let text: String
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

    func mouseDown() {
        downChangeCount = pasteboard.changeCount
        downSnapshot = nil
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
        guard let app = frontmost.frontmostApp(), !app.isSelf,
              let text = selection.currentSelection()
        else { return }
        capture(text, app: app, viaAX: true)
    }

    private func resolveGesture(app: SourceApp, downCount: Int) {
        if let text = selection.currentSelection(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            capture(text, app: app, viaAX: true)
            return
        }
        guard !axProvenApps.contains(app.bundleID) else { return }

        // The app copy-on-selected by itself (terminals, TUIs): the
        // selection is already on the clipboard. Take it, then put the
        // user's previous clipboard back.
        if pasteboard.changeCount != downCount {
            let text = pasteboard.readString()
            if let snapshot = downSnapshot {
                pasteboard.restore(snapshot)
                downSnapshot = nil
            }
            if let text {
                markerLog.info("app self-copied \(text.count) chars")
                capture(text, app: app, viaAX: false)
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
                let text = self.pasteboard.containsFileURLs() ? nil : self.pasteboard.readString()
                self.pasteboard.restore(saved)
                if let text {
                    markerLog.info("fallback captured \(text.count) chars")
                    self.capture(text, app: app, viaAX: false)
                }
            } else if attemptsLeft > 0 {
                self.poll(app: app, before: before, saved: saved, attemptsLeft: attemptsLeft - 1)
            } else {
                // Nothing was copied; clipboard untouched, nothing to restore.
                markerLog.debug("fallback: clipboard never changed")
            }
        }
    }

    private func capture(_ rawText: String, app: SourceApp, viaAX: Bool) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastReported else { return }
        lastReported = text
        if viaAX, !app.bundleID.isEmpty {
            axProvenApps.insert(app.bundleID)
        }

        // Editable fields: hold the commit briefly. Typing in the window
        // cancels it (select-to-edit); silence commits it. Fallback
        // (terminal) captures and read-only contexts commit instantly.
        let editable = MiddlePastePolicy.shouldPaste(role: selection.focusedElementRole())
        if retractionEnabled, viaAX, editable {
            pendingCommit?.token.cancel()
            let token = scheduler.schedule(after: config.commitDelay) { [weak self] in
                guard let self, let pending = self.pendingCommit else { return }
                self.pendingCommit = nil
                self.commit(pending.text, app: pending.app, viaAX: pending.viaAX)
            }
            pendingCommit = PendingCommit(text: text, app: app, viaAX: viaAX, token: token)
        } else {
            commit(text, app: app, viaAX: viaAX)
        }
    }

    private func commit(_ text: String, app: SourceApp, viaAX: Bool) {
        markerLog.info("captured \(text.count) chars viaAX=\(viaAX)")
        onCapture?(text, app, viaAX)
    }
}