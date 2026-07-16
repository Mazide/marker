import Foundation

/// Detects a three-finger tap from a stream of touch frames.
/// A tap = a session whose maximum simultaneous finger count is exactly
/// three, short enough to be a tap, whose three fingers landed together,
/// and whose fingers barely moved at any point — movement is what
/// separates a relaxed tap from a swipe or a two-finger scroll that a
/// stray third finger grazed, so the duration window can stay generous.
struct ThreeFingerTapDetector {
    var minDuration: TimeInterval = 0.04
    var maxDuration: TimeInterval = 0.75
    /// Max centroid drift in normalized trackpad units (0…1 per axis).
    var maxMovement: Float = 0.04
    /// The third finger must land within this window of the first touch;
    /// a scroll that a stray finger joins mid-gesture arrives much later.
    var maxLandingDelay: TimeInterval = 0.15

    private var sessionStart: TimeInterval?
    private var maxFingers = 0
    private var reachedThreeAt: TimeInterval?
    private var segmentFingers = 0
    private var segmentStartCentroid: (x: Float, y: Float)?
    private var maxDeviation: Float = 0

    /// Feed one touch frame; returns true when a three-finger tap completed.
    /// `centroid` may be nil when positions are unavailable — the detector
    /// then falls back to count+duration only.
    mutating func frame(fingers: Int, centroid: (x: Float, y: Float)?, at time: TimeInterval) -> Bool {
        if fingers > 0 {
            if sessionStart == nil {
                sessionStart = time
                maxFingers = 0
                reachedThreeAt = nil
                segmentFingers = 0
                segmentStartCentroid = nil
                maxDeviation = 0
            }
            maxFingers = max(maxFingers, fingers)
            if fingers >= 3, reachedThreeAt == nil {
                reachedThreeAt = time
            }
            // Movement is tracked per constant-finger-count segment: the
            // centroid jumps when a finger lands or lifts, so comparing
            // across a count change would read as fake movement.
            if fingers != segmentFingers {
                segmentFingers = fingers
                segmentStartCentroid = centroid
            } else if let centroid {
                if let start = segmentStartCentroid {
                    let dx = centroid.x - start.x
                    let dy = centroid.y - start.y
                    maxDeviation = max(maxDeviation, (dx * dx + dy * dy).squareRoot())
                } else {
                    segmentStartCentroid = centroid
                }
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
            && maxDeviation <= maxMovement
    }
}

/// Two three-finger taps in quick succession. The double requirement is
/// what makes a light tap safe as a paste trigger: every accidental-touch
/// scenario would have to repeat itself within the gap window.
struct ThreeFingerDoubleTapDetector {
    var single = ThreeFingerTapDetector()
    /// Max time from the end of the first tap to the end of the second
    /// (so it spans the pause plus the second tap itself).
    var maxGap: TimeInterval = 0.5

    private var lastTapEnd: TimeInterval?
    private var previousFingers = 0

    /// Feed one touch frame; returns true when the second tap of a pair
    /// completed.
    mutating func frame(fingers: Int, centroid: (x: Float, y: Float)?, at time: TimeInterval) -> Bool {
        let tapped = single.frame(fingers: fingers, centroid: centroid, at: time)
        let sessionEnded = previousFingers > 0 && fingers == 0
        previousFingers = fingers
        guard tapped else {
            // A session that ended without being a tap (swipe, scroll,
            // hold) breaks the pair — a real double tap has nothing in
            // between.
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
