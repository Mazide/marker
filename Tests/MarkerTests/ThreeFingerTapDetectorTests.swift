import XCTest
@testable import Marker

final class ThreeFingerTapDetectorTests: XCTestCase {
    private var detector = ThreeFingerTapDetector()

    func testQuickThreeFingerTapDetected() {
        XCTAssertFalse(detector.frame(fingers: 3, at: 0))
        XCTAssertFalse(detector.frame(fingers: 3, at: 0.05))
        XCTAssertTrue(detector.frame(fingers: 0, at: 0.12))
    }

    func testStaggeredFingerLandingStillCounts() {
        _ = detector.frame(fingers: 1, at: 0)
        _ = detector.frame(fingers: 2, at: 0.02)
        _ = detector.frame(fingers: 3, at: 0.04)
        _ = detector.frame(fingers: 1, at: 0.10)
        XCTAssertTrue(detector.frame(fingers: 0, at: 0.14))
    }

    func testTwoFingerTapIgnored() {
        _ = detector.frame(fingers: 2, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.1))
    }

    func testFourFingerTapIgnored() {
        _ = detector.frame(fingers: 3, at: 0)
        _ = detector.frame(fingers: 4, at: 0.03)
        _ = detector.frame(fingers: 0, at: 0.1)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.1))
    }

    func testLongHoldOrSwipeIgnored() {
        _ = detector.frame(fingers: 3, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.5), "swipes and holds are too long")
    }

    func testTooShortBlipIgnored() {
        _ = detector.frame(fingers: 3, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.02), "sub-60ms contact is noise")
    }

    func testSecondTapWorksAfterFirst() {
        _ = detector.frame(fingers: 3, at: 0)
        XCTAssertTrue(detector.frame(fingers: 0, at: 0.1))
        _ = detector.frame(fingers: 3, at: 1.0)
        XCTAssertTrue(detector.frame(fingers: 0, at: 1.1))
    }
}