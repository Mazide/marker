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
    /// false distinguishes an unreadable database from a genuinely empty one.
    private(set) var isReadable = true
    /// Captures waiting in the crash-safe recovery queue.
    private(set) var hasPendingWrites = false

    /// Refinements of the same selection gesture (double-click a word, then
    /// drag to extend) replace the previous entry within this window.
    private let refinementWindow: TimeInterval = 12
    private let pageSize: Int

    private let db: HistoryDatabase
    private let now: () -> Date
    @ObservationIgnored private let recoveryURL: URL?
    @ObservationIgnored private var pendingWrites: [PendingWrite]
    @ObservationIgnored private var recoveryQueueWritable: Bool

    private struct PendingWrite: Codable {
        let item: SelectionItem
        let deletingIDs: Set<UUID>
    }

    init(
        db: HistoryDatabase,
        pageSize: Int = 200,
        recoveryURL: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.db = db
        self.pageSize = pageSize
        self.recoveryURL = recoveryURL
        self.now = now
        let recovered = Self.loadPendingWrites(from: recoveryURL)
        pendingWrites = recovered.writes
        recoveryQueueWritable = recovered.safeToOverwrite
        hasPendingWrites = !pendingWrites.isEmpty
        flushPendingWrites()
        if let recent = db.recent(limit: pageSize, offset: 0) {
            items = mergingPendingWrites(into: recent)
            canLoadMore = (db.count() ?? items.count) > recent.count
        } else {
            isReadable = false
            items = mergingPendingWrites(into: [])
        }
    }

    @discardableResult
    func push(text rawText: String, app: SourceApp) -> Bool {
        push(RichText(plain: rawText), app: app)
    }

    /// Returns false while the item is waiting in the recovery queue. The
    /// queue is written before SQLite, so a failed database write survives
    /// an updater relaunch instead of existing only in this process's RAM.
    @discardableResult
    func push(_ content: RichText, app: SourceApp) -> Bool {
        let text = content.plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if items.first?.text == text {
            flushPendingWrites()
            return !pendingWrites.contains { $0.item.text == text }
        }

        var deletingIDs = Set<UUID>()
        if let first = items.first,
           first.bundleID == app.bundleID,
           now().timeIntervalSince(first.date) < refinementWindow,
           text.contains(first.text) || first.text.contains(text) {
            deletingIDs.insert(first.id)
            inheritPendingDeletions(from: first.id, into: &deletingIDs)
            items.removeFirst()
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

        // A pending predecessor may represent an older durable row. Carry
        // that tombstone forward when this capture supersedes it.
        let supersededPending = pendingWrites.filter {
            deletingIDs.contains($0.item.id) || $0.item.text == text
        }
        for pending in supersededPending {
            deletingIDs.formUnion(pending.deletingIDs)
            deletingIDs.insert(pending.item.id)
        }
        pendingWrites.removeAll {
            deletingIDs.contains($0.item.id) || $0.item.text == text
        }

        items.removeAll { $0.text == text }
        items.insert(item, at: 0)

        pendingWrites.append(PendingWrite(item: item, deletingIDs: deletingIDs))
        hasPendingWrites = true
        let recoverySaved = persistPendingWrites()
        flushPendingWrites()

        let saved = !pendingWrites.contains { $0.item.id == item.id }
        if !saved, !recoverySaved {
            markerLog.error("history recovery queue write failed; capture remains in memory only")
        }
        return saved
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
        pendingWrites.removeAll { $0.item.date < cutoff }
        hasPendingWrites = !pendingWrites.isEmpty
        _ = persistPendingWrites()
        db.deleteOlderThan(cutoff)
        canLoadMore = (db.count() ?? items.count) > items.count
    }

    /// Re-read the loaded window from the database. External writers
    /// (marker-cli add, a second instance) insert rows behind the app's
    /// back; call this before showing or pasting "the latest" so their
    /// entries count.
    func refresh() {
        flushPendingWrites()
        let limit = max(items.count, pageSize)
        guard let recent = db.recent(limit: limit, offset: 0) else {
            isReadable = false
            return
        }
        isReadable = true
        items = mergingPendingWrites(into: recent)
        canLoadMore = (db.count() ?? items.count) > recent.count
    }

    /// Append the next page of older entries to the in-memory window.
    func loadMore() {
        guard canLoadMore else { return }
        guard let more = db.recent(limit: pageSize, offset: items.count) else {
            isReadable = false
            return
        }
        isReadable = true
        items.append(contentsOf: more)
        canLoadMore = more.count == pageSize
    }

    /// Search the whole database, not just the loaded window.
    func search(text: String?, bundleID: String?) -> [SelectionItem] {
        let candidates: [SelectionItem]
        if let persisted = db.query(text: text, bundleID: bundleID, limit: 500) {
            candidates = mergingPendingWrites(into: persisted)
        } else {
            candidates = items
        }
        return candidates.filter { item in
            if let bundleID, item.bundleID != bundleID { return false }
            guard let text, !text.isEmpty else { return true }
            let needle = text.lowercased()
            return item.text.lowercased().contains(needle)
                || item.appName.lowercased().contains(needle)
        }
    }

    func clear() {
        items = []
        canLoadMore = false
        pendingWrites = []
        hasPendingWrites = false
        _ = persistPendingWrites()
        db.clear()
    }

    /// Unique source apps across the whole history, ordered by name.
    var apps: [(bundleID: String, name: String)] {
        var result = db.apps() ?? []
        if result.isEmpty {
            for item in items where !item.bundleID.isEmpty
                && !result.contains(where: { $0.bundleID == item.bundleID }) {
                result.append((item.bundleID, item.appName))
            }
        }
        var seen = Set(result.map(\.bundleID))
        for pending in pendingWrites where !pending.item.bundleID.isEmpty {
            if seen.insert(pending.item.bundleID).inserted {
                result.append((pending.item.bundleID, pending.item.appName))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Crash-safe recovery queue

    private func inheritPendingDeletions(from id: UUID, into ids: inout Set<UUID>) {
        guard let pending = pendingWrites.first(where: { $0.item.id == id }) else { return }
        ids.formUnion(pending.deletingIDs)
    }

    private func flushPendingWrites() {
        guard !pendingWrites.isEmpty else {
            hasPendingWrites = false
            return
        }

        let original = pendingWrites
        pendingWrites = original.filter { pending in
            !db.save(pending.item, deletingIDs: pending.deletingIDs)
        }
        hasPendingWrites = !pendingWrites.isEmpty
        if pendingWrites.count != original.count {
            _ = persistPendingWrites()
        }
    }

    private func mergingPendingWrites(into persisted: [SelectionItem]) -> [SelectionItem] {
        var result = persisted
        for pending in pendingWrites {
            result.removeAll {
                pending.deletingIDs.contains($0.id)
                    || $0.id == pending.item.id
                    || $0.text == pending.item.text
            }
            result.append(pending.item)
        }
        return result.sorted { $0.date > $1.date }
    }

    @discardableResult
    private func persistPendingWrites() -> Bool {
        guard let recoveryURL else { return pendingWrites.isEmpty }
        guard recoveryQueueWritable else { return false }
        do {
            if pendingWrites.isEmpty {
                if FileManager.default.fileExists(atPath: recoveryURL.path) {
                    try FileManager.default.removeItem(at: recoveryURL)
                }
                return true
            }

            try FileManager.default.createDirectory(
                at: recoveryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(pendingWrites)
            try data.write(to: recoveryURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: recoveryURL.path
            )
            return true
        } catch {
            markerLog.error("history recovery queue failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func loadPendingWrites(
        from url: URL?
    ) -> (writes: [PendingWrite], safeToOverwrite: Bool) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return ([], true)
        }
        do {
            let writes = try JSONDecoder().decode([PendingWrite].self, from: Data(contentsOf: url))
            return (writes, true)
        } catch {
            // Never overwrite an unreadable recovery file: preserving it is
            // safer than silently discarding captures after an update.
            markerLog.error("history recovery queue unreadable: \(error.localizedDescription, privacy: .public)")
            return ([], false)
        }
    }
}
