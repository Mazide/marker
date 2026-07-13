import Foundation

// Every interaction with the OS goes through these protocols so the
// domain layer (CaptureEngine, PasteEngine, HistoryStore) is fully
// testable with fakes.

/// Opaque saved pasteboard contents; only the implementation knows the shape.
protocol PasteboardSnapshot {}

protocol PasteboardControlling: AnyObject {
    var changeCount: Int { get }
    func readString() -> String?
    func writeString(_ string: String)
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    func containsFileURLs() -> Bool
}

protocol KeyEventSynthesizing: AnyObject {
    func postCopy()
    func postPaste()
    /// True when no blocking physical modifiers (⌥⇧⌃⌘) are held.
    func modifiersReleased() -> Bool
}

protocol SelectionReading: AnyObject {
    /// Best-effort read of the current selection (notification element
    /// first, focused element as fallback).
    func currentSelection() -> String?
    /// AX role of the element under the mouse cursor.
    func roleAtMouseLocation() -> String?
}

protocol FrontmostAppProviding: AnyObject {
    func frontmostApp() -> SourceApp?
}

protocol SchedulerToken {
    func cancel()
}

protocol Scheduling: AnyObject {
    @discardableResult
    func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) -> SchedulerToken
}

protocol HistoryPersisting {
    func load() -> [SelectionItem]
    func save(_ items: [SelectionItem])
}