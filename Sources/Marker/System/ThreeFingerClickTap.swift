import AppKit
import CoreGraphics

/// CGEventTap for the left mouse button that turns a physical click made
/// with three fingers resting on the trackpad into a paste gesture. A
/// physical press is deliberate in a way a light tap is not, so this has
/// none of the tap's false positives (stray finger grazing the pad during
/// a two-finger scroll). Unlike NSEvent global monitors a tap can swallow
/// the event, so the click that pastes never reaches the app under the
/// cursor. The handler decides per-click.
final class ThreeFingerClickTap {
    /// Current number of fingers on the trackpad; queried on every left
    /// mouse down. Returns 0 when unknown.
    var fingersTouching: (() -> Int)?
    /// Return true to swallow the click (paste will happen), false to let
    /// the app receive it untouched.
    var onThreeFingerClick: (() -> Bool)?

    private var tap: CFMachPort?
    private var swallowNextUp = false

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<ThreeFingerClickTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        )
        guard let tap else {
            markerLog.error("three-finger click tap creation failed")
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
        switch type {
        case .leftMouseDown:
            guard fingersTouching?() == 3 else {
                return Unmanaged.passUnretained(event)
            }
            markerLog.debug("left click with three fingers touching")
            swallowNextUp = onThreeFingerClick?() ?? false
            return swallowNextUp ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp where swallowNextUp:
            swallowNextUp = false
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
