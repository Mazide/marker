import AppKit

/// Last-resort capture for apps that don't expose selections via
/// Accessibility (Telegram, kitty, Sublime, …): synthesize Cmd+C, grab the
/// copied string, then restore the clipboard to its previous contents.
typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

enum FallbackCopier {
    typealias Snapshot = PasteboardSnapshot

    static func capture(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let saved = snapshot(pasteboard)
        postCmdC()
        poll(pasteboard, before: before, saved: saved, attemptsLeft: 16, completion: completion)
    }

    /// Cmd+C lands asynchronously; poll the change count instead of using
    /// one fixed delay so fast apps return quickly and slow apps still work.
    private static func poll(
        _ pasteboard: NSPasteboard,
        before: Int,
        saved: Snapshot,
        attemptsLeft: Int,
        completion: @escaping (String?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if pasteboard.changeCount != before {
                // A file copy (e.g. Finder) is not a text selection.
                let isFileCopy = pasteboard.availableType(from: [.fileURL]) != nil
                let text = isFileCopy ? nil : pasteboard.string(forType: .string)
                restore(pasteboard, from: saved)
                completion(text)
            } else if attemptsLeft > 0 {
                poll(pasteboard, before: before, saved: saved,
                     attemptsLeft: attemptsLeft - 1, completion: completion)
            } else {
                // Nothing was copied — the app had no selection. Clipboard
                // untouched, nothing to restore.
                markerLog.debug("fallback: clipboard never changed")
                completion(nil)
            }
        }
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    static func restore(_ pasteboard: NSPasteboard, from saved: Snapshot) {
        pasteboard.clearContents()
        let items = saved.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func postCmdC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(8) // kVK_ANSI_C
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
