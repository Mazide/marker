import AppKit

/// Trackpad touch feed via the private MultitouchSupport framework (the
/// same mechanism apps like Middle use). Loaded with dlopen/dlsym so
/// nothing links against the private framework at build time; if the
/// framework or symbols are missing the monitor silently does nothing.
/// Only the per-frame finger COUNT is read — touch struct layouts vary
/// between macOS versions, so we never parse them. Serves both paste
/// gestures: a live finger count for the click mode and a double-tap
/// detector fed from the frame stream.
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
    private typealias MTDeviceStop = @convention(c) (UnsafeMutableRawPointer?) -> Void

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

    private var createList: MTDeviceCreateList?
    private var register: MTRegisterContactFrameCallback?
    private var deviceStart: MTDeviceStart?
    private var deviceStop: MTDeviceStop?

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

        createList = unsafeBitCast(createListSym, to: MTDeviceCreateList.self)
        register = unsafeBitCast(registerSym, to: MTRegisterContactFrameCallback.self)
        deviceStart = unsafeBitCast(startSym, to: MTDeviceStart.self)
        // Optional: absent symbol just means restart() re-registers without
        // stopping the old devices first.
        if let stopSym = dlsym(handle, "MTDeviceStop") {
            deviceStop = unsafeBitCast(stopSym, to: MTDeviceStop.self)
        }

        attach()
    }

    /// Re-register the frame callback on a fresh device list. The
    /// MultitouchSupport feed dies silently across sleep/wake (observed
    /// 2026-07-17 and 2026-07-21); stale device refs never fire again, so
    /// stop them and start over.
    func restart() {
        guard started, createList != nil else { return }
        if let devices, let deviceStop {
            for index in 0..<CFArrayGetCount(devices) {
                deviceStop(UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(devices, index)))
            }
        }
        devices = nil
        attach()
    }

    private func attach() {
        guard let createList, let register, let deviceStart else { return }
        guard let list = createList()?.takeRetainedValue() else {
            markerLog.error("MTDeviceCreateList returned nothing")
            return
        }
        devices = list

        let callback: MTContactCallback = { _, _, fingers, timestamp, _ in
            TrackpadTapMonitor.shared?.frame(fingers: Int(fingers), at: timestamp)
            return 0
        }

        for index in 0..<CFArrayGetCount(list) {
            let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, index))
            register(device, callback)
            deviceStart(device, 0)
        }
        markerLog.info("trackpad monitor started (\(CFArrayGetCount(list)) devices)")
    }

    private var debugSessionStart: Double?
    private var debugMaxFingers = 0
    private var debugReachedThreeAt: Double?
    private var debugLastSessionEnd: Double?

    // Callback arrives on a MultitouchSupport thread.
    private func frame(fingers: Int, at timestamp: Double) {
        stateLock.lock()
        fingersDown = fingers
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        stateLock.unlock()

        // Debug bookkeeping mirrors the detector so failed taps are visible.
        if fingers > 0 {
            if debugSessionStart == nil {
                debugSessionStart = timestamp
                debugMaxFingers = 0
                debugReachedThreeAt = nil
            }
            debugMaxFingers = max(debugMaxFingers, fingers)
            if fingers == 3, debugReachedThreeAt == nil {
                debugReachedThreeAt = timestamp
            }
        } else if let start = debugSessionStart {
            debugSessionStart = nil
            if debugMaxFingers >= 3 {
                let ms = String(format: "%.0f", (timestamp - start) * 1000)
                let landing = self.debugReachedThreeAt.map {
                    String(format: "%.0f", ($0 - start) * 1000)
                } ?? "-"
                let gap = self.debugLastSessionEnd.map {
                    String(format: "%.0f", (timestamp - $0) * 1000)
                } ?? "-"
                markerLog.debug("touch session: maxFingers=\(self.debugMaxFingers) duration=\(ms, privacy: .public)ms landing=\(landing, privacy: .public)ms sinceLastSession=\(gap, privacy: .public)ms")
            }
            debugLastSessionEnd = timestamp
        }

        if doubleTap.frame(fingers: fingers, at: timestamp) {
            markerLog.info("three-finger double tap detected")
            DispatchQueue.main.async { [weak self] in
                self?.onThreeFingerDoubleTap?()
            }
        }
    }
}
