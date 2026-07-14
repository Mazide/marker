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

    func readContent() -> RichText? {
        guard let plain = pasteboard.string(forType: .string) else { return nil }
        var content = RichText(plain: plain)
        if let rtf = pasteboard.data(forType: .rtf),
           rtf.count <= RichText.flavorByteLimit {
            content.rtf = rtf
        }
        if let html = pasteboard.string(forType: .html),
           html.utf8.count <= RichText.flavorByteLimit {
            content.html = html
        }
        return content
    }

    func writeContent(_ content: RichText) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(content.plain, forType: .string)
        if let rtf = content.rtf {
            item.setData(rtf, forType: .rtf)
        }
        if let html = content.html {
            item.setString(html, forType: .html)
        }
        pasteboard.writeObjects([item])
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