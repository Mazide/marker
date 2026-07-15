import AppKit

/// Offers to move the app into /Applications when launched from a DMG,
/// Downloads, or a translocated path (the LetsMove pattern, minimal).
@MainActor
enum SelfInstaller {
    static func offerMoveToApplicationsIfNeeded() {
        let fm = FileManager.default
        let sourceURL = Bundle.main.bundleURL
        let path = sourceURL.path

        guard !path.hasPrefix("/Applications/") else { return }
        let translocated = path.contains("/AppTranslocation/")
        let readOnlyVolume = !fm.isWritableFile(atPath: path)
        let casualLocation = path.contains("/Downloads/") || path.contains("/Desktop/")
        // Dev builds and other deliberate locations: don't nag.
        guard translocated || readOnlyVolume || casualLocation else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "Move Marker to the Applications folder?", comment: "self-install alert title")
        alert.informativeText = NSLocalizedString(
            "Marker will move itself to Applications and relaunch from there.",
            comment: "self-install alert body")
        alert.addButton(withTitle: NSLocalizedString(
            "Move to Applications", comment: "self-install confirm button"))
        alert.addButton(withTitle: NSLocalizedString(
            "Not Now", comment: "self-install cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let destURL = URL(fileURLWithPath: "/Applications/Marker.app")
        do {
            // A copy already running from /Applications would fight this one.
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
            ) where app != NSRunningApplication.current {
                app.terminate()
            }
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: sourceURL, to: destURL)
            if !translocated, !readOnlyVolume {
                try? fm.trashItem(at: sourceURL, resultingItemURL: nil)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destURL, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            markerLog.error("self-install failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}