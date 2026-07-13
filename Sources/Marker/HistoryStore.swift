import AppKit
import Observation

struct SelectionItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let appName: String
    let bundleID: String
}

@Observable
@MainActor
final class HistoryStore {
    private(set) var items: [SelectionItem] = []

    private let maxItems = 20
    private let defaultsKey = "selectionHistory"

    init() {
        load()
    }

    func push(text: String, app: NSRunningApplication) {
        guard items.first?.text != text else { return }
        let item = SelectionItem(
            id: UUID(),
            text: text,
            date: .now,
            appName: app.localizedName ?? "Unknown",
            bundleID: app.bundleIdentifier ?? ""
        )
        items.removeAll { $0.text == text }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([SelectionItem].self, from: data)
        else { return }
        items = saved
    }
}
