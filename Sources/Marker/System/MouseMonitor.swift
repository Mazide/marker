import AppKit

/// Watches global mouse events and reports raw gestures; the engine
/// decides what they mean.
final class MouseMonitor {
    /// Bool: shift was held (shift+click extends a selection).
    var onMouseDown: ((_ shiftClick: Bool) -> Void)?
    /// A drag beyond a small threshold, or a double/triple click.
    var onSelectionGesture: (() -> Void)?

    private var monitors: [Any] = []
    private var downLocation: NSPoint = .zero

    func start() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.downLocation = NSEvent.mouseLocation
            self?.onMouseDown?(event.modifierFlags.contains(.shift))
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            let dx = location.x - self.downLocation.x
            let dy = location.y - self.downLocation.y
            let dragged = (dx * dx + dy * dy).squareRoot() > 5
            if dragged || event.clickCount >= 2 {
                self.onSelectionGesture?()
            }
        }
        monitors = [down, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}