import AppKit
import ApplicationServices
import Observation

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let history = HistoryStore()
    var axTrusted = AXIsProcessTrusted()

    var fallbackCopyEnabled: Bool = UserDefaults.standard.object(forKey: "fallbackCopyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fallbackCopyEnabled, forKey: "fallbackCopyEnabled") }
    }

    var toastEnabled: Bool = UserDefaults.standard.object(forKey: "toastEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(toastEnabled, forKey: "toastEnabled") }
    }

    @ObservationIgnored private let watcher = SelectionWatcher()
    @ObservationIgnored private let hotkey = HotkeyManager()
    @ObservationIgnored private let mouseMonitor = MouseMonitor()
    @ObservationIgnored private var trustPollTimer: Timer?
    /// Apps that have proven they report selections via AX; for these an
    /// empty AX read means "nothing selected", so never fall back to Cmd+C
    /// (which could copy a whole line in editors like VS Code).
    @ObservationIgnored private var axProvenApps: Set<String> = []
    /// Clipboard contents at mouse-down in a fallback-eligible app, so a
    /// self-copy-on-select (kitty, TUIs) can be undone after ingesting.
    @ObservationIgnored private var downSnapshot: PasteboardSnapshot?
    /// Element roles where a drag is not a text selection.
    private static let nonTextRoles: Set<String> = [
        "AXScrollBar", "AXSlider", "AXButton", "AXMenuItem", "AXMenu",
        "AXMenuBar", "AXMenuBarItem", "AXPopUpButton", "AXCheckBox",
        "AXRadioButton", "AXToolbar", "AXTabGroup", "AXDisclosureTriangle",
    ]

    func start() {
        watcher.onSelection = { [weak self] text, app in
            self?.ingest(text: text, app: app, viaAX: true)
        }
        mouseMonitor.onSelectionGesture = { [weak self] downChangeCount in
            self?.handleSelectionGesture(downChangeCount: downChangeCount)
        }
        mouseMonitor.onMouseDown = { [weak self] in
            guard let self else { return }
            // Snapshot only in fallback-eligible apps to avoid copying
            // pasteboard data on every click system-wide.
            guard self.axTrusted, self.fallbackCopyEnabled,
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !self.axProvenApps.contains(app.bundleIdentifier ?? "")
            else {
                self.downSnapshot = nil
                return
            }
            self.downSnapshot = FallbackCopier.snapshot(NSPasteboard.general)
        }
        hotkey.onHotkey = { [weak self] in
            guard let item = self?.history.items.first else { return }
            Paster.pasteIntoActiveApp(item.text)
        }
        hotkey.register()

        markerLog.info("start: AX trusted = \(self.axTrusted)")
        promptForAccessibilityIfNeeded()
        if axTrusted {
            watcher.start()
            mouseMonitor.start()
        } else {
            pollForTrust()
        }
    }

    private func ingest(text: String, app: NSRunningApplication, viaAX: Bool) {
        if viaAX, let bundleID = app.bundleIdentifier {
            axProvenApps.insert(bundleID)
        }
        let isNew = history.items.first?.text != text
        history.push(text: text, app: app)
        if isNew, toastEnabled {
            ToastPresenter.shared.show(text: text)
        }
    }

    private func handleSelectionGesture(downChangeCount: Int) {
        guard axTrusted else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }

        // Give the app a beat to finalize the selection after mouse-up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if let text = self.watcher.currentAXSelection(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.ingest(text: text, app: app, viaAX: true)
                return
            }
            guard self.fallbackCopyEnabled,
                  self.axProvenApps.contains(app.bundleIdentifier ?? "") == false
            else { return }
            // The app copy-on-selected by itself (terminals, TUIs): the
            // selection is already on the clipboard — take it, then put the
            // user's previous clipboard back.
            if NSPasteboard.general.changeCount != downChangeCount {
                if let text = NSPasteboard.general.string(forType: .string),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    markerLog.info("app self-copied \(text.count) chars")
                    self.ingest(text: text, app: app, viaAX: false)
                }
                if let snapshot = self.downSnapshot {
                    FallbackCopier.restore(NSPasteboard.general, from: snapshot)
                    self.downSnapshot = nil
                }
                return
            }
            if let role = self.watcher.roleAtMouseLocation(),
               Self.nonTextRoles.contains(role) {
                return
            }
            markerLog.debug("fallback Cmd+C for \(app.localizedName ?? "?", privacy: .public)")
            FallbackCopier.capture { text in
                guard let text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                markerLog.info("fallback captured \(text.count) chars")
                self.ingest(text: text, app: app, viaAX: false)
            }
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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
                self.watcher.start()
                self.mouseMonitor.start()
            }
        }
    }
}
