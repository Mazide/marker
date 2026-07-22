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

    /// Content roles: rich-text editors (contenteditable in Chrome, Slack,
    /// Notion) hit-test as AXGroup or AXStaticText while focusing a real
    /// editable element. Falling back here is only safe for triggers that
    /// consume nothing — over a browser page a click still belongs to the
    /// app, so middle-click and three-finger click must keep passing through.
    private static let contentRoles: Set<String?> = ["AXGroup", "AXStaticText"]

    static func shouldPaste(role: String?) -> Bool {
        guard let role else { return false }
        return textRoles.contains(role)
    }

    /// Full decision for every input path: cursor role first, focused
    /// element as fallback only when the cursor hit nothing meaningful.
    /// `allowContentRoleFallback` widens that fallback to rich-text editor
    /// content; pass it only for triggers that don't swallow a click.
    static func shouldPaste(
        cursorRole: String?,
        focusedRole: () -> String?,
        allowContentRoleFallback: Bool = false
    ) -> Bool {
        if shouldPaste(role: cursorRole) { return true }
        let canFallBack = bareRoles.contains(cursorRole)
            || (allowContentRoleFallback && contentRoles.contains(cursorRole))
        guard canFallBack else { return false }
        return shouldPaste(role: focusedRole())
    }
}
