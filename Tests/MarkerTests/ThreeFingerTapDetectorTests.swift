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
}
