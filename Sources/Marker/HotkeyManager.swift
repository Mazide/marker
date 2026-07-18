import AppKit
import Carbon.HIToolbox
import Foundation

/// A user-assignable global shortcut: Carbon key code + Carbon modifier
/// mask, plus the display label rendered at record time (key codes are
/// layout-independent, labels are not).
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

/// Registers global hotkeys via the Carbon hotkey API. Unlike NSEvent
/// global monitors, RegisterEventHotKey consumes the keystroke, so "√"
/// is not typed into the focused app. Re-registrable: assigning a new
/// combo in Settings unregisters the old ones and applies the new set.
final class HotkeyManager {
    /// Marker's global hotkeys. Raw value doubles as the Carbon hotkey ID.
    enum Hotkey: UInt32 {
        /// Paste the latest selection into the active app (default ⌥V).
        case pasteLatest = 1
        /// Open the history popover (default ⇧⌥V).
        case showHistory = 2
    }

    var onHotkey: ((Hotkey) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    func register(_ combos: [Hotkey: KeyCombo]) {
        installHandlerIfNeeded()
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()

        let signature = OSType(0x4D52_4B52) // 'MRKR'
        var errs: [OSStatus] = []
        for (key, combo) in combos.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            var ref: EventHotKeyRef?
            errs.append(RegisterEventHotKey(
                combo.keyCode,
                combo.modifiers,
                EventHotKeyID(signature: signature, id: key.rawValue),
                GetApplicationEventTarget(),
                0,
                &ref
            ))
            if let ref { hotKeyRefs.append(ref) }
        }
        markerLog.info("hotkey register: \(errs)")
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installErr = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard let hotkey = Hotkey(rawValue: hotKeyID.id) else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotkey?(hotkey) }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        if installErr != noErr {
            markerLog.error("hotkey handler install failed: \(installErr)")
        }
    }
}
