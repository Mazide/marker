import Foundation
import Observation

struct SelectionItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let appName: String
    let bundleID: String
    let rtf: Data?
    let html: String?

    init(
        id: UUID,
        text: String,
        date: Date,
        appName: String,
        bundleID: String,
        rtf: Data? = nil,
        html: String? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.appName = appName
        self.bundleID = bundleID
        self.rtf = rtf
        self.html = html
    }

    var content: RichText {
        RichText(plain: text, rtf: rtf, html: html)
    }
}

/// In-memory window over the history database: recent page(s) for the UI,
/// every capture written through immediately (one INSERT, no debounce).
@Observable
@MainActor
final class HistoryStore {
    private(set) var items: [SelectionItem] = []
    private(set) var canLoadMore = false

    /// Refinements of the same selection gesture (double-click a word, then
    /// drag to extend) replace the previous entry within this window.
    private let refinementWindow: TimeInterval = 12
    private let pageSize: Int

    private let db: HistoryDatabase
    private let now: () -> Date

    init(
        db: HistoryDatabase,
        pageSize: Int = 200,
        now: @escaping () -> Date = { Date() }
    ) {
        self.db = db
        self.pageSize = pageSize
        self.now = now
        items = db.recent(limit: pageSize, offset: 0)
        canLoadMore = db.count() > items.count
    }

    func push(text rawText: String, app: SourceApp) {
        push(RichText(plain: rawText), app: app)
    }

    func push(_ content: RichText, app: SourceApp) {
        let text = content.plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, items.first?.text != text else { return }

        if let first = items.first,
           first.bundleID == app.bundleID,
           now().timeIntervalSince(first.date) < refinementWindow,
           text.contains(first.text) || first.text.contains(text) {
            items.removeFirst()
            db.delete(id: first.id)
        }

        let item = SelectionItem(
            id: UUID(),
            text: text,
            date: now(),
            appName: app.name,
            bundleID: app.bundleID,
            rtf: content.rtf,
            html: content.html
        )
        items.removeAll { $0.text == text }
        db.deleteAll(text: text)
        items.insert(item, at: 0)
        db.insert(item)
    }

    func delete(_ item: SelectionItem) {
        items.removeAll { $0.id == item.id }
        db.delete(id: item.id)
    }

    /// Drop everything older than `days` (retention setting). `days <= 0`
    /// means "keep forever" and is a no-op.
    func applyRetention(days: Int) {
        guard days > 0 else { return }
        let cutoff = now().addingTimeInterval(-Double(days) * 86400)
        items.removeAll { $0.date < cutoff }
        db.deleteOlderThan(cutoff)
        canLoadMore = db.count() > items.count
    }

    /// Append the next page of older entries to the in-memory window.
    func loadMore() {
        guard canLoadMore else { return }
        let more = db.recent(limit: pageSize, offset: items.count)
        items.append(contentsOf: more)
        canLoadMore = more.count == pageSize
    }

    /// Search the whole database, not just the loaded window.
    func search(text: String?, bundleID: String?) -> [SelectionItem] {
        db.query(text: text, bundleID: bundleID, limit: 500)
    }

    func clear() {
        items = []
        canLoadMore = false
        db.clear()
    }

    /// Unique source apps across the whole history, ordered by name.
    var apps: [(bundleID: String, name: String)] {
        db.apps()
    }
}