import Foundation

/// FIFO queue over a burst of captures, so "select three fields, then
/// ⌥V ⌥V ⌥V" pastes them in selection order. Bursts are captures close in
/// time; a stale queue expires so ⌥V falls back to "paste the latest".
struct PasteQueue {
    struct Next: Equatable {
        let text: String
        let index: Int
        let total: Int
    }

    /// A capture further than this from the previous one starts a new burst.
    var burstGap: TimeInterval = 60
    /// ⌥V this long after the last activity ignores the queue entirely.
    var staleAfter: TimeInterval = 60
    /// Same-gesture refinements replace the queue tail within this window.
    var refinementWindow: TimeInterval = 12

    private var pending: [String] = []
    private var pastedCount = 0
    private var lastActivity: Date?

    mutating func captured(_ text: String, at date: Date) {
        if let last = lastActivity, date.timeIntervalSince(last) > burstGap {
            pending = []
            pastedCount = 0
        }
        if let tail = pending.last,
           let last = lastActivity,
           date.timeIntervalSince(last) < refinementWindow,
           text.contains(tail) || tail.contains(text) {
            pending[pending.count - 1] = text
        } else {
            pending.append(text)
        }
        lastActivity = date
    }

    /// The next queued text for ⌥V, oldest first; nil when the queue is
    /// empty or stale (caller falls back to the latest history item).
    mutating func nextForPaste(at date: Date) -> Next? {
        if let last = lastActivity, date.timeIntervalSince(last) > staleAfter {
            pending = []
            pastedCount = 0
            return nil
        }
        guard !pending.isEmpty else { return nil }
        let text = pending.removeFirst()
        pastedCount += 1
        lastActivity = date
        return Next(text: text, index: pastedCount, total: pastedCount + pending.count)
    }
}