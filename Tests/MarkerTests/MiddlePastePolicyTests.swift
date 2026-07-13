import XCTest
@testable import Marker

final class MiddlePastePolicyTests: XCTestCase {
    func testPastesInEditableTextRoles() {
        XCTAssertTrue(MiddlePastePolicy.shouldPaste(role: "AXTextArea"))
        XCTAssertTrue(MiddlePastePolicy.shouldPaste(role: "AXTextField"))
        XCTAssertTrue(MiddlePastePolicy.shouldPaste(role: "AXSearchField"))
    }

    func testPassesThroughEverywhereElse() {
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(role: "AXLink"), "middle-click opens links in tabs")
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(role: "AXWebArea"), "middle-click on a page scrolls/does app things")
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(role: "AXButton"))
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(role: nil))
    }
}