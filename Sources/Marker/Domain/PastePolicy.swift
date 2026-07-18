import Foundation

/// Which history entry ⌥V / middle-click should paste.
///
/// Selecting text in order to replace it makes that text the newest
/// history entry — pasting it back onto itself would be a no-op (the X11
/// select-to-replace trap: select the address bar, middle-click, get the
/// same URL back). So when the target's current selection IS the newest
/// entry, paste the one before it instead.
enum PastePolicy {
    static func item(history: [SelectionItem], currentSelection: String?) -> SelectionItem? {
        guard let first = history.first else { return nil }
        guard let selected = currentSelection?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !selected.isEmpty, selected == first.text
        else { return first }
        return history.dropFirst().first
    }
}
