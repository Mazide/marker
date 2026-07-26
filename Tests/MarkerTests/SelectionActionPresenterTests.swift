import AppKit
import XCTest
@testable import Marker

@MainActor
final class SelectionActionPresenterTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1_000, height: 800)
    private let size = NSSize(width: 100, height: 32)

    func testPlacesActionAboveAndRightOfPointerByDefault() {
        let frame = SelectionActionPresenter.positionedFrame(
            size: size,
            anchor: NSPoint(x: 400, y: 300),
            visibleFrame: screen
        )

        XCTAssertEqual(frame.origin.x, 410)
        XCTAssertEqual(frame.origin.y, 310)
    }

    func testFlipsActionLeftAtRightScreenEdge() {
        let frame = SelectionActionPresenter.positionedFrame(
            size: size,
            anchor: NSPoint(x: 990, y: 300),
            visibleFrame: screen
        )

        XCTAssertEqual(frame.origin.x, 880)
        XCTAssertEqual(frame.origin.y, 310)
    }

    func testFlipsActionBelowAtTopScreenEdge() {
        let frame = SelectionActionPresenter.positionedFrame(
            size: size,
            anchor: NSPoint(x: 400, y: 795),
            visibleFrame: screen
        )

        XCTAssertEqual(frame.origin.x, 410)
        XCTAssertEqual(frame.origin.y, 753)
    }

    func testClampsActionInsideVisibleScreen() {
        let frame = SelectionActionPresenter.positionedFrame(
            size: size,
            anchor: NSPoint(x: -20, y: -20),
            visibleFrame: screen
        )

        XCTAssertEqual(frame.minX, 6)
        XCTAssertEqual(frame.minY, 6)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX - 6)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY - 6)
    }

    func testPasteConfirmationUsesActionAnchorRule() {
        let frame = SelectionActionPresenter.positionedFrame(
            size: NSSize(width: 80, height: 42),
            anchor: NSPoint(x: 400, y: 300),
            visibleFrame: screen
        )

        XCTAssertEqual(frame.minX, 410)
        XCTAssertEqual(frame.minY, 310)
    }

    func testPasteConfirmationUsesActionFlipRuleAtTopEdge() {
        let frame = SelectionActionPresenter.positionedFrame(
            size: NSSize(width: 80, height: 42),
            anchor: NSPoint(x: 400, y: 795),
            visibleFrame: screen
        )

        XCTAssertEqual(frame.minX, 410)
        XCTAssertEqual(frame.maxY, 785)
    }
}
