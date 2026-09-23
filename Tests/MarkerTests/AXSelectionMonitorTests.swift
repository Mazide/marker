import AppKit
import XCTest
@testable import Marker

final class AXSelectionMonitorTests: XCTestCase {
    func testMissingBoundsRequireExactEditorIdentity() {
        for sameElement in [false, true] {
            XCTAssertEqual(AXSelectionMonitor.hitTargetsFocusedEditable(
                frontmostPID: 11,
                hitPID: 11,
                targetPID: 11,
                focusGenerationMatches: true,
                sameAXElement: sameElement,
                targetRole: "AXTextArea",
                targetFrame: nil,
                point: CGPoint(x: 40, y: 40)
            ), sameElement)
        }
    }

    func testNonEditableOrBackgroundTargetIsRejectedEvenAtSameElement() {
        for (frontmost, role): (pid_t?, String?) in [(22, "AXTextArea"), (nil, "AXTextArea"), (11, "AXGroup"), (11, nil)] {
            XCTAssertFalse(AXSelectionMonitor.hitTargetsFocusedEditable(
                frontmostPID: frontmost,
                hitPID: 11,
                targetPID: 11,
                focusGenerationMatches: true,
                sameAXElement: true,
                targetRole: role,
                targetFrame: CGRect(x: 10, y: 20, width: 300, height: 80),
                point: CGPoint(x: 40, y: 40)
            ))
        }
    }

    func testClickMustBelongToFrontmostFocusedEditor() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 80)
        let point = CGPoint(x: 40, y: 40)

        XCTAssertTrue(AXSelectionMonitor.hitTargetsFocusedEditable(
            frontmostPID: 11,
            hitPID: 11,
            targetPID: 11,
            focusGenerationMatches: true,
            sameAXElement: false,
            targetRole: "AXTextArea",
            targetFrame: frame,
            point: point
        ))
        XCTAssertFalse(AXSelectionMonitor.hitTargetsFocusedEditable(
            frontmostPID: 11,
            hitPID: 22,
            targetPID: 11,
            focusGenerationMatches: true,
            sameAXElement: false,
            targetRole: "AXTextArea",
            targetFrame: frame,
            point: point
        ), "a pre-activation click in another app must pass through")
        XCTAssertFalse(AXSelectionMonitor.hitTargetsFocusedEditable(
            frontmostPID: 11,
            hitPID: 11,
            targetPID: 11,
            focusGenerationMatches: true,
            sameAXElement: false,
            targetRole: "AXTextArea",
            targetFrame: frame,
            point: CGPoint(x: 40, y: 400)
        ), "a different control in the same app must not paste into stale focus")
        XCTAssertFalse(AXSelectionMonitor.hitTargetsFocusedEditable(
            frontmostPID: 11,
            hitPID: 11,
            targetPID: 11,
            focusGenerationMatches: false,
            sameAXElement: true,
            targetRole: "AXTextArea",
            targetFrame: frame,
            point: point
        ))
    }

}
