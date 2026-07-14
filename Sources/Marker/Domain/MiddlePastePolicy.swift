import Foundation

/// Middle-click (and its trackpad equivalent) pastes only when the cursor
/// is over an editable text element; everywhere else the click passes
/// through untouched, so browser gestures (close tab, open link in tab)
/// keep working.
///
/// Apps with minimal AX trees (kitty, some terminals) hit-test as AXWindow
/// even over their text area, so for AXWindow (or no element at all) the
/// focused element's role decides instead. Roles that carry their own
/// middle-click semantics (AXGroup/AXLink/AXWebArea inside browsers) never
/// fall back — a focused text field elsewhere on the page must not swallow
/// a click on a link.
enum MiddlePastePolicy {
    static let textRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXSearchField", "AXComboBox",
    ]

    /// Roles with no semantics of their own — the hit test hit an app
    /// that doesn't describe its content, not a real UI element.
    private static let bareRoles: Set<String?> = ["AXWindow", nil]

    static func shouldPaste(role: String?) -> Bool {
        guard let role else { return false }
        return textRoles.contains(role)
    }

    /// Full decision for both input paths: cursor role first, focused
    /// element as fallback only when the cursor hit nothing meaningful.
    static func shouldPaste(cursorRole: String?, focusedRole: () -> String?) -> Bool {
        if shouldPaste(role: cursorRole) { return true }
        guard bareRoles.contains(cursorRole) else { return false }
        return shouldPaste(role: focusedRole())
    }
}
