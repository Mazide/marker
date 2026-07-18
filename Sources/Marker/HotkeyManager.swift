import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys via the Carbon hotkey API. Unlike NSEvent
/// global monitors, RegisterEventHotKey consumes the keystroke, so "√"
/// is not typed into the focused app.
final class HotkeyManager {
    /// Marker's global hotkeys. Raw value doubles as the Carbon hotkey ID.
    enum Hotkey: UInt32 {
        /// ⌥V — paste the latest selection into the active app.
        case pasteLatest = 1
        /// ⇧⌥V — open the history popover.
        case showHistory = 2
    }

    var onHotkey: ((Hotkey) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    func register() {
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

        let signature = OSType(0x4D52_4B52) // 'MRKR'
        var errs: [OSStatus] = []
        for (key, modifiers) in [
            (Hotkey.pasteLatest, UInt32(optionKey)),
            (Hotkey.showHistory, UInt32(optionKey | shiftKey)),
        ] {
            var ref: EventHotKeyRef?
            errs.append(RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                modifiers,
                EventHotKeyID(signature: signature, id: key.rawValue),
                GetApplicationEventTarget(),
                0,
                &ref
            ))
            hotKeyRefs.append(ref)
        }
        markerLog.info("hotkey register: handler=\(installErr) hotkeys=\(errs)")
    }
}
