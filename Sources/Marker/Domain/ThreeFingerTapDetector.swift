import Foundation

/// Detects a three-finger tap from a stream of touch frames, by count and
/// timing alone: a session whose maximum simultaneous finger count is
/// exactly three, short enough to be a tap, whose third finger landed
/// reasonably soon. No position data — fingertips are free to wobble or
/// drift. On its own this also matches a quick three-finger swipe; the
/// double-tap requirement on top (plus pasting only over editable text)
/// is what makes it safe as a trigger.
struct ThreeFingerTapDetector {
    var minDuration: TimeInterval = 0.04
    var maxDuration: TimeInterval = 0.75
    /// The third finger must land within this window of the first touch;
    /// a scroll that a stray finger joins mid-gesture arrives much later.
    var maxLandingDelay: TimeInterval = 0.6

    private var sessionStart: TimeInterval?
    private var maxFingers = 0
    private var reachedThreeAt: TimeInterval?

    /// Feed one touch frame; returns true when a three-finger tap completed.
    mutating func frame(fingers: Int, at time: TimeInterval) -> Bool {
        if fingers > 0 {
            if sessionStart == nil {
                sessionStart = time
                maxFingers = 0
                reachedThreeAt = nil
            }
            maxFingers = max(maxFingers, fingers)
            if fingers == 3, reachedThreeAt == nil {
                reachedThreeAt = time
            }
            return false
        }
        guard let start = sessionStart else { return false }
        sessionStart = nil
        let duration = time - start
        guard let landed = reachedThreeAt else { return false }
        return maxFingers == 3
            && duration >= minDuration
            && duration <= maxDuration
            && landed - start <= maxLandingDelay
    }
}

/// Two three-finger taps in quick succession. The double requirement is
/// what makes the permissive tap safe as a paste trigger: an accidental
/// touch would have to repeat itself within the gap window, with nothing
/// else in between.
struct ThreeFingerDoubleTapDetector {
    var single = ThreeFingerTapDetector()
    /// Max time from the end of the first tap to the end of the second
    /// (so it spans the pause plus the second tap itself). Real unhurried
    /// double taps measure 600–900ms end to end.
    var maxGap: TimeInterval = 1.0

    private var lastTapEnd: TimeInterval?
    private var previousFingers = 0

    /// Feed one touch frame; returns true when the second tap of a pair
    /// completed.
    mutating func frame(fingers: Int, at time: TimeInterval) -> Bool {
        let tapped = single.frame(fingers: fingers, at: time)
        let sessionEnded = previousFingers > 0 && fingers == 0
        previousFingers = fingers
        guard tapped else {
            // A session that ended without being a tap (scroll, hold,
            // four fingers) breaks the pair — a real double tap has
            // nothing in between.
            if sessionEnded { lastTapEnd = nil }
            return false
        }
        if let previous = lastTapEnd, time - previous <= maxGap {
            lastTapEnd = nil
            return true
        }
        lastTapEnd = time
        return false
    }
}
