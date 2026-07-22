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
    private var runLoopSource: CFRunLoopSource?
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
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// The tap exists but the system has switched it off — the silent
    /// death mode. A tap that was never created doesn't count as dead.
    var isDead: Bool {
        guard let tap else { return false }
        return !CGEvent.tapIsEnabled(tap: tap)
    }

    /// Tear down and recreate the tap. Taps die silently across sleep/wake —
    /// the disabled-by-timeout callback only arrives while the tap still
    /// delivers events, so recreation is the only reliable revival.
    func restart() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        start()
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
