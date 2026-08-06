import Foundation

struct ThreeFingerTouchVector: Equatable {
    let x: Double
    let y: Double

    var magnitude: Double { hypot(x, y) }
}

enum ThreeFingerTouchState: Int, Equatable {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7
}

struct ThreeFingerTouchContact: Equatable {
    let fingerID: Int
    let state: ThreeFingerTouchState
    let position: ThreeFingerTouchVector
    let velocity: ThreeFingerTouchVector

    var hasValidGeometry: Bool {
        position.x.isFinite && position.y.isFinite
            && velocity.x.isFinite && velocity.y.isFinite
            && (0...1).contains(position.x) && (0...1).contains(position.y)
    }
}

struct ThreeFingerTouchFrame: Equatable {
    let fingers: Int
    /// nil means the private touch record could not be decoded safely.
    let contacts: [ThreeFingerTouchContact]?
    let time: TimeInterval
}

/// Pure state machine behind the system trackpad monitor. A geometrically
/// valid double tap enters `pastePending`; the caller must wait through the
/// late-swipe guard window before asking the machine to approve the paste.
/// Any swipe evidence enters a lock which ignores every contact transition
/// until the pad has stayed empty for the release interval.
struct SwipeLockedThreeFingerDoubleTapDetector {
    enum Phase: Equatable {
        case idle
        case firstTap
        case pastePending
        case swipeSuppressed
    }

    enum SuppressionReason: String, Equatable {
        case movement
        case appKitSwipe
        case activeSpaceChanged
        case frontmostAppChanged
    }

    enum CancellationReason: String, Equatable {
        case invalidTouchData
        case insufficientTouchData
        case wrongFingerCount
        case tooShort
        case tooLong
        case lateLanding
        case contactSetChanged
        case contactReturned
        case pairExpired
        case focusChanged
        case modeChanged
        case touchDuringPasteGuard
    }

    enum SessionOutcome: String, Equatable {
        case firstTap
        case secondTap
        case invalidTouchData
        case insufficientTouchData
        case wrongFingerCount
        case tooShort
        case tooLong
        case lateLanding
        case contactSetChanged
        case contactReturned
        case movement
        case appKitSwipe
        case activeSpaceChanged
        case frontmostAppChanged
        case focusChanged
        case modeChanged
        case touchDuringPasteGuard
        case pairExpired
    }

    struct SessionMetrics: Equatable {
        let duration: TimeInterval
        let landingDelay: TimeInterval?
        let stableFrames: Int
        let maxTransfer: Double
        let maxVelocity: Double
        let outcome: SessionOutcome
    }

    enum Action: Equatable {
        case firstSessionStarted
        case pastePending
        case pasteApproved
        case sequenceInvalidated(CancellationReason)
        case swipeSuppressed(SuppressionReason)
        case suppressionEnded
        case sessionMetrics(SessionMetrics)
    }

    var minDuration: TimeInterval = 0.04
    var maxDuration: TimeInterval = 0.75
    var maxLandingDelay: TimeInterval = 0.6
    var maxGap: TimeInterval = 1.0
    var pasteGuardInterval: TimeInterval = 0.15
    var suppressionReleaseInterval: TimeInterval = 0.25
    /// Normalized trackpad distance. Calibration may lower it, but never
    /// raises it above 0.08.
    var movementLimit: Double = 0.08
    var minimumStableFrames = 2

    private(set) var phase: Phase = .idle

    private struct Session {
        let start: TimeInterval
        var maxFingers = 0
        var reachedThreeAt: TimeInterval?
        var stableFrames = 0
        var baseline: [Int: ThreeFingerTouchVector]?
        var maxTransfer = 0.0
        var maxVelocity = 0.0
        var invalidReason: CancellationReason?
    }

    private var session: Session?
    private var firstTapEnd: TimeInterval?
    private var pastePendingAt: TimeInterval?
    private var lastFingers = 0
    private var suppressionZeroSince: TimeInterval?
    private var lastSuppressionSignal: TimeInterval?
    private var discardUntilZero = false

    mutating func frame(_ frame: ThreeFingerTouchFrame) -> [Action] {
        let fingers = max(0, frame.fingers)
        let previousFingers = lastFingers
        lastFingers = fingers

        if phase == .swipeSuppressed {
            if fingers == 0 {
                if previousFingers > 0 || suppressionZeroSince == nil {
                    suppressionZeroSince = frame.time
                }
            } else {
                suppressionZeroSince = nil
            }
            return []
        }

        if discardUntilZero {
            if fingers == 0 { discardUntilZero = false }
            return []
        }

        if fingers > 0 {
            var actions: [Action] = []
            if session == nil {
                if phase == .pastePending {
                    phase = .idle
                    pastePendingAt = nil
                    actions.append(.sequenceInvalidated(.touchDuringPasteGuard))
                }
                if phase == .firstTap,
                   let firstTapEnd,
                   frame.time - firstTapEnd > maxGap {
                    phase = .idle
                    self.firstTapEnd = nil
                    actions.append(.sequenceInvalidated(.pairExpired))
                }
                session = Session(start: frame.time)
                if phase == .idle {
                    actions.append(.firstSessionStarted)
                }
            }

            guard var active = session else { return actions }
            let hadReachedThree = active.reachedThreeAt != nil
            active.maxFingers = max(active.maxFingers, fingers)
            if fingers == 3, active.reachedThreeAt == nil {
                active.reachedThreeAt = frame.time
            }
            if hadReachedThree, previousFingers > 0, previousFingers < 3, fingers == 3 {
                active.invalidReason = active.invalidReason ?? .contactReturned
            }

            guard let contacts = frame.contacts,
                  contacts.count == fingers
            else {
                active.invalidReason = active.invalidReason ?? .invalidTouchData
                session = active
                return actions
            }

            if fingers == 3 {
                let stable = contacts.filter { $0.state == .touching }
                if stable.count == 3 {
                    guard Set(stable.map(\.fingerID)).count == 3,
                          stable.allSatisfy(\.hasValidGeometry)
                    else {
                        active.invalidReason = active.invalidReason ?? .invalidTouchData
                        session = active
                        return actions
                    }
                    let current = Dictionary(uniqueKeysWithValues: stable.map { ($0.fingerID, $0.position) })
                    if let baseline = active.baseline {
                        if baseline.keys.sorted() != current.keys.sorted() {
                            active.invalidReason = active.invalidReason ?? .contactSetChanged
                        } else {
                            active.stableFrames += 1
                            let displacements = current.compactMap { fingerID, point -> ThreeFingerTouchVector? in
                                guard let origin = baseline[fingerID] else { return nil }
                                return ThreeFingerTouchVector(
                                    x: point.x - origin.x,
                                    y: point.y - origin.y
                                )
                            }
                            let medianVector = ThreeFingerTouchVector(
                                x: Self.median(displacements.map(\.x)),
                                y: Self.median(displacements.map(\.y))
                            )
                            let transfer = medianVector.magnitude
                            active.maxTransfer = max(active.maxTransfer, transfer)
                            let medianSquared = transfer * transfer
                            let coherent = displacements.allSatisfy {
                                $0.x * medianVector.x + $0.y * medianVector.y
                                    >= -medianSquared * 0.1
                            }
                            if coherent, transfer > movementLimit {
                                session = active
                                actions.append(contentsOf: suppress(reason: .movement, at: frame.time))
                                return actions
                            }
                        }
                    } else {
                        active.baseline = current
                        active.stableFrames = 1
                    }
                    let medianVelocity = Self.median(stable.map { $0.velocity.magnitude })
                    active.maxVelocity = max(active.maxVelocity, medianVelocity)
                }
            }
            session = active
            return actions
        }

        guard let completed = session else { return [] }
        session = nil
        return finish(completed, at: frame.time)
    }

    /// AppKit `.swipe`, Space switches, and application switches all use
    /// the same lock. Repeated signals reset the zero-touch quiet period.
    mutating func suppress(reason: SuppressionReason, at time: TimeInterval) -> [Action] {
        var actions: [Action] = []
        if let active = session {
            actions.append(.sessionMetrics(metrics(
                for: active,
                at: time,
                outcome: Self.outcome(for: reason)
            )))
        }
        session = nil
        firstTapEnd = nil
        pastePendingAt = nil
        discardUntilZero = false
        phase = .swipeSuppressed
        lastSuppressionSignal = time
        suppressionZeroSince = lastFingers == 0 ? time : nil
        actions.append(.swipeSuppressed(reason))
        return actions
    }

    /// A focus or mode change invalidates a tap pair without manufacturing a
    /// swipe. If fingers are still down, their remaining frames are discarded.
    mutating func invalidate(reason: CancellationReason, at time: TimeInterval) -> [Action] {
        if phase == .swipeSuppressed {
            return [.sequenceInvalidated(reason)]
        }
        var actions: [Action] = []
        if let active = session {
            actions.append(.sessionMetrics(metrics(
                for: active,
                at: time,
                outcome: Self.outcome(for: reason)
            )))
        }
        session = nil
        firstTapEnd = nil
        pastePendingAt = nil
        phase = .idle
        discardUntilZero = lastFingers > 0
        actions.append(.sequenceInvalidated(reason))
        return actions
    }

    mutating func expireFirstTap(at time: TimeInterval) -> [Action] {
        guard phase == .firstTap,
              let firstTapEnd,
              time - firstTapEnd >= maxGap
        else { return [] }
        phase = .idle
        self.firstTapEnd = nil
        return [.sequenceInvalidated(.pairExpired)]
    }

    mutating func approvePendingPaste(at time: TimeInterval) -> [Action] {
        guard phase == .pastePending,
              let pastePendingAt,
              time - pastePendingAt >= pasteGuardInterval
        else { return [] }
        phase = .idle
        self.pastePendingAt = nil
        return [.pasteApproved]
    }

    mutating func releaseSuppressionIfReady(at time: TimeInterval) -> [Action] {
        guard phase == .swipeSuppressed,
              lastFingers == 0,
              let suppressionZeroSince,
              let lastSuppressionSignal,
              time - suppressionZeroSince >= suppressionReleaseInterval,
              time - lastSuppressionSignal >= suppressionReleaseInterval
        else { return [] }
        phase = .idle
        self.suppressionZeroSince = nil
        self.lastSuppressionSignal = nil
        return [.suppressionEnded]
    }

    private mutating func finish(_ completed: Session, at time: TimeInterval) -> [Action] {
        let duration = time - completed.start
        let invalid: CancellationReason?
        if let reason = completed.invalidReason {
            invalid = reason
        } else if completed.maxFingers != 3 {
            invalid = .wrongFingerCount
        } else if duration < minDuration {
            invalid = .tooShort
        } else if duration > maxDuration {
            invalid = .tooLong
        } else if let reached = completed.reachedThreeAt,
                  reached - completed.start > maxLandingDelay {
            invalid = .lateLanding
        } else if completed.reachedThreeAt == nil || completed.stableFrames < minimumStableFrames {
            invalid = .insufficientTouchData
        } else {
            invalid = nil
        }

        if let invalid {
            phase = .idle
            firstTapEnd = nil
            pastePendingAt = nil
            return [
                .sessionMetrics(metrics(for: completed, at: time, outcome: Self.outcome(for: invalid))),
                .sequenceInvalidated(invalid),
            ]
        }

        if phase == .idle {
            phase = .firstTap
            firstTapEnd = time
            return [.sessionMetrics(metrics(for: completed, at: time, outcome: .firstTap))]
        }

        guard phase == .firstTap,
              let firstTapEnd,
              time - firstTapEnd <= maxGap
        else {
            phase = .idle
            self.firstTapEnd = nil
            return [
                .sessionMetrics(metrics(for: completed, at: time, outcome: .secondTap)),
                .sequenceInvalidated(.pairExpired),
            ]
        }

        phase = .pastePending
        self.firstTapEnd = nil
        pastePendingAt = time
        return [
            .sessionMetrics(metrics(for: completed, at: time, outcome: .secondTap)),
            .pastePending,
        ]
    }

    private func metrics(
        for session: Session,
        at time: TimeInterval,
        outcome: SessionOutcome
    ) -> SessionMetrics {
        SessionMetrics(
            duration: max(0, time - session.start),
            landingDelay: session.reachedThreeAt.map { max(0, $0 - session.start) },
            stableFrames: session.stableFrames,
            maxTransfer: session.maxTransfer,
            maxVelocity: session.maxVelocity,
            outcome: outcome
        )
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func outcome(for reason: SuppressionReason) -> SessionOutcome {
        switch reason {
        case .movement: return .movement
        case .appKitSwipe: return .appKitSwipe
        case .activeSpaceChanged: return .activeSpaceChanged
        case .frontmostAppChanged: return .frontmostAppChanged
        }
    }

    private static func outcome(for reason: CancellationReason) -> SessionOutcome {
        switch reason {
        case .invalidTouchData: return .invalidTouchData
        case .insufficientTouchData: return .insufficientTouchData
        case .wrongFingerCount: return .wrongFingerCount
        case .tooShort: return .tooShort
        case .tooLong: return .tooLong
        case .lateLanding: return .lateLanding
        case .contactSetChanged: return .contactSetChanged
        case .contactReturned: return .contactReturned
        case .focusChanged: return .focusChanged
        case .modeChanged: return .modeChanged
        case .touchDuringPasteGuard: return .touchDuringPasteGuard
        case .pairExpired: return .pairExpired
        }
    }
}

enum ThreeFingerGestureCalibration {
    /// Applies the field-test acceptance rule. A dataset which does not
    /// cleanly separate taps from swipes deliberately yields no threshold.
    static func movementLimit(
        tapMovements: [Double],
        horizontalSwipeMovements: [Double],
        verticalSwipeMovements: [Double]
    ) -> Double? {
        guard tapMovements.count >= 15,
              horizontalSwipeMovements.count >= 20,
              verticalSwipeMovements.count >= 10
        else { return nil }
        let all = tapMovements + horizontalSwipeMovements + verticalSwipeMovements
        guard all.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let maxTap = tapMovements.max(),
              maxTap > 0,
              let minSwipe = (horizontalSwipeMovements + verticalSwipeMovements).min()
        else { return nil }
        let limit = min(0.08, maxTap * 1.25)
        return minSwipe >= limit * 2 ? limit : nil
    }
}
