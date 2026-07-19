import Foundation

/// The marker:// URL scheme — the automation door for tools that speak
/// URLs but not Shortcuts or shells (Keyboard Maestro, BetterTouchTool,
/// browser bookmarks, `open` in any script).
///
///   marker://show                   open the history popover
///   marker://search?q=invoice       open the popover with a query typed
///   marker://copy                   copy the newest entry to the clipboard
///   marker://copy?position=3        …or the Nth newest (1-based)
///   marker://add?text=hello         add text to history
enum URLCommand: Equatable {
    case show
    case search(query: String)
    case copy(position: Int)
    case add(text: String)

    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme == "marker" else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }
        switch url.host {
        case "show":
            return .show
        case "search":
            return .search(query: value("q") ?? "")
        case "copy":
            guard let position = value("position").map(Int.init) ?? 1 else { return nil }
            guard position >= 1 else { return nil }
            return .copy(position: position)
        case "add":
            guard let text = value("text")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return nil }
            return .add(text: text)
        default:
            return nil
        }
    }
}
