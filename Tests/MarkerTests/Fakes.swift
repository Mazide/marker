import Foundation
@testable import Marker

final class FakePasteboard: PasteboardControlling {
    struct Snapshot: PasteboardSnapshot {
        let value: String?
    }

    private(set) var changeCount = 0
    private(set) var current: String?
    private(set) var restoredValues: [String?] = []
    var fileURLsOnBoard = false

    func readString() -> String? { current }

    func writeString(_ string: String) {
        current = string
        changeCount += 1
    }

    func snapshot() -> PasteboardSnapshot { Snapshot(value: current) }

    func restore(_ snapshot: PasteboardSnapshot) {
        guard let snapshot = snapshot as? Snapshot else { return }
        restoredValues.append(snapshot.value)
        current = snapshot.value
        changeCount += 1
    }

    func containsFileURLs() -> Bool { fileURLsOnBoard }

    /// Simulate another process writing to the clipboard.
    func externalWrite(_ string: String) {
        current = string
        changeCount += 1
    }
}

final class FakeKeys: KeyEventSynthesizing {
    var copyCount = 0
    var pasteCount = 0
    var modifiersHeld = false
    var onCopy: (() -> Void)?

    func postCopy() {
        copyCount += 1
        onCopy?()
    }

    func postPaste() { pasteCount += 1 }

    func modifiersReleased() -> Bool { !modifiersHeld }
}

final class FakeSelectionReader: SelectionReading {
    var selection: String?
    var roleAtMouse: String?

    func currentSelection() -> String? { selection }
    func roleAtMouseLocation() -> String? { roleAtMouse }
}

final class FakeFrontmost: FrontmostAppProviding {
    var app: SourceApp? = SourceApp(pid: 1, bundleID: "com.example.app", name: "Example", isSelf: false)
    func frontmostApp() -> SourceApp? { app }
}

/// Runs scheduled jobs on demand, in order.
final class FakeScheduler: Scheduling {
    final class Token: SchedulerToken {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    private var jobs: [(token: Token, action: () -> Void)] = []

    @discardableResult
    func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) -> SchedulerToken {
        let token = Token()
        jobs.append((token, action))
        return token
    }

    var pendingCount: Int { jobs.count }

    /// Run all currently queued (and subsequently queued) jobs.
    func runAll(limit: Int = 100) {
        var steps = 0
        while !jobs.isEmpty, steps < limit {
            let job = jobs.removeFirst()
            steps += 1
            if !job.token.cancelled {
                job.action()
            }
        }
    }
}

final class InMemoryPersistence: HistoryPersisting {
    var stored: [SelectionItem] = []
    func load() -> [SelectionItem] { stored }
    func save(_ items: [SelectionItem]) { stored = items }
}