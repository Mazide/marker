import SwiftUI

/*
Marker
Select text. It's already saved.
*/
@main
struct MarkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No MenuBarExtra: the status item (StatusItemController) and the
        // hotkey both open the same centered history panel.
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two instances (login item racing a Sparkle relaunch, or a dev build
        // next to the installed copy) mean two event taps and two writers on
        // one history.sqlite — the newcomer defers to the running instance.
        if let other = Self.otherRunningInstance() {
            markerLog.error("another Marker is running (pid \(other.processIdentifier)) — deferring startup")
            // Grace period: an outgoing instance (quit, update) may still be
            // shutting down; only yield to it if it is alive in 2s.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let survivor = Self.otherRunningInstance() {
                    markerLog.error("pid \(survivor.processIdentifier) is still running — quitting this instance")
                    NSApp.terminate(nil)
                } else {
                    self?.startUp()
                }
            }
            return
        }
        startUp()
    }

    @MainActor
    private func startUp() {
        SelfInstaller.offerMoveToApplicationsIfNeeded()
        StatusItemController.shared.install()
        AppModel.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommand.parse(url) else {
                markerLog.error("unrecognized URL: \(url.absoluteString, privacy: .public)")
                continue
            }
            AppModel.shared.handle(command)
        }
    }

    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
    }
}
