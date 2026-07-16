import SwiftUI

@main
struct MarkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            HistoryView()
        } label: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "highlighter")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    /// Mono glyph of the app icon (highlight stripe + I-beam), drawn in
    /// code for a clean alpha channel. Template image so the menu bar
    /// tints it for light/dark and inactive states.
    private static let menuBarIcon: NSImage? = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            // Highlight stripe with a gap cut around the caret.
            let stripe = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 6.25, width: 13, height: 5.5),
                xRadius: 2, yRadius: 2
            )
            stripe.fill()
            cg.setBlendMode(.clear)
            NSBezierPath(
                roundedRect: NSRect(x: 11.25, y: 1.5, width: 4.5, height: 15),
                xRadius: 2.25, yRadius: 2.25
            ).fill()
            cg.setBlendMode(.normal)
            // I-beam caret: bar + serifs.
            NSBezierPath(
                roundedRect: NSRect(x: 12.75, y: 2.5, width: 1.5, height: 13),
                xRadius: 0.75, yRadius: 0.75
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 10.75, y: 2, width: 5.5, height: 1.3),
                xRadius: 0.65, yRadius: 0.65
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 10.75, y: 14.7, width: 5.5, height: 1.3),
                xRadius: 0.65, yRadius: 0.65
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
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
        AppModel.shared.start()
    }

    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
    }
}
