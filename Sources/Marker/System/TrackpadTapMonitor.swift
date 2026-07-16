import AppKit

/// Trackpad touch feed via the private MultitouchSupport framework (the
/// same mechanism apps like Middle use). Loaded with dlopen/dlsym so
/// nothing links against the private framework at build time; if the
/// framework or symbols are missing the monitor silently does nothing.
/// Serves both paste gestures: a live finger count for the click mode
/// and a double-tap detector fed from the frame stream.
final class TrackpadTapMonitor {
    /// Fires on the main queue when a three-finger double tap completes.
    var onThreeFingerDoubleTap: (() -> Void)?

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

    private let stateLock = NSLock()
    private var fingersDown = 0
    private var lastFrameUptime: TimeInterval = 0

    private var doubleTap = ThreeFingerDoubleTapDetector()
    private var devices: CFArray?
    private var started = false

    /// Fingers currently on the pad. Frames stream continuously while
    /// anything touches, and a physical click always disturbs the contacts
    /// right before the mouse event, so a short staleness window is enough
    /// to never answer from a dead feed (device gone, monitor never ran).
    func fingersTouching() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard ProcessInfo.processInfo.systemUptime - lastFrameUptime < 0.5 else { return 0 }
        return fingersDown
    }

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
            markerLog.error("MultitouchSupport unavailable; three-finger paste disabled")
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
        markerLog.info("trackpad monitor started (\(CFArrayGetCount(list)) devices)")
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

    // Callback arrives on a MultitouchSupport thread.
    private func frame(fingers: Int, centroid: (x: Float, y: Float)?, at timestamp: Double) {
        stateLock.lock()
        fingersDown = fingers
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        stateLock.unlock()

        if doubleTap.frame(fingers: fingers, centroid: centroid, at: timestamp) {
            markerLog.info("three-finger double tap detected")
            DispatchQueue.main.async { [weak self] in
                self?.onThreeFingerDoubleTap?()
            }
        }
    }
}
