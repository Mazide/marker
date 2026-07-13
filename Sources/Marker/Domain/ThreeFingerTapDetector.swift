import Foundation

/// Detects a three-finger tap from a stream of touch frames.
/// A tap = a session whose maximum simultaneous finger count is exactly
/// three, short enough to be a tap, and whose fingers barely moved —
/// movement is what separates a relaxed tap from a three-finger swipe
/// (Mission Control), so the duration window can stay generous.
struct ThreeFingerTapDetector {
    var minDuration: TimeInterval = 0.04
    var maxDuration: TimeInterval = 0.75
    /// Max centroid drift in normalized trackpad units (0…1 per axis).
    var maxMovement: Float = 0.04

    private var sessionStart: TimeInterval?
    private var maxFingers = 0
    private var startCentroid: (x: Float, y: Float)?
    private var maxDeviation: Float = 0

    /// Feed one touch frame; returns true when a three-finger tap completed.
    /// `centroid` may be nil when positions are unavailable — the detector
    /// then falls back to count+duration only.
    mutating func frame(fingers: Int, centroid: (x: Float, y: Float)?, at time: TimeInterval) -> Bool {
        if fingers > 0 {
            if sessionStart == nil {
                sessionStart = time
                maxFingers = 0
                startCentroid = nil
                maxDeviation = 0
            }
            maxFingers = max(maxFingers, fingers)
            if fingers == 3, let centroid {
                if let start = startCentroid {
                    let dx = centroid.x - start.x
                    let dy = centroid.y - start.y
                    maxDeviation = max(maxDeviation, (dx * dx + dy * dy).squareRoot())
                } else {
                    startCentroid = centroid
                }
            }
            return false
        }
        guard let start = sessionStart else { return false }
        sessionStart = nil
        let duration = time - start
        return maxFingers == 3
            && duration >= minDuration
            && duration <= maxDuration
            && maxDeviation <= maxMovement
    }
}