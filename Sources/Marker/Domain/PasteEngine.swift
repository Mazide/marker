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
    private let log: (String) -> Void

    init(
        pasteboard: PasteboardControlling,
        keys: KeyEventSynthesizing,
        scheduler: Scheduling,
        config: Config = Config(),
        now: @escaping () -> Date = { Date() },
        log: @escaping (String) -> Void = diagLog
    ) {
        self.pasteboard = pasteboard
        self.keys = keys
        self.scheduler = scheduler
        self.config = config
        self.now = now
        self.log = log
    }

    func pasteIntoActiveApp(_ text: String) {
        pasteIntoActiveApp(RichText(plain: text))
    }

    @discardableResult
    func pasteIntoActiveApp(
        _ content: RichText,
        operationID: String = UUID().uuidString.lowercased(),
        ifStillValid: @escaping () -> Bool = { true },
        onCommit: @escaping () -> Void = {}
    ) -> Bool {
        guard ifStillValid() else {
            log("paste.resolved operation=\(operationID) outcome=rejected reason=invalid_target")
            return false
        }
        log("paste.scheduled operation=\(operationID) chars=\(content.plain.count) rich=\(content.hasFlavors)")
        var accepted = true
        waitForModifierRelease(deadline: now().addingTimeInterval(config.modifierWait)) { [weak self] in
            accepted = self?.performPaste(
                content,
                operationID: operationID,
                ifStillValid: ifStillValid,
                onCommit: onCommit
            ) ?? false
        }
        return accepted
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

    /// Fires when a synthesized Cmd+V is posted, so the capture side can
    /// ignore the AX churn the paste causes in the target field.
    var onPaste: (() -> Void)?

    private func performPaste(
        _ content: RichText,
        operationID: String,
        ifStillValid: () -> Bool,
        onCommit: () -> Void
    ) -> Bool {
        guard ifStillValid() else {
            log("paste.resolved operation=\(operationID) outcome=rejected reason=target_changed_while_waiting")
            return false
        }
        let saved = pasteboard.snapshot()
        guard ifStillValid() else {
            log("paste.resolved operation=\(operationID) outcome=rejected reason=target_changed_during_snapshot")
            return false
        }
        pasteboard.writeContent(content)
        guard ifStillValid() else {
            pasteboard.restore(saved)
            log("paste.resolved operation=\(operationID) outcome=rejected reason=target_changed_before_dispatch")
            return false
        }
        markerLog.info("paste: \(content.plain.count) chars via Cmd+V rich=\(content.hasFlavors)")
        keys.postPaste()
        log("paste.committed operation=\(operationID)")
        onCommit()
        onPaste?()
        scheduler.schedule(after: config.restoreDelay) { [pasteboard, log] in
            pasteboard.restore(saved)
            log("paste.clipboard_restored operation=\(operationID)")
        }
        return true
    }
}
