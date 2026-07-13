import AppKit

final class CGEventKeySynthesizer: KeyEventSynthesizing {
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
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}