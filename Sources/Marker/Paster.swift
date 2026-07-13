import AppKit

enum Paster {
    /// Pastes `text` into the active app without permanently clobbering the
    /// system clipboard: saves the current string contents, writes `text`,
    /// synthesizes Cmd+V, then restores the original contents shortly after.
    static func pasteIntoActiveApp(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let saved else { return }
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(9) // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
