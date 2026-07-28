import AppKit
import SwiftUI

/// A mouse-first action for a captured selection. It floats beside the
/// selection gesture's mouse-up point without activating Marker or changing
/// the system clipboard until the user explicitly clicks Copy.
@MainActor
final class SelectionActionPresenter {
    static let shared = SelectionActionPresenter()

    private static let gap: CGFloat = 10
    private static let screenMargin: CGFloat = 6
    fileprivate static let shadowInset: CGFloat = 14

    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var presentationID = 0
    private var copiedPresentationID: Int?

    func show(
        at anchor: NSPoint,
        selectionCenter: NSPoint?,
        savedToHistory: Bool,
        onCopy: @escaping () -> Void
    ) {
        presentationID += 1
        let currentID = presentationID
        copiedPresentationID = nil
        hideTimer?.invalidate()

        let view = SelectionActionView(
            savedToHistory: savedToHistory,
            initialOffset: Self.directionalSettleOffset(
                selectionCenter: selectionCenter,
                anchor: anchor
            ),
            onCopy: { [weak self] in
                guard let self, currentID == self.presentationID else { return }
                self.copiedPresentationID = currentID
                onCopy()
                self.scheduleHide(after: 0.6, presentationID: currentID)
            },
            onHover: { [weak self] hovering in
                guard let self, currentID == self.presentationID else { return }
                guard self.copiedPresentationID != currentID else { return }
                if hovering {
                    self.hideTimer?.invalidate()
                } else {
                    self.scheduleHide(after: 0.9, presentationID: currentID)
                }
            }
        )
        let hosting = NSHostingView(rootView: view.markerThemed())
        let size = hosting.fittingSize
        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.ignoresMouseEvents = false

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        guard let screen else { return }
        let finalFrame = Self.positionedFrame(
            size: size,
            anchor: anchor,
            visibleFrame: screen.visibleFrame,
            contentInset: Self.shadowInset
        )

        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        scheduleHide(after: 2.4, presentationID: currentID)
    }

    func showPasteConfirmation(at anchor: NSPoint) {
        presentationID += 1
        let currentID = presentationID
        copiedPresentationID = nil
        hideTimer?.invalidate()

        let hosting = NSHostingView(rootView: PasteConfirmationView().markerThemed())
        let size = hosting.fittingSize
        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.ignoresMouseEvents = true

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        guard let screen else { return }
        let finalFrame = Self.positionedFrame(
            size: size,
            anchor: anchor,
            visibleFrame: screen.visibleFrame,
            contentInset: Self.shadowInset
        )

        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        scheduleHide(after: 0.9, presentationID: currentID)
    }

    func dismiss() {
        presentationID += 1
        let currentID = presentationID
        copiedPresentationID = nil
        hideTimer?.invalidate()
        hideTimer = nil
        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self,
                      let panel,
                      currentID == self.presentationID
                else { return }
                panel.orderOut(nil)
            }
        }
    }

    static func positionedFrame(
        size: NSSize,
        anchor: NSPoint,
        visibleFrame: NSRect,
        contentInset: CGFloat = 0
    ) -> NSRect {
        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = max(minimumX, visibleFrame.maxX - size.width - screenMargin)
        let minimumY = visibleFrame.minY + screenMargin
        let maximumY = max(minimumY, visibleFrame.maxY - size.height - screenMargin)
        let contentWidth = max(0, size.width - contentInset * 2)
        let contentHeight = max(0, size.height - contentInset * 2)

        var x = anchor.x + gap - contentInset
        if x + size.width > visibleFrame.maxX - screenMargin {
            x = anchor.x - contentWidth - gap - contentInset
        }

        var y = anchor.y + gap - contentInset
        if y + size.height > visibleFrame.maxY - screenMargin {
            y = anchor.y - contentHeight - gap - contentInset
        }

        return NSRect(
            origin: NSPoint(
                x: min(max(x, minimumX), maximumX),
                y: min(max(y, minimumY), maximumY)
            ),
            size: size
        )
    }

    /// Begin six points back toward the selection, then spring to the mouse-up
    /// anchor. Double/shift-click has no measurable selection vector.
    static func directionalSettleOffset(
        selectionCenter: NSPoint?,
        anchor: NSPoint
    ) -> CGSize {
        guard let selectionCenter else {
            return CGSize(width: -6, height: 0)
        }
        let dx = anchor.x - selectionCenter.x
        let dy = anchor.y - selectionCenter.y
        let length = hypot(dx, dy)
        guard length > 0.5 else {
            return CGSize(width: -6, height: 0)
        }
        return CGSize(width: -dx / length * 6, height: -dy / length * 6)
    }

    private func scheduleHide(after delay: TimeInterval, presentationID: Int) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, presentationID == self.presentationID else { return }
                self.dismiss()
            }
        }
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
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }
}

private struct SelectionActionView: View {
    let savedToHistory: Bool
    let initialOffset: CGSize
    let onCopy: () -> Void
    let onHover: (Bool) -> Void

    @AppStorage("pillTheme") private var storedTheme = PillThemeChoice.ink.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var copyHovered = false
    @State private var copiedCheckScale = 1.0
    @State private var copiedCheckOpacity = 1.0
    @State private var flashOpacity = 0.0

    private var choice: PillThemeChoice {
        PillThemeChoice(rawValue: storedTheme) ?? .ink
    }

    private var theme: PillTheme {
        choice.theme(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 9) {
            if savedToHistory {
                SavedBadge(theme: theme, iconSize: 16, badgeSize: 9, frame: 18)
                    .help("Saved to Marker")
                    .accessibilityLabel("Saved to Marker")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(theme.accent)
                    .help("Queued safely — retrying history")
                    .accessibilityLabel("Queued safely — retrying history")
            }

            Divider()
                .frame(height: 16)
                .overlay(theme.border ?? theme.text.opacity(0.14))

            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(theme.success)
                    .scaleEffect(copiedCheckScale)
                    .opacity(copiedCheckOpacity)
                    .help("Copied to Clipboard")
                    .accessibilityLabel("Copied to Clipboard")
            } else {
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(copyHovered ? theme.text : theme.dim)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .animation(.easeOut(duration: 0.1), value: copyHovered)
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")
                .accessibilityLabel("Copy to Clipboard")
                .onHover { hovering in
                    copyHovered = hovering
                    (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
                }
            }
        }
        .font(.system(size: 12))
        .frame(minHeight: 32)
        .padding(.horizontal, 9)
        .selectionActionBackground(
            theme: theme,
            flashOpacity: flashOpacity
        )
        .padding(SelectionActionPresenter.shadowInset)
        .onHover(perform: onHover)
        .modifier(SelectionActionAppearModifier(kind: .action, initialOffset: initialOffset))
    }

    private func copy() {
        guard !copied else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            copyHovered = false
        }
        NSCursor.arrow.set()

        if reduceMotion {
            copiedCheckOpacity = 0
            copied = true
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.12)) {
                    copiedCheckOpacity = 1
                }
            }
        } else {
            copiedCheckScale = 1.4
            copiedCheckOpacity = 1
            flashOpacity = 0.08
            copied = true
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    copiedCheckScale = 1
                }
                withAnimation(.easeOut(duration: 0.35)) {
                    flashOpacity = 0
                }
            }
        }

        onCopy()
    }
}

private struct PasteConfirmationView: View {
    @AppStorage("pillTheme") private var storedTheme = PillThemeChoice.ink.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: PillTheme {
        (PillThemeChoice(rawValue: storedTheme) ?? .ink).theme(for: colorScheme)
    }

    var body: some View {
        SavedBadge(theme: theme, iconSize: 18, badgeSize: 10, frame: 22)
            .padding(7)
            .selectionActionBackground(theme: theme)
            .padding(SelectionActionPresenter.shadowInset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pasted with Marker")
            .modifier(SelectionActionAppearModifier(kind: .paste))
    }
}

/// The settings picker uses the real pill geometry and palette at a compact
/// scale. It is intentionally inert: the surrounding picker owns the click.
struct PillThemePreview: View {
    let choice: PillThemeChoice

    @Environment(\.colorScheme) private var colorScheme

    private var theme: PillTheme {
        choice.theme(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 9) {
            SavedBadge(theme: theme, iconSize: 16, badgeSize: 9, frame: 18)

            Divider()
                .frame(height: 16)
                .overlay(theme.border ?? theme.text.opacity(0.14))

            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(theme.dim)
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 9)
        .selectionActionBackground(theme: theme)
        .scaleEffect(0.72)
        .frame(width: 67, height: 29)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SavedBadge: View {
    let theme: PillTheme
    let iconSize: CGFloat
    let badgeSize: CGFloat
    let frame: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: StatusItemController.icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(theme.dim)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: badgeSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.8), theme.success.opacity(0.8))
                .offset(x: 2, y: 2)
        }
        .frame(width: frame, height: frame)
    }
}

private enum SelectionActionAppearKind {
    case action
    case paste

    var initialOffset: CGSize {
        switch self {
        case .action: CGSize(width: -6, height: 0)
        case .paste: CGSize(width: 0, height: 4)
        }
    }

    var fadeDuration: TimeInterval {
        switch self {
        case .action: 0.15
        case .paste: 0.12
        }
    }
}

private struct SelectionActionAppearModifier: ViewModifier {
    let kind: SelectionActionAppearKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize
    @State private var opacity = 0.0

    init(kind: SelectionActionAppearKind, initialOffset: CGSize? = nil) {
        self.kind = kind
        _offset = State(initialValue: initialOffset ?? kind.initialOffset)
    }

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        offset = .zero
                    }
                } else {
                    let movement: Animation = kind == .action
                        ? .spring(response: 0.3, dampingFraction: 0.75)
                        : .easeOut(duration: 0.12)
                    withAnimation(movement) {
                        offset = .zero
                    }
                }
                withAnimation(.easeOut(duration: kind.fadeDuration)) {
                    opacity = 1
                }
            }
    }
}

private extension View {
    func selectionActionBackground(
        theme: PillTheme,
        flashOpacity: Double = 0
    ) -> some View {
        background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.chip)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.success.opacity(flashOpacity))
                    }
            }
            .overlay {
                if let border = theme.border {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 9, y: 3)
    }
}
