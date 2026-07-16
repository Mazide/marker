import XCTest
@testable import Marker

final class ThreeFingerTapDetectorTests: XCTestCase {
    private var detector = ThreeFingerTapDetector()

    func testQuickThreeFingerTapDetected() {
        XCTAssertFalse(detector.frame(fingers: 3, at: 0))
        XCTAssertFalse(detector.frame(fingers: 3, at: 0.05))
        XCTAssertTrue(detector.frame(fingers: 0, at: 0.12))
    }

    func testRealisticRelaxedTapCounts() {
        // Numbers from live logs: staggered landing ~400ms in, ~500ms total.
        _ = detector.frame(fingers: 1, at: 0)
        _ = detector.frame(fingers: 2, at: 0.2)
        _ = detector.frame(fingers: 3, at: 0.4)
        _ = detector.frame(fingers: 3, at: 0.45)
        XCTAssertTrue(detector.frame(fingers: 0, at: 0.5))
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

    func testLongHoldIgnored() {
        _ = detector.frame(fingers: 3, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, at: 1.0), "holds are too long")
    }

    func testTooShortBlipIgnored() {
        _ = detector.frame(fingers: 3, at: 0)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.02), "sub-60ms contact is noise")
    }

    func testLateThirdFingerIgnored() {
        _ = detector.frame(fingers: 2, at: 0)
        _ = detector.frame(fingers: 3, at: 0.65)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.7), "third finger joined too late")
    }

    func testSecondTapWorksAfterFirst() {
        _ = detector.frame(fingers: 3, at: 0)
        XCTAssertTrue(detector.frame(fingers: 0, at: 0.1))
        _ = detector.frame(fingers: 3, at: 1.0)
        XCTAssertTrue(detector.frame(fingers: 0, at: 1.1))
    }
}

final class ThreeFingerDoubleTapDetectorTests: XCTestCase {
    private var detector = ThreeFingerDoubleTapDetector()

    private func tap(from start: TimeInterval, duration: TimeInterval = 0.1) -> Bool {
        _ = detector.frame(fingers: 3, at: start)
        return detector.frame(fingers: 0, at: start + duration)
    }

    func testTwoQuickTapsFire() {
        XCTAssertFalse(tap(from: 0))
        XCTAssertTrue(tap(from: 0.25), "second tap within the gap fires")
    }

    func testRealisticUnhurriedPairFires() {
        // Live logs: ~450ms taps, 600–900ms end to end between them.
        XCTAssertFalse(tap(from: 0, duration: 0.45))
        XCTAssertTrue(tap(from: 0.85, duration: 0.45))
    }

    func testSingleTapDoesNotFire() {
        XCTAssertFalse(tap(from: 0))
    }

    func testSlowPairDoesNotFire() {
        XCTAssertFalse(tap(from: 0))
        XCTAssertFalse(tap(from: 1.5), "gap exceeded: taps are independent")
    }

    func testSlowPairSecondTapStartsANewPair() {
        _ = tap(from: 0)
        _ = tap(from: 1.5)
        XCTAssertTrue(tap(from: 2.0), "late tap becomes the first of the next pair")
    }

    func testThirdTapAfterAPairStartsFresh() {
        _ = tap(from: 0)
        XCTAssertTrue(tap(from: 0.25))
        XCTAssertFalse(tap(from: 0.5), "pair consumed; a lone follow-up tap does not fire")
        XCTAssertTrue(tap(from: 0.75), "…but it seeds the next pair")
    }

    func testScrollBetweenTapsDoesNotPair() {
        XCTAssertFalse(tap(from: 0))
        // A two-finger scroll: not a tap, and it must break the pairing
        // window instead of leaving it open.
        _ = detector.frame(fingers: 2, at: 0.15)
        _ = detector.frame(fingers: 2, at: 0.25)
        _ = detector.frame(fingers: 0, at: 0.3)
        XCTAssertFalse(tap(from: 0.35), "the scroll broke the pair")
    }

    func testLoneScrollStrayCandidateDoesNotFire() {
        // A two-finger scroll a stray finger joined can slip past the
        // single-tap detector; without a twin within the gap it stays quiet.
        _ = detector.frame(fingers: 2, at: 0)
        _ = detector.frame(fingers: 3, at: 0.3)
        XCTAssertFalse(detector.frame(fingers: 0, at: 0.5))
    }
}
