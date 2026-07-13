import Foundation

/// Middle-click pastes only when the cursor is over an editable text
/// element; everywhere else the click passes through untouched, so
/// browser gestures (close tab, open link in tab) keep working.
enum MiddlePastePolicy {
    static let textRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXSearchField", "AXComboBox",
    ]

    static func shouldPaste(role: String?) -> Bool {
        guard let role else { return false }
        return textRoles.contains(role)
    }
}