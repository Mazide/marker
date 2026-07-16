import AppKit

/// Live trackpad finger count via the private MultitouchSupport framework
/// (the same mechanism apps like Middle use). Loaded with dlopen/dlsym so
/// nothing links against the private framework at build time; if the
/// framework or symbols are missing the monitor silently does nothing.
/// Only the per-frame finger COUNT is read — touch struct layouts vary
/// between macOS versions, so we never parse them.
final class TrackpadTapMonitor {
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
            markerLog.error("MultitouchSupport unavailable; three-finger click disabled")
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

        let callback: MTContactCallback = { _, _, fingers, _, _ in
            TrackpadTapMonitor.shared?.frame(fingers: Int(fingers))
            return 0
        }

        for index in 0..<CFArrayGetCount(list) {
            let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, index))
            register(device, callback)
            deviceStart(device, 0)
        }
        markerLog.info("trackpad monitor started (\(CFArrayGetCount(list)) devices)")
    }

    // Callback arrives on a MultitouchSupport thread.
    private func frame(fingers: Int) {
        stateLock.lock()
        fingersDown = fingers
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        stateLock.unlock()
    }
}
