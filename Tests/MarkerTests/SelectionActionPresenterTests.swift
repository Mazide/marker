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

    func testShadowInsetKeepsVisiblePillAtAnchorGap() {
        let inset: CGFloat = 14
        let frame = SelectionActionPresenter.positionedFrame(
            size: NSSize(width: 128, height: 60),
            anchor: NSPoint(x: 400, y: 300),
            visibleFrame: screen,
            contentInset: inset
        )

        XCTAssertEqual(frame.minX + inset, 410)
        XCTAssertEqual(frame.minY + inset, 310)
    }

    func testShadowInsetKeepsFlippedPillAtAnchorGap() {
        let inset: CGFloat = 14
        let frame = SelectionActionPresenter.positionedFrame(
            size: NSSize(width: 128, height: 60),
            anchor: NSPoint(x: 990, y: 780),
            visibleFrame: screen,
            contentInset: inset
        )

        XCTAssertEqual(frame.maxX - inset, 980)
        XCTAssertEqual(frame.maxY - inset, 770)
    }

    func testDirectionalSettleComesFromSelectionCenter() {
        let offset = SelectionActionPresenter.directionalSettleOffset(
            selectionCenter: NSPoint(x: 10, y: 20),
            anchor: NSPoint(x: 13, y: 24)
        )

        XCTAssertEqual(offset.width, -3.6, accuracy: 0.001)
        XCTAssertEqual(offset.height, -4.8, accuracy: 0.001)
    }

    func testDirectionalSettleFallsBackFromLeftWithoutSelectionVector() {
        let offset = SelectionActionPresenter.directionalSettleOffset(
            selectionCenter: nil,
            anchor: NSPoint(x: 100, y: 100)
        )

        XCTAssertEqual(offset, CGSize(width: -6, height: 0))
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
