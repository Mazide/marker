import AppKit

/// The menu bar icon. Not a MenuBarExtra: both entry points — the icon and
/// the hotkey — summon the same centered history panel, so the icon is a
/// plain status item whose click toggles the panel.
@MainActor
final class StatusItemController {
    static let shared = StatusItemController()

    private var item: NSStatusItem?

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon
        item.button?.target = self
        item.button?.action = #selector(clicked)
        self.item = item
    }

    @objc private func clicked() {
        HistoryPanelPresenter.shared.toggle()
    }

    /// Mono glyph of the app icon (highlight stripe + I-beam), drawn in
    /// code for a clean alpha channel. Template image so the menu bar
    /// tints it for light/dark and inactive states.
    private static let icon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            // Highlight stripe with a gap cut around the caret.
            let stripe = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 6.25, width: 13, height: 5.5),
                xRadius: 2, yRadius: 2
            )
            stripe.fill()
            cg.setBlendMode(.clear)
            NSBezierPath(
                roundedRect: NSRect(x: 11.25, y: 1.5, width: 4.5, height: 15),
                xRadius: 2.25, yRadius: 2.25
            ).fill()
            cg.setBlendMode(.normal)
            // I-beam caret: bar + serifs.
            NSBezierPath(
                roundedRect: NSRect(x: 12.75, y: 2.5, width: 1.5, height: 13),
                xRadius: 0.75, yRadius: 0.75
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 10.75, y: 2, width: 5.5, height: 1.3),
                xRadius: 0.65, yRadius: 0.65
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 10.75, y: 14.7, width: 5.5, height: 1.3),
                xRadius: 0.65, yRadius: 0.65
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
