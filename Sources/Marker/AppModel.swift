import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation
import ServiceManagement
import Sparkle

/// How the trackpad three-finger paste gesture triggers.
enum ThreeFingerPasteMode: String, CaseIterable {
    case off
    case click
    case doubleTap

    static func fromStoredValue(_ raw: String?, legacyClickEnabled: Bool) -> Self {
        if let raw, let mode = Self(rawValue: raw) { return mode }
        return legacyClickEnabled ? .click : .off
    }
}

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let history = HistoryStore(
        db: SQLiteHistoryDatabase(),
        recoveryURL: SQLiteHistoryDatabase.recoveryURL()
    )
    var axTrusted = AXIsProcessTrusted()

    var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled) {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                markerLog.error("login item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var toastEnabled: Bool = UserDefaults.standard.object(forKey: "toastEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(toastEnabled, forKey: "toastEnabled") }
    }

    static let defaultPasteCombo = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey), label: "⌥V")
    static let defaultHistoryCombo = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | shiftKey), label: "⇧⌥V")

    var pasteHotkey: KeyCombo = AppModel.storedCombo("pasteHotkey") ?? AppModel.defaultPasteCombo {
        didSet { AppModel.store(pasteHotkey, forKey: "pasteHotkey"); registerHotkeys() }
    }
    var historyHotkey: KeyCombo = AppModel.storedCombo("historyHotkey") ?? AppModel.defaultHistoryCombo {
        didSet { AppModel.store(historyHotkey, forKey: "historyHotkey"); registerHotkeys() }
    }

    private static func storedCombo(_ key: String) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private static func store(_ combo: KeyCombo, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: key)
    }

    private func registerHotkeys() {
        hotkey.register([.pasteLatest: pasteHotkey, .showHistory: historyHotkey])
    }

    /// Bundle IDs whose selections are never captured (password managers,
    /// anything private). Enforced inside CaptureEngine, before the ⌘C
    /// fallback can touch the app's clipboard.
    var excludedBundleIDs: [String] = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [] {
        didSet {
            UserDefaults.standard.set(excludedBundleIDs, forKey: "excludedBundleIDs")
            engine.excludedBundleIDs = Set(excludedBundleIDs)
        }
    }

    /// X11-style middle-click paste at the click point. Off by default;
    /// only swallows clicks over editable text (MiddlePastePolicy).
    var middleClickPasteEnabled: Bool = UserDefaults.standard.object(forKey: "middleClickPasteEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(middleClickPasteEnabled, forKey: "middleClickPasteEnabled") }
    }

    /// File trail for the click-paste path (~/Library/Logs/Marker.log), so
    /// a "middle-click didn't paste" report can be diagnosed by copying one
    /// file. Off by default.
    var diagLogEnabled: Bool = UserDefaults.standard.bool(forKey: "diagLogEnabled") {
        didSet {
            UserDefaults.standard.set(diagLogEnabled, forKey: "diagLogEnabled")
            DiagFile.shared.enabled = diagLogEnabled
        }
    }

    /// Trackpad three-finger paste as a middle-click substitute, via the
    /// private MultitouchSupport API — experimental, off by default. Click
    /// is the deliberate trigger; double tap is protected by touch geometry,
    /// AppKit swipe signals, and app/Space change suppression.
    var threeFingerPasteMode: ThreeFingerPasteMode = AppModel.storedThreeFingerPasteMode() {
        didSet {
            UserDefaults.standard.set(threeFingerPasteMode.rawValue, forKey: "threeFingerPasteMode")
            trackpadTap.cancelTapSequence(reason: .modeChanged)
            if threeFingerPasteMode != .off { trackpadTap.start() }
        }
    }

    /// Migration: before the mode picker there was a bool toggle (under
    /// the even older "threeFingerTapEnabled" key) whose only behavior was
    /// the physical click. A stored explicit mode, including double tap,
    /// remains authoritative.
    private static func storedThreeFingerPasteMode() -> ThreeFingerPasteMode {
        let defaults = UserDefaults.standard
        return ThreeFingerPasteMode.fromStoredValue(
            defaults.string(forKey: "threeFingerPasteMode"),
            legacyClickEnabled: defaults.bool(forKey: "threeFingerTapEnabled")
        )
    }

    /// Selections immediately typed over were made to edit, not to copy;
    /// they are removed from history.
    var retractEditedEnabled: Bool = UserDefaults.standard.object(forKey: "retractEditedEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(retractEditedEnabled, forKey: "retractEditedEnabled")
            engine.retractionEnabled = retractEditedEnabled
        }
    }

    /// API keys, tokens and private keys are never written to history.
    var skipSecretsEnabled: Bool = UserDefaults.standard.object(forKey: "skipSecretsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(skipSecretsEnabled, forKey: "skipSecretsEnabled") }
    }

    /// Rich capture through a synthesized ⌘C in browsers and web views,
    /// where the Accessibility read carries almost no formatting.
    var richCopyEnabled: Bool = UserDefaults.standard.object(forKey: "richCopyEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(richCopyEnabled, forKey: "richCopyEnabled")
            engine.richViaCopyEnabled = richCopyEnabled
        }
    }

    /// 0 = keep forever (default: history is unencrypted on disk, see README,
    /// so this is opt-in, not a silent default).
    var historyRetentionDays: Int = UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int ?? 0 {
        didSet {
            UserDefaults.standard.set(historyRetentionDays, forKey: "historyRetentionDays")
            history.applyRetention(days: historyRetentionDays)
        }
    }

    // System layer
    @ObservationIgnored private let pasteboard = SystemPasteboard()
    @ObservationIgnored private let keys = CGEventKeySynthesizer()
    @ObservationIgnored private let scheduler = TimerScheduler()
    @ObservationIgnored private let frontmost = WorkspaceFrontmost()
    @ObservationIgnored private let axMonitor = AXSelectionMonitor()
    @ObservationIgnored private let mouseMonitor = MouseMonitor()
    @ObservationIgnored private let middleClickTap = MiddleClickTap()
    @ObservationIgnored private let trackpadTap = TrackpadTapMonitor()
    @ObservationIgnored private let threeFingerClickTap = ThreeFingerClickTap()
    @ObservationIgnored private let hotkey = HotkeyManager()
    @ObservationIgnored private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @ObservationIgnored private var trustPollTimer: Timer?
    @ObservationIgnored private var retentionTimer: Timer?
    @ObservationIgnored private var tapHealthTimer: Timer?
    /// Mouse-up (or shift-click) point waiting for the capture engine to
    /// confirm that the gesture really selected text.
    @ObservationIgnored private var captureActionAnchor: (
        point: NSPoint,
        selectionCenter: NSPoint?,
        date: Date
    )?
    /// Cursor point for a gesture paste. PasteEngine may wait for modifiers,
    /// so show feedback only when it reaches the actual paste operation.
    @ObservationIgnored private var pendingPasteFeedbackAnchor: NSPoint?
    /// AX identity captured at the beginning of the first tap. It survives
    /// the pair and the late-swipe guard, then must compare equal at paste.
    @ObservationIgnored private var threeFingerTapTarget: FocusedPasteTarget?

    // Domain layer
    @ObservationIgnored private var engine: CaptureEngine!
    @ObservationIgnored private var pasteEngine: PasteEngine!

    init() {
        engine = CaptureEngine(
            selection: axMonitor,
            pasteboard: pasteboard,
            keys: keys,
            frontmost: frontmost,
            scheduler: scheduler
        )
        pasteEngine = PasteEngine(
            pasteboard: pasteboard,
            keys: keys,
            scheduler: scheduler
        )
    }

    func start() {
        axMonitor.onSelectionChanged = { [weak self] in
            self?.engine.axSelectionChanged()
        }
        axMonitor.onFocusedElementChanged = { [weak self] in
            guard let self else { return }
            self.trackpadTap.cancelTapSequence(reason: .focusChanged)
        }
        axMonitor.onKeyDown = { [weak self] isIntent, isTyping, isMarkerSynthetic in
            if !isMarkerSynthetic {
                SelectionActionPresenter.shared.dismiss()
            }
            self?.engine.keyDown(isSelectionIntent: isIntent, isPlainTyping: isTyping)
        }
        engine.retractionEnabled = retractEditedEnabled
        engine.richViaCopyEnabled = richCopyEnabled
        engine.excludedBundleIDs = Set(excludedBundleIDs)
        pasteEngine.onPaste = { [weak self] in
            guard let self else { return }
            self.engine.externalPasteOccurred()
            guard let anchor = self.pendingPasteFeedbackAnchor else { return }
            self.pendingPasteFeedbackAnchor = nil
            SelectionActionPresenter.shared.showPasteConfirmation(at: anchor)
        }
        mouseMonitor.onMouseDown = { [weak self] shiftClick, point in
            SelectionActionPresenter.shared.dismiss()
            if shiftClick {
                self?.captureActionAnchor = (point, nil, Date())
            }
            self?.engine.mouseDown(shiftClick: shiftClick)
        }
        mouseMonitor.onSelectionGesture = { [weak self] point, selectionCenter in
            self?.captureActionAnchor = (point, selectionCenter, Date())
            self?.engine.selectionGesture()
        }
        engine.onCapture = { [weak self] content, app, _ in
            self?.ingest(content: content, app: app)
        }
        hotkey.onHotkey = { [weak self] key in
            guard let self else { return }
            switch key {
            case .pasteLatest:
                guard let item = self.itemToPaste() else { return }
                self.pasteEngine.pasteIntoActiveApp(item.content)
            case .showHistory:
                HistoryPanelPresenter.shared.toggle()
            }
        }
        middleClickTap.onMiddleClick = { [weak self] _ in
            guard let self else { return false }
            guard self.middleClickPasteEnabled, self.axTrusted else {
                diagLog("middle-click ignored: enabled=\(self.middleClickPasteEnabled) axTrusted=\(self.axTrusted)")
                return false
            }
            guard self.shouldPasteAtCursor(input: "middle-click") else { return false }
            guard let item = self.itemToPaste() else {
                diagLog("middle-click ignored: nothing to paste (PastePolicy)")
                return false
            }
            // Paste into the current focus, same as ⌥V.
            self.pendingPasteFeedbackAnchor = NSEvent.mouseLocation
            self.pasteEngine.pasteIntoActiveApp(item.content)
            diagLog("middle-click pasted \(item.text.count) chars")
            return true
        }
        threeFingerClickTap.fingersTouching = { [weak self] in
            self?.trackpadTap.fingersTouching() ?? 0
        }
        threeFingerClickTap.onThreeFingerClick = { [weak self] in
            guard let self, self.threeFingerPasteMode == .click, self.axTrusted,
                  self.shouldPasteAtCursor(input: "three-finger click"),
                  let item = self.itemToPaste()
            else { return false }
            self.pendingPasteFeedbackAnchor = NSEvent.mouseLocation
            self.pasteEngine.pasteIntoActiveApp(item.content)
            return true
        }
        trackpadTap.onFirstTouchSessionStarted = { [weak self] in
            guard let self,
                  self.threeFingerPasteMode == .doubleTap,
                  self.axTrusted
            else {
                self?.threeFingerTapTarget = nil
                return
            }
            self.threeFingerTapTarget = self.axMonitor.focusedEditablePasteTarget()
        }
        trackpadTap.onTapSequenceInvalidated = { [weak self] in
            self?.threeFingerTapTarget = nil
        }
        trackpadTap.onThreeFingerDoubleTap = { [weak self] in
            guard let self else { return }
            defer { self.threeFingerTapTarget = nil }
            guard self.threeFingerPasteMode == .doubleTap,
                  self.axTrusted,
                  !self.trackpadTap.isSwipeSuppressed(),
                  let target = self.threeFingerTapTarget,
                  self.axMonitor.isStillFocusedEditable(target),
                  let item = self.itemToPaste()
            else {
                diagLog("three-finger double tap ignored: target or mode changed")
                return
            }
            self.pendingPasteFeedbackAnchor = NSEvent.mouseLocation
            self.pasteEngine.pasteIntoActiveApp(item.content)
        }
        if threeFingerPasteMode != .off {
            trackpadTap.start()
        }
        registerHotkeys()

        history.applyRetention(days: historyRetentionDays)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.history.applyRetention(days: self.historyRetentionDays)
            }
        }

        // First run from /Applications: start at login by default (the
        // system notifies the user; the toggle can turn it off). Dev builds
        // outside /Applications never self-register.
        let offeredKey = "didEnableLaunchAtLogin"
        if !UserDefaults.standard.bool(forKey: offeredKey),
           Bundle.main.bundlePath.hasPrefix("/Applications/") {
            UserDefaults.standard.set(true, forKey: offeredKey)
            launchAtLogin = true
        }

        // Every input feed can die silently across sleep/wake: CGEventTaps
        // stop delivering (their disabled-by-timeout callback never fires on
        // a dead tap), and the MultitouchSupport frame stream goes quiet
        // (observed 2026-07-17, and 2026-07-21 after a day-long lid close —
        // capture and click-paste both dead until relaunch). Recreate all of
        // them on every wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.restartInputMonitors() }
        }
        // Belt to the wake fix's suspenders: taps have also died with no
        // sleep involved (2026-07-17, trigger never confirmed). A dead tap
        // reports tapIsEnabled == false at least in the timeout-disable
        // mode, so a cheap poll catches part of what the wake hook misses.
        tapHealthTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                let model = AppModel.shared
                guard model.axTrusted,
                      model.middleClickTap.isDead || model.threeFingerClickTap.isDead
                else { return }
                diagLog("health check: dead event tap detected")
                model.restartInputMonitors()
            }
        }

        diagLog("start: AX trusted = \(axTrusted)")
        promptForAccessibilityIfNeeded()
        if axTrusted {
            axMonitor.start()
            mouseMonitor.start()
            middleClickTap.start()
            threeFingerClickTap.start()
        } else {
            pollForTrust()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Sparkle's own preference — it persists this itself.
    var autoUpdatesEnabled: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    func copyToClipboard(_ text: String) {
        pasteboard.writeString(text)
    }

    func copyToClipboard(_ content: RichText) {
        pasteboard.writeContent(content)
    }

    func copyToClipboard(_ item: SelectionItem) {
        copyToClipboard(item.content)
    }

    /// The entry the paste triggers use when the user picked one in the
    /// popover — Marker's own paste slot, nothing near the system clipboard.
    /// A new capture clears it: the fresh selection takes over again.
    @ObservationIgnored private var pickedPasteItemID: UUID?

    /// Popover row click / ↩: make this item what ⌥V and the click gestures
    /// paste. The toast is the feedback that the click did something.
    func pickForPaste(_ item: SelectionItem) {
        pickedPasteItemID = item.id
        ToastPresenter.shared.showReady(text: item.text, hotkeyLabel: pasteHotkey.label)
    }

    /// Panel row click / ↩. The panel is non-activating, so the frontmost
    /// app never lost focus: if an editable element still holds the caret,
    /// paste straight into it — the text appearing is its own feedback.
    /// No editable focus → arm the paste slot as before. Either way the
    /// item stays armed so the paste hotkey can repeat it.
    func pickFromPanel(_ item: SelectionItem) {
        let role = axTrusted ? axMonitor.focusedElementRole() : nil
        guard let role, MiddlePastePolicy.shouldPaste(role: role) else {
            markerLog.info("panel pick: no editable focus (\(role ?? "nil", privacy: .public)) — armed paste slot")
            pickForPaste(item)
            return
        }
        markerLog.info("panel pick: pasting into focused \(role, privacy: .public)")
        pickedPasteItemID = item.id
        pasteEngine.pasteIntoActiveApp(item.content)
    }

    /// Search query the popover should adopt (marker://search). Cleared by
    /// HistoryView once applied.
    var popoverSearchRequest: String?

    func handle(_ command: URLCommand) {
        switch command {
        case .show:
            HistoryPanelPresenter.shared.show()
        case .search(let query):
            popoverSearchRequest = query
            HistoryPanelPresenter.shared.show()
        case .copy(let position):
            history.refresh()
            let items = history.items
            guard items.count >= position else {
                markerLog.error("marker://copy: only \(items.count) entries, wanted \(position)")
                return
            }
            copyToClipboard(items[position - 1])
        case .add(let text):
            _ = history.push(
                RichText(plain: text),
                app: SourceApp(pid: 0, bundleID: "url.marker.add", name: "Automation", isSelf: false)
            )
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func ingest(content: RichText, app: SourceApp) {
        // The clipboard stays the user's: captures land in history only,
        // and reach the pasteboard solely through an explicit Copy action.
        if skipSecretsEnabled, SecretDetector.looksSecret(content.plain) {
            markerLog.info("skipped a selection that looks like a secret")
            return
        }

        let saved = history.push(content, app: app)
        let actionAnchor = takeCaptureActionAnchor()
        // Selecting something new supersedes a popover pick — the latest
        // selection is what the user means to paste now.
        pickedPasteItemID = nil
        if toastEnabled, let actionAnchor {
            SelectionActionPresenter.shared.show(
                at: actionAnchor.point,
                selectionCenter: actionAnchor.selectionCenter,
                savedToHistory: saved
            ) { [weak self] in
                self?.copyToClipboard(content)
            }
        }
        if !saved, toastEnabled {
            ToastPresenter.shared.show(
                text: content.plain,
                appName: app.name,
                bundleID: app.bundleID,
                warning: String(localized: "Couldn't save to history")
            )
        }
    }

    /// Captures normally settle within 0.15–0.9s. Anything older belongs to
    /// an abandoned gesture and must not make a later capture appear in the
    /// wrong place.
    private func takeCaptureActionAnchor() -> (point: NSPoint, selectionCenter: NSPoint?)? {
        guard let anchor = captureActionAnchor else { return nil }
        captureActionAnchor = nil
        guard Date().timeIntervalSince(anchor.date) < 2 else { return nil }
        return (anchor.point, anchor.selectionCenter)
    }

    /// What ⌥V and the click gestures should paste — usually the newest
    /// entry, but never a selection onto itself (PastePolicy). When the
    /// newest entry is skipped it was a select-to-replace target, not a
    /// wanted capture — the paste wipes it from the screen, so retract it
    /// from history too.
    private func itemToPaste() -> SelectionItem? {
        history.refresh() // marker-cli may have added entries behind our back
        let items = history.items
        // A popover pick wins outright — the user pointed at this exact
        // entry, so the never-paste-onto-itself policy doesn't apply.
        if let id = pickedPasteItemID {
            if let picked = items.first(where: { $0.id == id }) {
                return picked
            }
            pickedPasteItemID = nil // deleted since; fall back to the newest
        }
        let picked = PastePolicy.item(
            history: items,
            currentSelection: axMonitor.currentSelection()
        )
        if let picked, let first = items.first, picked.id != first.id {
            history.delete(first)
            markerLog.info("retracted select-to-replace capture from history")
        }
        return picked
    }

    /// Shared gate for the cursor-targeted paste triggers. Clicks pass
    /// through when the policy says no, so the cursor role decides first
    /// and the focused element is only a fallback.
    private func shouldPasteAtCursor(input: String) -> Bool {
        let cursorRole = axMonitor.roleAtMouseLocation()
        guard MiddlePastePolicy.shouldPaste(
            cursorRole: cursorRole,
            focusedRole: { self.axMonitor.focusedElementRole() }
        ) else {
            let focused = axMonitor.focusedElementRole() ?? "nil"
            diagLog("\(input) ignored: cursor=\(cursorRole ?? "nil") focused=\(focused)")
            return false
        }
        return true
    }

    /// Recreate the input monitors after a wake. Safe to run even if they
    /// are healthy — stop/recreate is cheap and loses no state.
    private func restartInputMonitors() {
        guard axTrusted else { return }
        diagLog("wake: restarting input monitors")
        mouseMonitor.stop()
        mouseMonitor.start()
        middleClickTap.restart()
        threeFingerClickTap.restart()
        if threeFingerPasteMode != .off {
            trackpadTap.restart()
        }
    }

    private func promptForAccessibilityIfNeeded() {
        guard !axTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func pollForTrust() {
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            Task { @MainActor in
                guard let self else { return }
                markerLog.info("AX trust granted, starting watcher")
                self.axTrusted = true
                self.axMonitor.start()
                self.mouseMonitor.start()
                self.middleClickTap.start()
                self.threeFingerClickTap.start()
            }
        }
    }
}
