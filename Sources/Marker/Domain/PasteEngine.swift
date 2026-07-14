import Foundation

/// The ⌥V paste flow: wait for physical modifiers to clear (the hotkey IS
/// ⌥V — pasting while Option is held sends ⌥⌘V), swap the clipboard,
/// synthesize Cmd+V, restore the previous clipboard.
@MainActor
final class PasteEngine {
    struct Config {
        var modifierPollInterval: TimeInterval = 0.05
        var modifierWait: TimeInterval = 1.0
        var restoreDelay: TimeInterval = 0.3
    }

    private let pasteboard: PasteboardControlling
    private let keys: KeyEventSynthesizing
    private let scheduler: Scheduling
    private let config: Config
    private let now: () -> Date

    init(
        pasteboard: PasteboardControlling,
        keys: KeyEventSynthesizing,
        scheduler: Scheduling,
        config: Config = Config(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.pasteboard = pasteboard
        self.keys = keys
        self.scheduler = scheduler
        self.config = config
        self.now = now
    }

    func pasteIntoActiveApp(_ text: String) {
        pasteIntoActiveApp(RichText(plain: text))
    }

    func pasteIntoActiveApp(_ content: RichText) {
        waitForModifierRelease(deadline: now().addingTimeInterval(config.modifierWait)) { [weak self] in
            self?.performPaste(content)
        }
    }

    private func waitForModifierRelease(deadline: Date, then action: @escaping () -> Void) {
        if keys.modifiersReleased() || now() > deadline {
            action()
        } else {
            scheduler.schedule(after: config.modifierPollInterval) { [weak self] in
                self?.waitForModifierRelease(deadline: deadline, then: action)
            }
        }
    }

    private func performPaste(_ content: RichText) {
        let saved = pasteboard.snapshot()
        pasteboard.writeContent(content)
        markerLog.info("paste: \(content.plain.count) chars via Cmd+V rich=\(content.hasFlavors)")
        keys.postPaste()
        scheduler.schedule(after: config.restoreDelay) { [pasteboard] in
            pasteboard.restore(saved)
        }
    }
}