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
    /// Plain text plus whatever rich flavors (RTF/HTML) the board holds;
    /// nil when there is no plain text at all.
    func readContent() -> RichText?
    /// Write plain + rich flavors as one multi-flavor item.
    func writeContent(_ content: RichText)
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
    /// Rich (RTF/HTML) version of the current selection, whitespace-trimmed
    /// to match the trimmed plain text. Expensive — called only when a
    /// capture is about to commit. nil when the app exposes no attributed
    /// AX text or no attribute translates to real formatting.
    func currentSelectionRich() -> RichText?
    /// AX role of the element under the mouse cursor.
    func roleAtMouseLocation() -> String?
    /// AX role of the focused element.
    func focusedElementRole() -> String?
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

protocol HistoryDatabase: AnyObject {
    func insert(_ item: SelectionItem)
    func delete(id: UUID)
    func deleteAll(text: String)
    func deleteOlderThan(_ date: Date)
    func clear()
    func recent(limit: Int, offset: Int) -> [SelectionItem]
    /// Case-insensitive search over text and app name, newest first.
    func query(text: String?, bundleID: String?, limit: Int) -> [SelectionItem]
    func apps() -> [(bundleID: String, name: String)]
    func count() -> Int
}