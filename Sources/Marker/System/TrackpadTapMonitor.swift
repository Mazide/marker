import AppKit

/// Trackpad touch feed via the private MultitouchSupport framework (the
/// same mechanism apps like Middle use). The private symbols are resolved
/// at runtime; malformed or unfamiliar touch records fail closed.
final class TrackpadTapMonitor {
    /// Called on the main queue at the beginning of a potential first tap.
    var onFirstTouchSessionStarted: (() -> Void)?
    /// Called on the main queue only after the 150 ms late-swipe guard.
    var onThreeFingerDoubleTap: (() -> Void)?
    /// Clears any AX target retained by the owner.
    var onTapSequenceInvalidated: (() -> Void)?

    private typealias MTDeviceCreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias MTRegisterContactFrameCallback = @convention(c) (
        UnsafeMutableRawPointer?, MTContactCallback?
    ) -> Void
    private typealias MTDeviceStart = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias MTDeviceStop = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private struct MTPoint {
        var x: Float
        var y: Float
    }

    private struct MTReadout {
        var position: MTPoint
        var velocity: MTPoint
    }

    /// Full 96-byte MTTouch record exposed
    /// by MultitouchSupport on supported macOS releases. Only `state`,
    /// `fingerID`, and the normalized readout are consumed.
    private struct MTTouchRecord {
        var frame: Int32
        var timestamp: Double
        var pathIndex: Int32
        var state: Int32
        var fingerID: Int32
        var handID: Int32
        var normalized: MTReadout
        var size: Float
        var zero1: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var absolute: MTReadout
        var zero2a: Int32
        var zero2b: Int32
        var unknown2: Float
    }

    // The C callback has no refcon; a single shared instance receives frames.
    nonisolated(unsafe) static var shared: TrackpadTapMonitor?

    private let stateLock = NSLock()
    private var fingersDown = 0
    private var lastFrameUptime: TimeInterval = 0
    private var loggedDecodeFailureForSession = false
    private var loggedStableDecodeForSession = false

    /// Accessed only on the main queue. Raw touch callbacks copy their data
    /// before dispatching here.
    private var detector: SwipeLockedThreeFingerDoubleTapDetector
    private var pasteGuardWork: DispatchWorkItem?
    private var pairExpiryWork: DispatchWorkItem?
    private var suppressionReleaseWork: DispatchWorkItem?

    private var devices: CFArray?
    private var started = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var globalSwipeMonitor: Any?
    private var localSwipeMonitor: Any?

    private var createList: MTDeviceCreateList?
    private var register: MTRegisterContactFrameCallback?
    private var deviceStart: MTDeviceStart?
    private var deviceStop: MTDeviceStop?

    private enum DecodeFailure: String {
        case unreasonableCount
        case missingBuffer
        case unexpectedStride
        case invalidState
        case invalidGeometry
    }

    private struct ContactDecode {
        let contacts: [ThreeFingerTouchContact]?
        let failure: DecodeFailure?
        let uniqueIdentifierCount: Int
        let uniqueLegacyFieldCount: Int
        let touchingCount: Int
    }

    init() {
        var detector = SwipeLockedThreeFingerDoubleTapDetector()
        let stored = UserDefaults.standard.double(forKey: "threeFingerTapMovementLimit")
        if stored > 0, stored <= 0.08 {
            detector.movementLimit = stored
        }
        self.detector = detector
    }

    /// Fingers currently on the pad. A short staleness window prevents a
    /// physical-click decision from using a dead MultitouchSupport feed.
    func fingersTouching() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard ProcessInfo.processInfo.systemUptime - lastFrameUptime < 0.5 else { return 0 }
        return fingersDown
    }

    /// Main-queue guard used again immediately before AppModel pastes.
    func isSwipeSuppressed() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return detector.phase == .swipeSuppressed
    }

    func start() {
        guard !started else { return }
        started = true
        Self.shared = self
        installSystemGestureObservers()

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
        if let stopSym = dlsym(handle, "MTDeviceStop") {
            deviceStop = unsafeBitCast(stopSym, to: MTDeviceStop.self)
        }

        attach()
    }

    /// Re-register the callback after sleep/wake, when stale device refs no
    /// longer deliver frames.
    func restart() {
        guard started, createList != nil else { return }
        cancelTapSequence(reason: .modeChanged)
        if let devices, let deviceStop {
            for index in 0..<CFArrayGetCount(devices) {
                deviceStop(UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(devices, index)))
            }
        }
        devices = nil
        attach()
    }

    func cancelTapSequence(
        reason: SwipeLockedThreeFingerDoubleTapDetector.CancellationReason
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        handle(detector.invalidate(reason: reason, at: Self.now))
    }

    private func installSystemGestureObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.receivedSuppressionSignal(.activeSpaceChanged)
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.receivedSuppressionSignal(.frontmostAppChanged)
        })

        globalSwipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] _ in
            self?.deliverSuppressionSignal(.appKitSwipe)
        }
        localSwipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            self?.receivedSuppressionSignal(.appKitSwipe)
            return event
        }
    }

    private func deliverSuppressionSignal(
        _ reason: SwipeLockedThreeFingerDoubleTapDetector.SuppressionReason
    ) {
        if Thread.isMainThread {
            receivedSuppressionSignal(reason)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.receivedSuppressionSignal(reason)
            }
        }
    }

    private func attach() {
        guard let createList, let register, let deviceStart else { return }
        guard let list = createList()?.takeRetainedValue() else {
            markerLog.error("MTDeviceCreateList returned nothing")
            return
        }
        devices = list

        let callback: MTContactCallback = { _, rawTouches, fingers, _, _ in
            let count = max(0, Int(fingers))
            let decoded = TrackpadTapMonitor.decodeContacts(rawTouches, count: count)
            TrackpadTapMonitor.shared?.receivedFrame(fingers: count, decoded: decoded)
            return 0
        }

        for index in 0..<CFArrayGetCount(list) {
            let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, index))
            register(device, callback)
            deviceStart(device, 0)
        }
        markerLog.info("trackpad monitor started (\(CFArrayGetCount(list)) devices)")
    }

    private static func decodeContacts(
        _ rawTouches: UnsafeMutableRawPointer?,
        count: Int
    ) -> ContactDecode {
        if count == 0 {
            return ContactDecode(
                contacts: [], failure: nil,
                uniqueIdentifierCount: 0, uniqueLegacyFieldCount: 0, touchingCount: 0
            )
        }
        guard count <= 16 else {
            return ContactDecode(
                contacts: nil, failure: .unreasonableCount,
                uniqueIdentifierCount: 0, uniqueLegacyFieldCount: 0, touchingCount: 0
            )
        }
        guard let rawTouches else {
            return ContactDecode(
                contacts: nil, failure: .missingBuffer,
                uniqueIdentifierCount: 0, uniqueLegacyFieldCount: 0, touchingCount: 0
            )
        }
        guard MemoryLayout<MTTouchRecord>.stride == 96 else {
            return ContactDecode(
                contacts: nil, failure: .unexpectedStride,
                uniqueIdentifierCount: 0, uniqueLegacyFieldCount: 0, touchingCount: 0
            )
        }

        let raw = UnsafeRawPointer(rawTouches)
        var records: [MTTouchRecord] = []
        records.reserveCapacity(count)
        for index in 0..<count {
            records.append(raw.advanced(by: index * MemoryLayout<MTTouchRecord>.stride)
                .load(as: MTTouchRecord.self))
        }
        let uniqueIdentifierCount = Set(records.map(\.fingerID)).count
        let uniqueLegacyFieldCount = Set(records.map(\.pathIndex)).count
        var contacts: [ThreeFingerTouchContact] = []
        contacts.reserveCapacity(count)
        for record in records {
            guard let state = ThreeFingerTouchState(rawValue: Int(record.state)) else {
                return ContactDecode(
                    contacts: nil, failure: .invalidState,
                    uniqueIdentifierCount: uniqueIdentifierCount,
                    uniqueLegacyFieldCount: uniqueLegacyFieldCount,
                    touchingCount: 0
                )
            }
            let contact = ThreeFingerTouchContact(
                fingerID: Int(record.fingerID),
                state: state,
                position: ThreeFingerTouchVector(
                    x: Double(record.normalized.position.x),
                    y: Double(record.normalized.position.y)
                ),
                velocity: ThreeFingerTouchVector(
                    x: Double(record.normalized.velocity.x),
                    y: Double(record.normalized.velocity.y)
                )
            )
            guard contact.hasValidGeometry else {
                return ContactDecode(
                    contacts: nil, failure: .invalidGeometry,
                    uniqueIdentifierCount: uniqueIdentifierCount,
                    uniqueLegacyFieldCount: uniqueLegacyFieldCount,
                    touchingCount: contacts.filter { $0.state == .touching }.count
                )
            }
            contacts.append(contact)
        }
        return ContactDecode(
            contacts: contacts,
            failure: nil,
            uniqueIdentifierCount: uniqueIdentifierCount,
            uniqueLegacyFieldCount: uniqueLegacyFieldCount,
            touchingCount: contacts.filter { $0.state == .touching }.count
        )
    }

    // The callback arrives on a MultitouchSupport thread. Copy everything
    // before dispatch: the framework owns and immediately reuses the buffer.
    private func receivedFrame(
        fingers: Int,
        decoded: ContactDecode
    ) {
        let now = Self.now
        var diagnostic: String?
        stateLock.lock()
        fingersDown = fingers
        lastFrameUptime = now
        if fingers == 0 {
            loggedDecodeFailureForSession = false
            loggedStableDecodeForSession = false
        } else if fingers == 3,
                  let failure = decoded.failure,
                  !loggedDecodeFailureForSession {
            loggedDecodeFailureForSession = true
            diagnostic = "failure=\(failure.rawValue) ids=\(decoded.uniqueIdentifierCount) legacy=\(decoded.uniqueLegacyFieldCount)"
        } else if fingers == 3,
                  decoded.touchingCount == 3,
                  !loggedStableDecodeForSession {
            loggedStableDecodeForSession = true
            diagnostic = "failure=none ids=\(decoded.uniqueIdentifierCount) legacy=\(decoded.uniqueLegacyFieldCount) touching=3"
        }
        stateLock.unlock()

        if let diagnostic {
            markerLog.debug("three-finger decode aggregate: \(diagnostic, privacy: .public)")
        }

        let frame = ThreeFingerTouchFrame(fingers: fingers, contacts: decoded.contacts, time: now)
        DispatchQueue.main.async { [weak self] in
            self?.process(frame)
        }
    }

    private func process(_ frame: ThreeFingerTouchFrame) {
        dispatchPrecondition(condition: .onQueue(.main))
        handle(detector.frame(frame))
        if detector.phase == .swipeSuppressed {
            if frame.fingers == 0 {
                scheduleSuppressionRelease()
            } else {
                suppressionReleaseWork?.cancel()
                suppressionReleaseWork = nil
            }
        }
    }

    private func receivedSuppressionSignal(
        _ reason: SwipeLockedThreeFingerDoubleTapDetector.SuppressionReason
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        handle(detector.suppress(reason: reason, at: Self.now))
        if fingersTouching() == 0 {
            scheduleSuppressionRelease()
        }
    }

    private func handle(_ actions: [SwipeLockedThreeFingerDoubleTapDetector.Action]) {
        for action in actions {
            switch action {
            case .firstSessionStarted:
                onFirstTouchSessionStarted?()
            case .pastePending:
                pairExpiryWork?.cancel()
                pairExpiryWork = nil
                schedulePasteGuard()
            case .pasteApproved:
                pasteGuardWork = nil
                markerLog.debug("three-finger paste guard approved")
                onThreeFingerDoubleTap?()
            case .sequenceInvalidated(let reason):
                cancelPendingWork()
                onTapSequenceInvalidated?()
                markerLog.debug("three-finger tap sequence invalidated: \(reason.rawValue, privacy: .public)")
            case .swipeSuppressed(let reason):
                cancelPendingWork()
                onTapSequenceInvalidated?()
                markerLog.debug("three-finger swipe suppression: \(reason.rawValue, privacy: .public)")
            case .suppressionEnded:
                suppressionReleaseWork = nil
                markerLog.debug("three-finger swipe suppression ended")
            case .sessionMetrics(let metrics):
                log(metrics)
                if metrics.outcome == .firstTap {
                    schedulePairExpiry()
                }
            }
        }
    }

    private func schedulePasteGuard() {
        pasteGuardWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.handle(self.detector.approvePendingPaste(at: Self.now))
        }
        pasteGuardWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + detector.pasteGuardInterval,
            execute: work
        )
    }

    private func schedulePairExpiry() {
        pairExpiryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.handle(self.detector.expireFirstTap(at: Self.now))
        }
        pairExpiryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + detector.maxGap, execute: work)
    }

    private func scheduleSuppressionRelease() {
        suppressionReleaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let actions = self.detector.releaseSuppressionIfReady(at: Self.now)
            self.handle(actions)
            if actions.isEmpty, self.detector.phase == .swipeSuppressed,
               self.fingersTouching() == 0 {
                self.scheduleSuppressionRelease()
            }
        }
        suppressionReleaseWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + detector.suppressionReleaseInterval,
            execute: work
        )
    }

    private func cancelPendingWork() {
        pasteGuardWork?.cancel()
        pasteGuardWork = nil
        pairExpiryWork?.cancel()
        pairExpiryWork = nil
    }

    private func log(_ metrics: SwipeLockedThreeFingerDoubleTapDetector.SessionMetrics) {
        let duration = String(format: "%.0f", metrics.duration * 1_000)
        let landing = metrics.landingDelay.map { String(format: "%.0f", $0 * 1_000) } ?? "-"
        let transfer = String(format: "%.4f", metrics.maxTransfer)
        let velocity = String(format: "%.4f", metrics.maxVelocity)
        markerLog.debug(
            "three-finger session: duration=\(duration, privacy: .public)ms landing=\(landing, privacy: .public)ms stableFrames=\(metrics.stableFrames) transfer=\(transfer, privacy: .public) velocity=\(velocity, privacy: .public) outcome=\(metrics.outcome.rawValue, privacy: .public)"
        )
    }

    private static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
