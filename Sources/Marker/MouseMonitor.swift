import AppKit

/// Watches global mouse events and reports gestures that look like a text
/// selection: a drag beyond a small threshold, or a double/triple click.
final class MouseMonitor {
    /// Called with the pasteboard changeCount recorded at mouse-down, so the
    /// handler can tell whether the app copy-on-selected by itself.
    var onSelectionGesture: ((Int) -> Void)?

    private var monitors: [Any] = []
    private var downLocation: NSPoint = .zero
    private var downChangeCount = 0

    func start() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.downLocation = NSEvent.mouseLocation
            self?.downChangeCount = NSPasteboard.general.changeCount
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            let dx = location.x - self.downLocation.x
            let dy = location.y - self.downLocation.y
            let dragged = (dx * dx + dy * dy).squareRoot() > 5
            if dragged || event.clickCount >= 2 {
                self.onSelectionGesture?(self.downChangeCount)
            }
        }
        monitors = [down, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}
