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

    // System layer
    @ObservationIgnored private let pasteboard = SystemPasteboard()
    @ObservationIgnored private let keys = CGEventKeySynthesizer()
    @ObservationIgnored private let scheduler = TimerScheduler()
    @ObservationIgnored private let frontmost = WorkspaceFrontmost()
    @ObservationIgnored private let axMonitor = AXSelectionMonitor()
    @ObservationIgnored private let mouseMonitor = MouseMonitor()
    @ObservationIgnored private let hotkey = HotkeyManager()
    @ObservationIgnored private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @ObservationIgnored private var trustPollTimer: Timer?

    // Domain layer
    @ObservationIgnored private var engine: CaptureEngine!
    @ObservationIgnored private var pasteEngine: PasteEngine!
    @ObservationIgnored private var pasteQueue = PasteQueue()

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
        axMonitor.onKeyDown = { [weak self] isIntent in
            self?.engine.keyDown(isSelectionIntent: isIntent)
        }
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
            guard let self else { return }
            // A recent burst of selections pastes in order (⌥V ⌥V ⌥V fills
            // three form fields); otherwise ⌥V pastes the latest.
            if let next = self.pasteQueue.nextForPaste(at: Date()) {
                self.pasteEngine.pasteIntoActiveApp(next.text)
                if next.total > 1, self.toastEnabled {
                    ToastPresenter.shared.show(
                        text: next.text,
                        caption: .pasted(index: next.index, total: next.total)
                    )
                }
            } else if let item = self.history.items.first {
                self.pasteEngine.pasteIntoActiveApp(item.text)
            }
        }
        hotkey.register()

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
        } else {
            pollForTrust()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func copyToClipboard(_ text: String) {
        pasteboard.writeString(text)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func ingest(text: String, app: SourceApp) {
        let isNew = history.items.first?.text != text
        history.push(text: text, app: app)
        pasteQueue.captured(text, at: Date())
        if copyToClipboardEnabled {
            pasteboard.writeString(text)
        }
        if isNew, toastEnabled {
            ToastPresenter.shared.show(text: text, appName: app.name, bundleID: app.bundleID)
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
            }
        }
    }
}