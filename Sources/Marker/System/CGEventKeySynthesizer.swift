import AppKit

final class CGEventKeySynthesizer: KeyEventSynthesizing {
    /// "MARKER" as an event-source tag. Global monitors see our synthesized
    /// ⌘C/⌘V too; tagging lets UI dismissals ignore them while still
    /// reacting to the user's real keyboard.
    static let syntheticEventTag: Int64 = 0x4D41524B4552

    static func isMarkerSynthetic(_ event: CGEvent?) -> Bool {
        event?.getIntegerValueField(.eventSourceUserData) == syntheticEventTag
    }

    func postCopy() {
        postCommandKey(CGKeyCode(8)) // kVK_ANSI_C
    }

    func postPaste() {
        postCommandKey(CGKeyCode(9)) // kVK_ANSI_V
    }

    func modifiersReleased() -> Bool {
        CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand])
            .isEmpty
    }

    private func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
