import AppKit
import ApplicationServices
import os

let markerLog = Logger(subsystem: "dev.looseconfetti.marker", category: "watcher")

/// Watches the frontmost application for text-selection changes via the
/// Accessibility API and reports the selected text after a short debounce.
final class SelectionWatcher: NSObject {
    var onSelection: ((String, NSRunningApplication) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var watchedApp: NSRunningApplication?
    private var debounceTimer: Timer?
    private var lastReported: String?
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
        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    @objc private func frontAppChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        attach(to: app)
    }

    private func detach() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        appElement = nil
        watchedApp = nil
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
            let watcher = Unmanaged<SelectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.selectionChanged(in: element)
        }
        let createErr = AXObserverCreate(pid, callback, &newObserver)
        guard createErr == .success, let newObserver else {
            markerLog.error("AXObserverCreate failed for \(app.localizedName ?? "?", privacy: .public): \(createErr.rawValue)")
            return
        }

        let element = AXUIElementCreateApplication(pid)
        // Chromium keeps its AX tree disabled until a client asks for it
        // explicitly (verified: AXEnhancedUserInterface wakes Chrome's tree).
        // Native apps ignore unsupported attributes, so set both everywhere.
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
        markerLog.info("attached to \(app.localizedName ?? "?", privacy: .public) pid=\(pid)")

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )
        observer = newObserver
        appElement = element
        watchedApp = app
    }

    /// Selection notifications fire on every caret move while dragging;
    /// debounce so we only read the selection once the user settles.
    private func selectionChanged(in element: AXUIElement) {
        markerLog.debug("selection-changed notification")
        pendingElement = element
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.captureSelection()
        }
    }

    private func captureSelection() {
        guard let watchedApp else { return }

        // The notification's element is the most reliable source; fall back
        // to the focused element (system-wide, then per-app).
        var text = pendingElement.flatMap { selectedText(of: $0) }
        if text == nil, let focused = focusedElement() {
            text = selectedText(of: focused)
        }
        pendingElement = nil

        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text != lastReported
        else {
            markerLog.debug("no usable selection")
            return
        }
        markerLog.info("captured \(text.count) chars")

        lastReported = text
        onSelection?(text, watchedApp)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var textRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &textRef
        )
        guard err == .success, let text = textRef as? String, !text.isEmpty else {
            markerLog.debug("selectedText read failed: \(err.rawValue)")
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
