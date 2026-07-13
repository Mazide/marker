import Foundation
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

    /// Refinements of the same selection gesture (double-click a word, then
    /// drag to extend) replace the previous entry within this window.
    private let refinementWindow: TimeInterval = 12

    private let persistence: HistoryPersisting
    private let now: () -> Date

    init(
        persistence: HistoryPersisting = FileHistoryPersistence(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.persistence = persistence
        self.now = now
        items = persistence.load()
    }

    func push(text rawText: String, app: SourceApp) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, items.first?.text != text else { return }

        if let first = items.first,
           first.bundleID == app.bundleID,
           now().timeIntervalSince(first.date) < refinementWindow,
           text.contains(first.text) || first.text.contains(text) {
            items.removeFirst()
        }

        let item = SelectionItem(
            id: UUID(),
            text: text,
            date: now(),
            appName: app.name,
            bundleID: app.bundleID
        )
        items.removeAll { $0.text == text }
        items.insert(item, at: 0)
        persistence.save(items)
    }

    func clear() {
        items = []
        persistence.save(items)
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
}

/// JSON file in Application Support, with one-time migration from the
/// pre-0.2 UserDefaults key.
final class FileHistoryPersistence: HistoryPersisting {
    private let legacyDefaultsKey = "selectionHistory"
    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    func load() -> [SelectionItem] {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            return saved
        }
        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let saved = try? JSONDecoder().decode([SelectionItem].self, from: data) {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            save(saved)
            return saved
        }
        return []
    }

    func save(_ items: [SelectionItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}