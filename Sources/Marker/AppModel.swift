import AppKit
import ApplicationServices
import Observation

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let history = HistoryStore()
    var axTrusted = AXIsProcessTrusted()

    @ObservationIgnored private let watcher = SelectionWatcher()
    @ObservationIgnored private let hotkey = HotkeyManager()
    @ObservationIgnored private var trustPollTimer: Timer?

    func start() {
        watcher.onSelection = { [weak self] text, app in
            self?.history.push(text: text, app: app)
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
        } else {
            pollForTrust()
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
            }
        }
    }
}
