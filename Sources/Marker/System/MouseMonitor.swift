import AppKit

/// Watches global mouse events and reports raw gestures; the engine
/// decides what they mean.
final class MouseMonitor {
    /// Bool: shift was held (shift+click extends a selection); point: click
    /// location, used as the action anchor if the gesture captures text.
    var onMouseDown: ((_ shiftClick: Bool, _ point: NSPoint) -> Void)?
    /// A drag beyond a small threshold, or a double/triple click, together
    /// with the mouse-up anchor and approximate selection center. The latter
    /// gives the action pill a truthful directional-settle vector.
    var onSelectionGesture: ((_ point: NSPoint, _ selectionCenter: NSPoint) -> Void)?

    private var monitors: [Any] = []
    private var downLocation: NSPoint = .zero

    func start() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.downLocation = NSEvent.mouseLocation
            self?.onMouseDown?(event.modifierFlags.contains(.shift), NSEvent.mouseLocation)
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            let dx = location.x - self.downLocation.x
            let dy = location.y - self.downLocation.y
            let dragged = (dx * dx + dy * dy).squareRoot() > 5
            if dragged || event.clickCount >= 2 {
                let center = NSPoint(
                    x: (self.downLocation.x + location.x) / 2,
                    y: (self.downLocation.y + location.y) / 2
                )
                self.onSelectionGesture?(location, center)
            }
        }
        monitors = [down, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}
