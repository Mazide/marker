import XCTest
@testable import Marker

final class ThreeFingerTapDetectorTests: XCTestCase {
    private var detector = ThreeFingerTapDetector()

    func testQuickThreeFingerTapDetected() {
        XCTAssertFalse(detector.frame(fingers: 3, centroid: nil, at: 0))
        XCTAssertFalse(detector.frame(fingers: 3, centroid: nil, at: 0.05))
        XCTAssertTrue(detector.frame(fingers: 0, centroid: nil, at: 0.12))
    }

    func testStaggeredFingerLandingStillCounts() {
        _ = detector.frame(fingers: 1, centroid: nil, at: 0)
        _ = detector.frame(fingers: 2, centroid: nil, at: 0.02)
        _ = detector.frame(fingers: 3, centroid: nil, at: 0.04)
        _ = detector.frame(fingers: 1, centroid: nil, at: 0.10)
        XCTAssertTrue(detector.frame(fingers: 0, centroid: nil, at: 0.14))
    }

    func testTwoFingerTapIgnored() {
        _ = detector.frame(fingers: 2, centroid: nil, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 0.1))
    }

    func testFourFingerTapIgnored() {
        _ = detector.frame(fingers: 3, centroid: nil, at: 0)
        _ = detector.frame(fingers: 4, centroid: nil, at: 0.03)
        _ = detector.frame(fingers: 0, centroid: nil, at: 0.1)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 0.1))
    }

    func testLongHoldIgnored() {
        _ = detector.frame(fingers: 3, centroid: nil, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 1.0), "holds are too long")
    }

    func testTooShortBlipIgnored() {
        _ = detector.frame(fingers: 3, centroid: nil, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 0.02), "sub-60ms contact is noise")
    }

    func testSecondTapWorksAfterFirst() {
        _ = detector.frame(fingers: 3, centroid: nil, at: 0)
        XCTAssertTrue(detector.frame(fingers: 0, centroid: nil, at: 0.1))
        _ = detector.frame(fingers: 3, centroid: nil, at: 1.0)
        XCTAssertTrue(detector.frame(fingers: 0, centroid: nil, at: 1.1))
    }

    func testMovingThreeFingersIsASwipeNotATap() {
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.5), at: 0)
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.62), at: 0.15)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 0.3), "centroid moved: swipe")
    }

    func testRelaxedSlowTapCounts() {
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.5), at: 0)
        _ = detector.frame(fingers: 3, centroid: (0.51, 0.5), at: 0.4)
        XCTAssertTrue(detector.frame(fingers: 0, centroid: nil, at: 0.6), "600ms stationary tap is a tap")
    }

    func testScrollWithStrayThirdFingerIgnored() {
        _ = detector.frame(fingers: 2, centroid: (0.5, 0.3), at: 0)
        _ = detector.frame(fingers: 2, centroid: (0.5, 0.5), at: 0.25)
        _ = detector.frame(fingers: 3, centroid: (0.45, 0.55), at: 0.35)
        _ = detector.frame(fingers: 3, centroid: (0.45, 0.56), at: 0.4)
        _ = detector.frame(fingers: 2, centroid: (0.5, 0.6), at: 0.45)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 0.55), "third finger joined mid-scroll")
    }

    func testMovingTwoFingerSegmentDisqualifiesEvenWithEarlyThird() {
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.3), at: 0)
        _ = detector.frame(fingers: 2, centroid: (0.5, 0.35), at: 0.1)
        _ = detector.frame(fingers: 2, centroid: (0.5, 0.55), at: 0.3)
        XCTAssertFalse(detector.frame(fingers: 0, centroid: nil, at: 0.4), "session scrolled after the tap window")
    }

    func testCentroidJumpAcrossFingerCountChangeIsNotMovement() {
        _ = detector.frame(fingers: 2, centroid: (0.5, 0.5), at: 0)
        _ = detector.frame(fingers: 3, centroid: (0.42, 0.55), at: 0.03)
        _ = detector.frame(fingers: 3, centroid: (0.42, 0.55), at: 0.08)
        XCTAssertTrue(detector.frame(fingers: 0, centroid: nil, at: 0.12), "count-change centroid jump is not a swipe")
    }
}

final class ThreeFingerDoubleTapDetectorTests: XCTestCase {
    private var detector = ThreeFingerDoubleTapDetector()

    private func tap(from start: TimeInterval, duration: TimeInterval = 0.1) -> Bool {
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.5), at: start)
        return detector.frame(fingers: 0, centroid: nil, at: start + duration)
    }

    func testTwoQuickTapsFire() {
        XCTAssertFalse(tap(from: 0))
        XCTAssertTrue(tap(from: 0.25), "second tap within the gap fires")
    }

    func testSingleTapDoesNotFire() {
        XCTAssertFalse(tap(from: 0))
    }

    func testSlowPairDoesNotFire() {
        XCTAssertFalse(tap(from: 0))
        XCTAssertFalse(tap(from: 0.8), "gap exceeded: taps are independent")
    }

    func testSlowPairSecondTapStartsANewPair() {
        _ = tap(from: 0)
        _ = tap(from: 0.8)
        XCTAssertTrue(tap(from: 1.1), "late tap becomes the first of the next pair")
    }

    func testThirdTapAfterAPairStartsFresh() {
        _ = tap(from: 0)
        XCTAssertTrue(tap(from: 0.25))
        XCTAssertFalse(tap(from: 0.5), "pair consumed; a lone follow-up tap does not fire")
        XCTAssertTrue(tap(from: 0.75), "…but it seeds the next pair")
    }

    func testScrollBetweenTapsDoesNotPair() {
        XCTAssertFalse(tap(from: 0))
        // A swipe session: rejected by the single-tap detector, but it
        // must not extend or reset the pairing window into a false fire.
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.3), at: 0.15)
        _ = detector.frame(fingers: 3, centroid: (0.5, 0.6), at: 0.25)
        _ = detector.frame(fingers: 0, centroid: nil, at: 0.3)
        XCTAssertFalse(tap(from: 0.35), "first tap aged out during the swipe")
    }
}
