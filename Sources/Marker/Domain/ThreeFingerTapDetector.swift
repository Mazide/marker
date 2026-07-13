import Foundation

/// Detects a three-finger tap from a stream of touch-frame finger counts.
/// A tap = a touch session whose maximum simultaneous finger count is
/// exactly three and whose duration sits in the tap window — long enough
/// to be deliberate, short enough to reject three-finger swipes
/// (Mission Control) and holds.
struct ThreeFingerTapDetector {
    var minDuration: TimeInterval = 0.06
    var maxDuration: TimeInterval = 0.22

    private var sessionStart: TimeInterval?
    private var maxFingers = 0

    /// Feed one touch frame; returns true when a three-finger tap completed.
    mutating func frame(fingers: Int, at time: TimeInterval) -> Bool {
        if fingers > 0 {
            if sessionStart == nil {
                sessionStart = time
                maxFingers = 0
            }
            maxFingers = max(maxFingers, fingers)
            return false
        }
        guard let start = sessionStart else { return false }
        sessionStart = nil
        let duration = time - start
        return maxFingers == 3
            && duration >= minDuration
            && duration <= maxDuration
    }
}