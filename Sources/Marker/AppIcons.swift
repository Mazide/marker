import AppKit
import UniformTypeIdentifiers

/// Cached 16pt app icons for history rows and the app filter.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .application)
        }
        icon.size = NSSize(width: 16, height: 16)
        cache[bundleID] = icon
        return icon
    }
}