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

    private let legacyDefaultsKey = "selectionHistory"
    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

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
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Unique source apps present in the history, ordered by name.
    var apps: [(bundleID: String, name: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for item in items where !item.bundleID.isEmpty && seen.insert(item.bundleID).inserted {
            result.append((item.bundleID, item.appName))
        }
        return result.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            items = saved
            return
        }
        // Migrate pre-0.2 history out of UserDefaults.
        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            items = saved
            save()
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
    }
}