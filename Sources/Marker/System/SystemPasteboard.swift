import AppKit

final class SystemPasteboard: PasteboardControlling {
    private struct Snapshot: PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func writeString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func snapshot() -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
        return Snapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        guard let snapshot = snapshot as? Snapshot else { return }
        pasteboard.clearContents()
        let items = snapshot.items.map { entry in
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

    func containsFileURLs() -> Bool {
        pasteboard.availableType(from: [.fileURL]) != nil
    }
}