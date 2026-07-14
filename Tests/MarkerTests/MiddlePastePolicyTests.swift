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

    func testFallsBackToFocusedElementForBareAXTrees() {
        // kitty and friends hit-test as AXWindow (or nothing) but focus
        // an AXTextArea.
        XCTAssertTrue(MiddlePastePolicy.shouldPaste(
            cursorRole: "AXWindow", focusedRole: { "AXTextArea" }))
        XCTAssertTrue(MiddlePastePolicy.shouldPaste(
            cursorRole: nil, focusedRole: { "AXTextArea" }))
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(
            cursorRole: "AXWindow", focusedRole: { "AXWebArea" }))
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(
            cursorRole: nil, focusedRole: { nil }))
    }

    func testNoFallbackOverRolesWithOwnClickSemantics() {
        // A focused text field elsewhere must not swallow a middle-click
        // on a link or page content.
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(
            cursorRole: "AXLink", focusedRole: { "AXTextField" }))
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(
            cursorRole: "AXGroup", focusedRole: { "AXTextField" }))
        XCTAssertFalse(MiddlePastePolicy.shouldPaste(
            cursorRole: "AXWebArea", focusedRole: { "AXTextField" }))
    }

    func testCursorRoleWinsWithoutTouchingFocus() {
        XCTAssertTrue(MiddlePastePolicy.shouldPaste(
            cursorRole: "AXTextField",
            focusedRole: { XCTFail("focused role must not be queried"); return nil }))
    }
}