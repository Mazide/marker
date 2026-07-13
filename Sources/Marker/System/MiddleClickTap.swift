import AppKit
import CoreGraphics

/// CGEventTap for the middle mouse button. Unlike NSEvent global monitors
/// a tap can swallow the event, so a middle-click that pastes does not
/// also close a browser tab. The handler decides per-click.
final class MiddleClickTap {
    /// Return true to swallow the click (paste will happen), false to let
    /// the app receive it untouched.
    var onMiddleClick: ((CGPoint) -> Bool)?

    private var tap: CFMachPort?
    private var swallowNextUp = false

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MiddleClickTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        )
        guard let tap else {
            markerLog.error("middle-click tap creation failed")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .otherMouseDown:
            swallowNextUp = onMiddleClick?(event.location) ?? false
            return swallowNextUp ? nil : Unmanaged.passUnretained(event)
        case .otherMouseUp where swallowNextUp:
            swallowNextUp = false
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}