import Foundation

/// Middle-click (and its trackpad equivalent) pastes only when the cursor
/// is over an editable text element; everywhere else the click passes
/// through untouched, so browser gestures (close tab, open link in tab)
/// keep working.
///
/// Apps with minimal AX trees (kitty, some terminals) hit-test as AXWindow
/// even over their text area, and browser pages hit-test their blank canvas
/// as AXWebArea — for those (or no element at all) the focused element's
/// role decides instead. Roles that carry their own middle-click semantics
/// (AXLink, AXButton, AXGroup content) never fall back — a focused text
/// field elsewhere on the page must not swallow a click on a link.
enum MiddlePastePolicy {
    static let textRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXSearchField", "AXComboBox",
    ]

    /// Roles with no click semantics of their own — the hit test hit an app
    /// that doesn't describe its content (AXWindow, nothing) or the blank
    /// canvas of a browser page (AXWebArea). Links, buttons and tabs
    /// hit-test as their own roles, so a fallback here never steals a click
    /// the app cared about; at worst it trades autoscroll on empty page
    /// space for a paste into the focused field.
    private static let bareRoles: Set<String?> = ["AXWindow", "AXWebArea", nil]

    static func shouldPaste(role: String?) -> Bool {
        guard let role else { return false }
        return textRoles.contains(role)
    }

    /// Full decision for click triggers: cursor role first, focused element
    /// as fallback only when the cursor hit nothing meaningful. Taps don't
    /// consume a click and skip the cursor entirely — they gate on the
    /// focused role alone via `shouldPaste(role:)`.
    static func shouldPaste(
        cursorRole: String?,
        focusedRole: () -> String?
    ) -> Bool {
        if shouldPaste(role: cursorRole) { return true }
        guard bareRoles.contains(cursorRole) else { return false }
        return shouldPaste(role: focusedRole())
    }
}
