import XCTest
@testable import Marker

final class SwipeLockedThreeFingerDoubleTapDetectorTests: XCTestCase {
    private var detector = SwipeLockedThreeFingerDoubleTapDetector()

    private func contacts(
        _ ids: [Int] = [11, 22, 33],
        state: ThreeFingerTouchState = .touching,
        dx: Double = 0,
        dy: Double = 0,
        velocity: Double = 0.01
    ) -> [ThreeFingerTouchContact] {
        zip(ids, [(0.2, 0.3), (0.5, 0.4), (0.8, 0.6)]).map { id, origin in
            ThreeFingerTouchContact(
                fingerID: id,
                state: state,
                position: ThreeFingerTouchVector(x: origin.0 + dx, y: origin.1 + dy),
                velocity: ThreeFingerTouchVector(x: velocity, y: 0)
            )
        }
    }

    @discardableResult
    private func send(
        _ fingers: Int,
        _ time: TimeInterval,
        contacts supplied: [ThreeFingerTouchContact]? = nil
    ) -> [SwipeLockedThreeFingerDoubleTapDetector.Action] {
        detector.frame(ThreeFingerTouchFrame(
            fingers: fingers,
            contacts: supplied ?? (fingers == 0 ? [] : contacts(Array([11, 22, 33].prefix(fingers)))),
            time: time
        ))
    }

    @discardableResult
    private func tap(from start: TimeInterval, dx: Double = 0.003) -> [SwipeLockedThreeFingerDoubleTapDetector.Action] {
        _ = send(3, start, contacts: contacts())
        _ = send(3, start + 0.05, contacts: contacts(dx: dx))
        return send(0, start + 0.1)
    }

    func testValidPairWaitsThroughLateSwipeGuardBeforeApproval() {
        let first = tap(from: 0)
        guard case .sessionMetrics(let metrics) = first.last else {
            return XCTFail("a valid first tap must emit aggregate metrics")
        }
        XCTAssertEqual(metrics.outcome, .firstTap)
        XCTAssertEqual(metrics.stableFrames, 2)
        XCTAssertEqual(metrics.maxTransfer, 0.003, accuracy: 0.000_001)
        let second = tap(from: 0.3)
        XCTAssertTrue(second.contains(.pastePending))
        XCTAssertEqual(detector.phase, .pastePending)
        XCTAssertTrue(detector.approvePendingPaste(at: 0.549).isEmpty)
        XCTAssertEqual(detector.approvePendingPaste(at: 0.551), [.pasteApproved])
        XCTAssertEqual(detector.phase, .idle)
    }

    func testSwipeMovementLocksThreeTwoThreeSequenceUntilContinuousZero() {
        _ = send(3, 0, contacts: contacts())
        let moved = send(3, 0.05, contacts: contacts(dx: 0.09, velocity: 1.2))
        XCTAssertTrue(moved.contains(.swipeSuppressed(.movement)))
        XCTAssertEqual(detector.phase, .swipeSuppressed)

        _ = send(2, 0.08, contacts: contacts([11, 22], dx: 0.1))
        _ = send(3, 0.11, contacts: contacts(dx: 0.12))
        _ = send(0, 0.15)
        XCTAssertTrue(detector.releaseSuppressionIfReady(at: 0.399).isEmpty)
        XCTAssertEqual(
            detector.releaseSuppressionIfReady(at: 0.401),
            [.suppressionEnded]
        )
        XCTAssertEqual(detector.phase, .idle)
    }

    func testTwoSwipesSeparatedByShortAirGapRemainOneSuppressedSequence() {
        _ = detector.suppress(reason: .appKitSwipe, at: 0)
        _ = send(0, 0.02)
        XCTAssertTrue(detector.releaseSuppressionIfReady(at: 0.2).isEmpty)

        _ = detector.suppress(reason: .appKitSwipe, at: 0.21)
        XCTAssertTrue(detector.releaseSuppressionIfReady(at: 0.45).isEmpty)
        XCTAssertEqual(detector.phase, .swipeSuppressed)
        XCTAssertEqual(detector.releaseSuppressionIfReady(at: 0.461), [.suppressionEnded])
    }

    func testDoubleTapWorksOnlyAfterSuppressionFullyEnds() {
        _ = detector.suppress(reason: .activeSpaceChanged, at: 0)
        _ = send(0, 0.01)

        // These tap-like transitions are discarded while locked.
        _ = tap(from: 0.05)
        _ = tap(from: 0.2)
        XCTAssertEqual(detector.phase, .swipeSuppressed)

        // The last zero transition was at 0.30, so release is after 0.55.
        XCTAssertEqual(detector.releaseSuppressionIfReady(at: 0.551), [.suppressionEnded])
        _ = tap(from: 0.7)
        XCTAssertTrue(tap(from: 1.0).contains(.pastePending))
    }

    func testSwipeCancelsFirstTap() {
        _ = tap(from: 0)
        XCTAssertEqual(detector.phase, .firstTap)
        let actions = detector.suppress(reason: .frontmostAppChanged, at: 0.15)
        XCTAssertTrue(actions.contains(.swipeSuppressed(.frontmostAppChanged)))
        _ = send(0, 0.16)
        _ = detector.releaseSuppressionIfReady(at: 0.411)

        XCTAssertFalse(tap(from: 0.5).contains(.pastePending))
        XCTAssertEqual(detector.phase, .firstTap)
    }

    func testLateAppKitSwipeCancelsPastePending() {
        _ = tap(from: 0)
        _ = tap(from: 0.3)
        XCTAssertEqual(detector.phase, .pastePending)

        let actions = detector.suppress(reason: .appKitSwipe, at: 0.49)
        XCTAssertTrue(actions.contains(.swipeSuppressed(.appKitSwipe)))
        XCTAssertTrue(detector.approvePendingPaste(at: 1).isEmpty)
    }

    func testSpaceAndApplicationSignalsBothSuppress() {
        _ = tap(from: 0)
        XCTAssertTrue(detector.suppress(reason: .activeSpaceChanged, at: 0.12)
            .contains(.swipeSuppressed(.activeSpaceChanged)))
        _ = send(0, 0.13)
        _ = detector.releaseSuppressionIfReady(at: 0.381)

        _ = tap(from: 0.5)
        XCTAssertTrue(detector.suppress(reason: .frontmostAppChanged, at: 0.62)
            .contains(.swipeSuppressed(.frontmostAppChanged)))
    }

    func testFocusChangeCancelsFirstTapAndPastePending() {
        _ = tap(from: 0)
        XCTAssertTrue(detector.invalidate(reason: .focusChanged, at: 0.12)
            .contains(.sequenceInvalidated(.focusChanged)))
        XCTAssertEqual(detector.phase, .idle)

        _ = tap(from: 0.3)
        _ = tap(from: 0.6)
        XCTAssertEqual(detector.phase, .pastePending)
        _ = detector.invalidate(reason: .focusChanged, at: 0.71)
        XCTAssertTrue(detector.approvePendingPaste(at: 1).isEmpty)
    }

    func testSuppressionReleasesWithoutSystemEndedEvent() {
        _ = detector.suppress(reason: .appKitSwipe, at: 0)
        _ = send(0, 0.05)
        XCTAssertTrue(detector.releaseSuppressionIfReady(at: 0.249).isEmpty)
        XCTAssertEqual(detector.releaseSuppressionIfReady(at: 0.251), [.suppressionEnded])
    }

    func testLandingAndLiftFramesDoNotCountAsMovement() {
        _ = send(1, 0, contacts: contacts([11], state: .makeTouch))
        _ = send(2, 0.1, contacts: contacts([11, 22], state: .makeTouch, dx: 0.2))
        // IDs are not stable while contacts land or lift; these frames must
        // not poison an otherwise valid tap.
        let landing = contacts(state: .makeTouch, dx: -0.1).map {
            ThreeFingerTouchContact(
                fingerID: 0,
                state: $0.state,
                position: $0.position,
                velocity: $0.velocity
            )
        }
        _ = send(3, 0.2, contacts: landing)
        _ = send(3, 0.25, contacts: contacts())
        _ = send(3, 0.3, contacts: contacts(dx: 0.002))
        let lifting = contacts([11, 22], state: .breakTouch, dx: 0.3).map {
            ThreeFingerTouchContact(
                fingerID: 0,
                state: $0.state,
                position: $0.position,
                velocity: $0.velocity
            )
        }
        _ = send(2, 0.35, contacts: lifting)
        let actions = send(0, 0.4)
        XCTAssertEqual(detector.phase, .firstTap)
        XCTAssertFalse(actions.contains { action in
            if case .swipeSuppressed = action { return true }
            return false
        })
    }

    func testInsufficientOrMalformedTouchDataNeverSeedsTap() {
        let invalid = detector.frame(ThreeFingerTouchFrame(fingers: 3, contacts: nil, time: 0))
        XCTAssertEqual(invalid, [.firstSessionStarted])
        let end = send(0, 0.1)
        XCTAssertTrue(end.contains(.sequenceInvalidated(.invalidTouchData)))
        XCTAssertEqual(detector.phase, .idle)

        _ = send(3, 0.2, contacts: contacts(state: .makeTouch))
        _ = send(3, 0.25, contacts: contacts(state: .breakTouch))
        let insufficient = send(0, 0.3)
        XCTAssertTrue(insufficient.contains(.sequenceInvalidated(.insufficientTouchData)))
    }

    func testContactReturnInvalidatesSession() {
        _ = send(3, 0, contacts: contacts())
        _ = send(2, 0.03, contacts: contacts([11, 22], state: .breakTouch))
        _ = send(3, 0.06, contacts: contacts())
        let actions = send(0, 0.1)
        XCTAssertTrue(actions.contains(.sequenceInvalidated(.contactReturned)))
        XCTAssertEqual(detector.phase, .idle)
    }
}

final class ThreeFingerGestureCalibrationTests: XCTestCase {
    func testSeparatedDatasetProducesCappedTapLimit() {
        let limit = ThreeFingerGestureCalibration.movementLimit(
            tapMovements: Array(repeating: 0.02, count: 15),
            horizontalSwipeMovements: Array(repeating: 0.08, count: 20),
            verticalSwipeMovements: Array(repeating: 0.09, count: 10)
        )
        XCTAssertNotNil(limit)
        XCTAssertEqual(limit ?? 0, 0.025, accuracy: 0.000_001)
    }

    func testOverlappingOrIncompleteDatasetIsRejected() {
        XCTAssertNil(ThreeFingerGestureCalibration.movementLimit(
            tapMovements: Array(repeating: 0.04, count: 15),
            horizontalSwipeMovements: Array(repeating: 0.09, count: 20),
            verticalSwipeMovements: Array(repeating: 0.11, count: 10)
        ))
        XCTAssertNil(ThreeFingerGestureCalibration.movementLimit(
            tapMovements: Array(repeating: 0.01, count: 14),
            horizontalSwipeMovements: Array(repeating: 0.1, count: 20),
            verticalSwipeMovements: Array(repeating: 0.1, count: 10)
        ))
    }
}
