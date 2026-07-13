import AppKit
import SwiftUI

/// Small transient HUD under the menu bar (top-right) confirming a capture.
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(text: String) {
        let snippet = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        let hosting = NSHostingView(rootView: ToastView(text: snippet))
        var size = hosting.fittingSize
        size.width = min(size.width, 300)
        let panel = self.panel ?? makePanel()
        panel.contentView = hosting

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - size.width - 12,
            y: visible.maxY - size.height - 8
        )
        let finalFrame = NSRect(origin: origin, size: size)

        if panel.isVisible {
            // Already on screen: glide to the new size/position.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            // Slide down from under the menu bar while fading in.
            var startFrame = finalFrame
            startFrame.origin.y += 14
            panel.setFrame(startFrame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func hide() {
        guard let panel else { return }
        var upFrame = panel.frame
        upFrame.origin.y += 10
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(upFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.panel = panel
        return panel
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 15, height: 15)
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(maxWidth: 280)
        .toastBackground()
        .padding(4)
    }
}

private extension View {
    @ViewBuilder
    func toastBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect()
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
        }
    }
}
