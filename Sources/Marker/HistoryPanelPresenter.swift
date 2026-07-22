import AppKit
import SwiftUI

/// Spotlight-style floating panel for the history hotkey. The menu bar icon
/// keeps the compact MenuBarExtra popover; the hotkey summons this centered
/// panel instead — a keyboard-first invocation puts the UI at eye line, not
/// in the screen corner.
@MainActor
final class HistoryPanelPresenter: NSObject, NSWindowDelegate {
    static let shared = HistoryPanelPresenter()

    private var panel: KeyablePanel?
    /// Screen Y of the panel's top edge. Content-driven resizes (search
    /// narrowing the list) keep the top pinned and grow downward.
    private var desiredTop: CGFloat = 0
    /// When the status item is clicked while the panel is open, the click
    /// first lands as resign-key (which closes the panel) and only then as
    /// the button action — so toggle() would instantly reopen it. A close
    /// this recent means the click was meant to close.
    private var lastCloseAt: TimeInterval = 0

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else if CACurrentMediaTime() - lastCloseAt > 0.3 {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        // Fresh root view per show: search text, filter and selection reset,
        // and onAppear refreshes history and grabs keyboard focus.
        let hosting = NSHostingController(
            rootView: HistoryView(onDismiss: { [weak self] in self?.close() })
        )
        panel.contentViewController = hosting

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = hosting.view.fittingSize
        desiredTop = visible.maxY - visible.height * 0.12
        panel.setFrame(
            NSRect(
                x: (visible.midX - size.width / 2).rounded(),
                y: desiredTop - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        // Non-activating: the target app keeps focus, so a pick can be
        // followed by the paste hotkey without clicking back — but the
        // panel is key, so typing lands in its search field.
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        lastCloseAt = CACurrentMediaTime()
        panel.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    /// Clicking anywhere else dismisses the panel, Spotlight-style.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// SwiftUI drives window height from content; AppKit anchors resizes at
    /// the bottom-left corner. Re-pin the top edge so the search field —
    /// where the eyes are — never jumps.
    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        let frame = panel.frame
        if abs(frame.maxY - desiredTop) > 0.5 {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: desiredTop))
        }
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        self.panel = panel
        return panel
    }
}

/// Borderless windows refuse key status by default; the search field needs
/// it to receive typing while the app stays inactive.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
