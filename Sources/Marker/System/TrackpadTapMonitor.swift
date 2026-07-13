import AppKit

/// Three-finger-tap detection via the private MultitouchSupport framework
/// (the same mechanism apps like Middle use). Loaded with dlopen/dlsym so
/// nothing links against the private framework at build time; if the
/// framework or symbols are missing the monitor silently does nothing.
/// Only the per-frame finger COUNT is read — touch struct layouts vary
/// between macOS versions, so we never parse them.
final class TrackpadTapMonitor {
    var onThreeFingerTap: (() -> Void)?

    private typealias MTDeviceCreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias MTRegisterContactFrameCallback = @convention(c) (
        UnsafeMutableRawPointer?, MTContactCallback?
    ) -> Void
    private typealias MTDeviceStart = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

    // The C callback has no refcon; a single shared instance receives frames.
    nonisolated(unsafe) static var shared: TrackpadTapMonitor?

    private var detector = ThreeFingerTapDetector()
    private var devices: CFArray?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Self.shared = self

        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        ),
            let createListSym = dlsym(handle, "MTDeviceCreateList"),
            let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
            let startSym = dlsym(handle, "MTDeviceStart")
        else {
            markerLog.error("MultitouchSupport unavailable; three-finger tap disabled")
            return
        }

        let createList = unsafeBitCast(createListSym, to: MTDeviceCreateList.self)
        let register = unsafeBitCast(registerSym, to: MTRegisterContactFrameCallback.self)
        let deviceStart = unsafeBitCast(startSym, to: MTDeviceStart.self)

        guard let list = createList()?.takeRetainedValue() else {
            markerLog.error("MTDeviceCreateList returned nothing")
            return
        }
        devices = list

        let callback: MTContactCallback = { _, touches, fingers, timestamp, _ in
            let centroid = TrackpadTapMonitor.centroid(of: touches, count: Int(fingers))
            TrackpadTapMonitor.shared?.frame(fingers: Int(fingers), centroid: centroid, at: timestamp)
            return 0
        }

        for index in 0..<CFArrayGetCount(list) {
            let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, index))
            register(device, callback)
            deviceStart(device, 0)
        }
        markerLog.info("trackpad tap monitor started (\(CFArrayGetCount(list)) devices)")
    }

    /// Normalized finger centroid from the classic 96-byte MTTouch layout
    /// (position floats at offsets 32/36). If Apple ever changes the layout
    /// the values become garbage; the movement filter then rejects taps, so
    /// worst case is "feature quietly off", never a crash on our side.
    private static func centroid(of touches: UnsafeMutableRawPointer?, count: Int) -> (x: Float, y: Float)? {
        guard let touches, count > 0 else { return nil }
        let stride = 96
        var sumX: Float = 0, sumY: Float = 0
        for index in 0..<count {
            let base = touches.advanced(by: index * stride)
            sumX += base.loadUnaligned(fromByteOffset: 32, as: Float.self)
            sumY += base.loadUnaligned(fromByteOffset: 36, as: Float.self)
        }
        let x = sumX / Float(count)
        let y = sumY / Float(count)
        guard x.isFinite, y.isFinite else { return nil }
        return (x, y)
    }

    private var debugSessionStart: Double?
    private var debugMaxFingers = 0
    private var debugStartCentroid: (x: Float, y: Float)?
    private var debugMaxDeviation: Float = 0

    private func frame(fingers: Int, centroid: (x: Float, y: Float)?, at timestamp: Double) {
        // Debug bookkeeping mirrors the detector so failed taps are visible.
        if fingers > 0 {
            if debugSessionStart == nil {
                debugSessionStart = timestamp
                debugMaxFingers = 0
                debugStartCentroid = nil
                debugMaxDeviation = 0
            }
            debugMaxFingers = max(debugMaxFingers, fingers)
            if let centroid {
                if let start = debugStartCentroid {
                    let dx = centroid.x - start.x, dy = centroid.y - start.y
                    debugMaxDeviation = max(debugMaxDeviation, (dx * dx + dy * dy).squareRoot())
                } else {
                    debugStartCentroid = centroid
                }
            }
        } else if let start = debugSessionStart {
            debugSessionStart = nil
            if debugMaxFingers >= 3 {
                let ms = String(format: "%.0f", (timestamp - start) * 1000)
                let dev = String(format: "%.3f", self.debugMaxDeviation)
                markerLog.debug("touch session: maxFingers=\(self.debugMaxFingers) duration=\(ms, privacy: .public)ms movement=\(dev, privacy: .public)")
            }
        }
        // Callback arrives on a MultitouchSupport thread.
        if detector.frame(fingers: fingers, centroid: centroid, at: timestamp) {
            markerLog.info("three-finger tap detected")
            DispatchQueue.main.async { [weak self] in
                self?.onThreeFingerTap?()
            }
        }
    }
}