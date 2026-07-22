import AppKit
import SwiftUI

/// Small transient HUD under the menu bar (top-right) confirming a capture.
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(text: String, appName: String, bundleID: String, warning: String? = nil) {
        present(ToastView(text: snippet(of: text), appName: appName, bundleID: bundleID, warning: warning))
    }

    /// Attribution for gesture pastes (three-finger click, middle-click):
    /// they fire with no visible chrome, so say the insert was us.
    func showPaste(text: String, source: PasteToastSource) {
        present(PasteToastView(text: snippet(of: text), source: source))
    }

    /// A popover pick landed in Marker's paste slot; tell the user how to
    /// fire it — the popover has already closed by the time this shows.
    func showReady(text: String, hotkeyLabel: String) {
        present(ReadyToastView(text: snippet(of: text), hotkeyLabel: hotkeyLabel))
    }

    private func snippet(of text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func present(_ view: some View) {
        let hosting = NSHostingView(rootView: view)
        var size = hosting.fittingSize
        size.height = min(size.height, 120)
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

enum PasteToastSource {
    case threeFingerClick
    case threeFingerDoubleTap
    case middleClick
}

private struct PasteToastView: View {
    let text: String
    let source: PasteToastSource

    private var sourceLabel: Text {
        switch source {
        case .threeFingerClick: Text("three-finger click")
        case .threeFingerDoubleTap: Text("three-finger double tap")
        case .middleClick: Text("middle-click")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 14, height: 14)
                Text("Marker")
                    .font(.caption2.weight(.semibold))
                Text("· pasted via")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: source == .middleClick ? "computermouse" : "hand.tap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                sourceLabel
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: 12.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 330, alignment: .leading)
        .toastBackground()
        .padding(5)
    }
}

private struct ReadyToastView: View {
    let text: String
    let hotkeyLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 14, height: 14)
                Text("Marker")
                    .font(.caption2.weight(.semibold))
                Text("· \(hotkeyLabel) pastes this")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: 12.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 330, alignment: .leading)
        .toastBackground()
        .padding(5)
    }
}

private struct ToastView: View {
    let text: String
    let appName: String
    let bundleID: String
    var warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 14, height: 14)
                Text("Marker")
                    .font(.caption2.weight(.semibold))
                Text("· captured from")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(nsImage: AppIcons.icon(for: bundleID))
                    .resizable()
                    .frame(width: 12, height: 12)
                Text(appName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: 12.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 330, alignment: .leading)
        .toastBackground()
        .padding(5)
    }
}

private extension View {
    @ViewBuilder
    func toastBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(in: .rect(cornerRadius: 14))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.5)))
        }
    }
}
