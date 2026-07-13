import AppKit

final class WorkspaceFrontmost: FrontmostAppProviding {
    func frontmostApp() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return SourceApp(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? "Unknown",
            isSelf: app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        )
    }
}