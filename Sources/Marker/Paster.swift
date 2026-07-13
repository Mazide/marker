import AppKit

enum Paster {
    /// Pastes `text` into the active app without permanently clobbering the
    /// system clipboard: saves the current string contents, writes `text`,
    /// synthesizes Cmd+V, then restores the original contents shortly after.
    static func pasteIntoActiveApp(_ text: String) {
        // The hotkey is ⌥V: if Cmd+V is synthesized while the user still
        // physically holds Option, the app receives ⌥⌘V (a different
        // command in many apps). Wait for modifiers to clear first.
        waitForModifierRelease(deadline: Date().addingTimeInterval(1.0)) {
            performPaste(text)
        }
    }

    private static func waitForModifierRelease(deadline: Date, then action: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand])
        if held.isEmpty || Date() > deadline {
            action()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                waitForModifierRelease(deadline: deadline, then: action)
            }
        }
    }

    private static func performPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = FallbackCopier.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markerLog.info("paste: \(text.count) chars via Cmd+V")
        postCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            FallbackCopier.restore(pasteboard, from: saved)
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
