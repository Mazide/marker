import AppKit
import ApplicationServices
import Observation
import ServiceManagement
import Sparkle

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let history = HistoryStore(db: SQLiteHistoryDatabase())
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

    /// Classic auto-copy: captured selections also land on the system
    /// clipboard. Off = strict X11-primary mode (history only).
    var copyToClipboardEnabled: Bool = UserDefaults.standard.object(forKey: "copyToClipboardEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(copyToClipboardEnabled, forKey: "copyToClipboardEnabled") }
    }

    var toastEnabled: Bool = UserDefaults.standard.object(forKey: "toastEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(toastEnabled, forKey: "toastEnabled") }
    }

    /// X11-style middle-click paste at the click point. Off by default;
    /// only swallows clicks over editable text (MiddlePastePolicy).
    var middleClickPasteEnabled: Bool = UserDefaults.standard.object(forKey: "middleClickPasteEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(middleClickPasteEnabled, forKey: "middleClickPasteEnabled") }
    }

    /// Trackpad three-finger tap as a middle-click substitute (private
    /// MultitouchSupport API — experimental, off by default).
    var threeFingerTapEnabled: Bool = UserDefaults.standard.object(forKey: "threeFingerTapEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(threeFingerTapEnabled, forKey: "threeFingerTapEnabled")
            if threeFingerTapEnabled { trackpadTap.start() }
        }
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
    @ObservationIgnored private let hotkey = HotkeyManager()
    @ObservationIgnored private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @ObservationIgnored private var trustPollTimer: Timer?
    @ObservationIgnored private var retentionTimer: Timer?

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
        axMonitor.onKeyDown = { [weak self] isIntent, isTyping in
            self?.engine.keyDown(isSelectionIntent: isIntent, isPlainTyping: isTyping)
        }
        engine.retractionEnabled = retractEditedEnabled
        mouseMonitor.onMouseDown = { [weak self] in
            self?.engine.mouseDown()
        }
        mouseMonitor.onSelectionGesture = { [weak self] in
            self?.engine.selectionGesture()
        }
        engine.onCapture = { [weak self] text, app, _ in
            self?.ingest(text: text, app: app)
        }
        hotkey.onHotkey = { [weak self] in
            guard let self, let item = self.history.items.first else { return }
            self.pasteEngine.pasteIntoActiveApp(item.text)
        }
        middleClickTap.onMiddleClick = { [weak self] point in
            guard let self, self.middleClickPasteEnabled, self.axTrusted,
                  self.shouldPasteAtCursor(input: "middle-click"),
                  let text = self.history.items.first?.text
            else { return false }
            _ = point
            // Paste into the current focus, same as ⌥V.
            self.pasteEngine.pasteIntoActiveApp(text)
            return true
        }
        trackpadTap.onThreeFingerTap = { [weak self] in
            guard let self, self.threeFingerTapEnabled, self.axTrusted,
                  self.shouldPasteAtCursor(input: "tap"),
                  let text = self.history.items.first?.text
            else { return }
            self.pasteEngine.pasteIntoActiveApp(text)
        }
        if threeFingerTapEnabled {
            trackpadTap.start()
        }
        hotkey.register()

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

        markerLog.info("start: AX trusted = \(self.axTrusted)")
        promptForAccessibilityIfNeeded()
        if axTrusted {
            axMonitor.start()
            mouseMonitor.start()
            middleClickTap.start()
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

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func ingest(text: String, app: SourceApp) {
        // Secrets pass through to the clipboard (the user selected them on
        // purpose) but are never persisted to history.
        if skipSecretsEnabled, SecretDetector.looksSecret(text) {
            markerLog.info("skipped a selection that looks like a secret")
            if copyToClipboardEnabled {
                pasteboard.writeString(text)
            }
            return
        }

        let isNew = history.items.first?.text != text
        history.push(text: text, app: app)
        if copyToClipboardEnabled {
            pasteboard.writeString(text)
        }
        if isNew, toastEnabled {
            ToastPresenter.shared.show(text: text, appName: app.name, bundleID: app.bundleID)
        }
    }

    /// Shared gate for middle-click and three-finger tap; both paste into
    /// the focused element, so both use the same cursor/focus policy.
    private func shouldPasteAtCursor(input: String) -> Bool {
        let cursorRole = axMonitor.roleAtMouseLocation()
        guard MiddlePastePolicy.shouldPaste(
            cursorRole: cursorRole,
            focusedRole: { self.axMonitor.focusedElementRole() }
        ) else {
            markerLog.info("\(input, privacy: .public) ignored: cursor=\(cursorRole ?? "nil", privacy: .public)")
            return false
        }
        return true
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
            }
        }
    }
}