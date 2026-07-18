import XCTest
@testable import Marker

final class PastePolicyTests: XCTestCase {
    private func item(_ text: String) -> SelectionItem {
        SelectionItem(
            id: UUID(),
            text: text,
            date: Date(),
            appName: "Example",
            bundleID: "com.example.app"
        )
    }

    func testPastesNewestWhenNothingIsSelected() {
        let history = [item("new"), item("old")]
        XCTAssertEqual(PastePolicy.item(history: history, currentSelection: nil)?.text, "new")
        XCTAssertEqual(PastePolicy.item(history: history, currentSelection: "")?.text, "new")
    }

    func testPastesNewestWhenSelectionDiffers() {
        let history = [item("new"), item("old")]
        XCTAssertEqual(PastePolicy.item(history: history, currentSelection: "unrelated")?.text, "new")
    }

    /// The select-to-replace trap: selecting the address bar makes its URL
    /// the newest entry; pasting must reach past it, not echo it back.
    func testSkipsNewestWhenItIsTheCurrentSelection() {
        let history = [item("https://vc.ru"), item("what I wanted")]
        let picked = PastePolicy.item(history: history, currentSelection: "https://vc.ru")
        XCTAssertEqual(picked?.text, "what I wanted")
    }

    func testSelectionComparisonIgnoresSurroundingWhitespace() {
        // Captures are trimmed; raw AX selections are not.
        let history = [item("select all"), item("previous")]
        let picked = PastePolicy.item(history: history, currentSelection: "  select all \n")
        XCTAssertEqual(picked?.text, "previous")
    }

    func testNothingToPasteWhenOnlyEntryIsTheSelection() {
        let history = [item("only")]
        XCTAssertNil(PastePolicy.item(history: history, currentSelection: "only"))
    }

    func testEmptyHistoryPastesNothing() {
        XCTAssertNil(PastePolicy.item(history: [], currentSelection: "anything"))
    }
}
