import AppKit
import ApplicationServices

/// Thin AX adapter: subscribes to selection-changed notifications on the
/// frontmost app, watches keystrokes for selection intent, and reads
/// selections on demand. All decisions live in CaptureEngine.
final class AXSelectionMonitor: NSObject, SelectionReading {
    var onSelectionChanged: (() -> Void)?
    var onKeyDown: ((_ isSelectionIntent: Bool) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var keyMonitor: Any?
    private var pendingElement: AXUIElement?
    private let systemWide = AXUIElementCreateSystemWide()

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(frontAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Distinguish user selections from programmatic ones (Cmd+L
        // selecting the URL bar, autocomplete): keyboard-driven selections
        // only count when the key looked like selection intent.
        if keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let flags = event.modifierFlags
                // keyCode, not characters: on non-Latin layouts (RU: "ф")
                // charactersIgnoringModifiers never matches "a".
                let isSelectAll = flags.contains(.command) && event.keyCode == 0 // kVK_ANSI_A
                self?.onKeyDown?(flags.contains(.shift) || isSelectAll)
            }
        }
        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    // MARK: - SelectionReading

    func currentSelection() -> String? {
        if let pendingElement, let text = selectedText(of: pendingElement) {
            return text
        }
        guard let focused = focusedElement() else { return nil }
        return selectedText(of: focused)
    }

    func roleAtMouseLocation() -> String? {
        let location = NSEvent.mouseLocation
        guard let screenHeight = NSScreen.screens.first?.frame.height else { return nil }
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(location.x),
            Float(screenHeight - location.y),
            &elementRef
        ) == .success, let elementRef else { return nil }
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            elementRef,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success else { return nil }
        return roleRef as? String
    }

    // MARK: - AX observer wiring

    @objc private func frontAppChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        attach(to: app)
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        appElement = nil
        pendingElement = nil
    }

    private func attach(to app: NSRunningApplication?) {
        detach()
        guard let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        guard AXIsProcessTrusted() else {
            markerLog.error("attach skipped: process not AX-trusted")
            return
        }

        let pid = app.processIdentifier
        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<AXSelectionMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.pendingElement = element
            monitor.onSelectionChanged?()
        }
        let createErr = AXObserverCreate(pid, callback, &newObserver)
        guard createErr == .success, let newObserver else {
            markerLog.error("AXObserverCreate failed for \(app.localizedName ?? "?", privacy: .public): \(createErr.rawValue)")
            return
        }

        let element = AXUIElementCreateApplication(pid)
        // Chromium keeps its AX tree disabled until a client asks for it
        // explicitly; native apps ignore unsupported attributes.
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let addErr = AXObserverAddNotification(
            newObserver,
            element,
            kAXSelectedTextChangedNotification as CFString,
            refcon
        )
        guard addErr == .success else {
            markerLog.error("AXObserverAddNotification failed for \(app.localizedName ?? "?", privacy: .public): \(addErr.rawValue)")
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )
        observer = newObserver
        appElement = element
        markerLog.info("attached to \(app.localizedName ?? "?", privacy: .public) pid=\(pid)")
    }

    // MARK: - AX reads

    private func selectedText(of element: AXUIElement) -> String? {
        var textRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &textRef
        )
        guard err == .success, let text = textRef as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    private func focusedElement() -> AXUIElement? {
        for source in [systemWide, appElement].compactMap({ $0 }) {
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                source,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success,
               let focusedRef,
               CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
                return (focusedRef as! AXUIElement)
            }
        }
        return nil
    }
}