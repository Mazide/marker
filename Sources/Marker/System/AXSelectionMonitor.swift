import AppKit
import ApplicationServices

/// Thin AX adapter: subscribes to selection-changed notifications on the
/// frontmost app, watches keystrokes for selection intent, and reads
/// selections on demand. All decisions live in CaptureEngine.
final class AXSelectionMonitor: NSObject, SelectionReading {
    var onSelectionChanged: (() -> Void)?
    var onKeyDown: ((_ isSelectionIntent: Bool, _ isPlainTyping: Bool) -> Void)?

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
                let isSelectionIntent = flags.contains(.shift) || isSelectAll
                let isArrow = (123...126).contains(Int(event.keyCode))
                let isPlainTyping = !flags.contains(.command)
                    && !flags.contains(.control)
                    && !isArrow
                    && !isSelectionIntent
                self?.onKeyDown?(isSelectionIntent, isPlainTyping)
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

    func currentSelectionRich() -> RichText? {
        if let pendingElement, let rich = richSelectedText(of: pendingElement) {
            return rich
        }
        guard let focused = focusedElement() else { return nil }
        return richSelectedText(of: focused)
    }

    /// Role of the focused element — apps with minimal AX trees (kitty)
    /// return nothing useful from position hit-testing but do report focus.
    func focusedElementRole() -> String? {
        guard let focused = focusedElement() else { return nil }
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success else { return nil }
        return roleRef as? String
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

    /// Attributed selection via AXAttributedStringForRange, translated
    /// from AX text attributes (AXFont, AXForegroundColor, …) to display
    /// attributes and serialized as RTF + HTML. Whitespace at both ends is
    /// trimmed so the flavors match the trimmed plain text the engine
    /// stores. Returns nil when the app exposes no attributed text or no
    /// run carries an attribute we can translate.
    private func richSelectedText(of element: AXUIElement) -> RichText? {
        var display: NSAttributedString?
        if let axString = rangeAttributedSelection(of: element) {
            display = displayAttributed(from: axString)
            if display == nil {
                markerLog.info("rich: range read untranslatable, keys=\(Self.attributeKeys(of: axString), privacy: .public)")
            }
        }
        // Chromium's AXAttributedStringForRange drops all attributes once
        // the selection crosses text nodes; the WebKit-style text-marker
        // read keeps them.
        if display == nil, let axString = markerAttributedSelection(of: element) {
            display = displayAttributed(from: axString)
            if display == nil {
                markerLog.info("rich: marker read untranslatable, keys=\(Self.attributeKeys(of: axString), privacy: .public)")
            }
        }
        guard let display else { return nil }

        let plain = display.string
        let trimmedPlain = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlain.isEmpty else { return nil }
        var trimmed = display
        if trimmedPlain != plain {
            let trimRange = (plain as NSString).range(of: trimmedPlain)
            guard trimRange.location != NSNotFound else {
                markerLog.info("rich: trim lost the plain text")
                return nil
            }
            trimmed = display.attributedSubstring(from: trimRange)
        }

        let fullRange = NSRange(location: 0, length: trimmed.length)
        var content = RichText(plain: trimmedPlain)
        if let rtf = try? trimmed.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ), rtf.count <= RichText.flavorByteLimit {
            content.rtf = rtf
        }
        if let htmlData = try? trimmed.data(
            from: fullRange,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
        ), htmlData.count <= RichText.flavorByteLimit,
           let html = String(data: htmlData, encoding: .utf8) {
            content.html = html
        }
        guard content.hasFlavors else {
            markerLog.info("rich: serialization produced no flavors (len=\(trimmed.length))")
            return nil
        }
        return content
    }

    /// Attributed selection via AXAttributedStringForRange — the classic
    /// per-element read; nil when the app exposes no range or no string.
    private func rangeAttributedSelection(of element: AXUIElement) -> NSAttributedString? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else {
            markerLog.info("rich: no AXSelectedTextRange")
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range),
              range.length > 0, range.length <= 200_000
        else {
            markerLog.info("rich: bad range length=\(range.length)")
            return nil
        }

        var attrRef: CFTypeRef?
        let attrErr = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            rangeRef,
            &attrRef
        )
        guard attrErr == .success,
              let axString = attrRef as? NSAttributedString,
              axString.length > 0
        else {
            markerLog.info("rich: AXAttributedStringForRange err=\(attrErr.rawValue)")
            return nil
        }
        return axString
    }

    /// WebKit-style attributed selection via AXSelectedTextMarkerRange +
    /// AXAttributedStringForTextMarkerRange (Safari, Chromium web areas).
    private func markerAttributedSelection(of element: AXUIElement) -> NSAttributedString? {
        var markerRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRangeRef
        ) == .success, let markerRangeRef else {
            markerLog.info("rich: no AXSelectedTextMarkerRange")
            return nil
        }

        var attrRef: CFTypeRef?
        let attrErr = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForTextMarkerRange" as CFString,
            markerRangeRef,
            &attrRef
        )
        guard attrErr == .success,
              let axString = attrRef as? NSAttributedString,
              axString.length > 0
        else {
            markerLog.info("rich: AXAttributedStringForTextMarkerRange err=\(attrErr.rawValue)")
            return nil
        }
        return axString
    }

    private static func attributeKeys(of axString: NSAttributedString) -> String {
        var keys = Set<String>()
        axString.enumerateAttributes(
            in: NSRange(location: 0, length: axString.length)
        ) { attributes, _, _ in
            for key in attributes.keys { keys.insert(key.rawValue) }
        }
        return keys.sorted().joined(separator: ",")
    }

    /// AX attributed strings carry AX-specific keys, not display keys —
    /// serializing them directly would produce unformatted RTF. Translate
    /// the runs we understand; nil when nothing translated (plain capture
    /// is the honest result then).
    private func displayAttributed(from axString: NSAttributedString) -> NSAttributedString? {
        let out = NSMutableAttributedString(string: axString.string)
        var sawFormatting = false
        axString.enumerateAttributes(
            in: NSRange(location: 0, length: axString.length)
        ) { attributes, range, _ in
            var display: [NSAttributedString.Key: Any] = [:]
            if let fontInfo = attributes[NSAttributedString.Key("AXFont")] as? [String: Any] {
                let size = (fontInfo["AXFontSize"] as? NSNumber)?.doubleValue ?? 0
                if let name = fontInfo["AXFontName"] as? String, size > 0,
                   let font = NSFont(name: name, size: size) {
                    display[.font] = font
                }
            }
            if let value = attributes[NSAttributedString.Key("AXForegroundColor")],
               let color = nsColor(from: value) {
                display[.foregroundColor] = color
            }
            if let value = attributes[NSAttributedString.Key("AXBackgroundColor")],
               let color = nsColor(from: value) {
                display[.backgroundColor] = color
            }
            if let underline = attributes[NSAttributedString.Key("AXUnderline")] as? NSNumber,
               underline.intValue != 0 {
                display[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if let strike = attributes[NSAttributedString.Key("AXStrikethrough")] as? NSNumber,
               strike.boolValue {
                display[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let url = linkURL(from: attributes[NSAttributedString.Key("AXLink")]) {
                display[.link] = url
            }
            if !display.isEmpty {
                out.addAttributes(display, range: range)
                sawFormatting = true
            }
        }
        return sawFormatting ? out : nil
    }

    private func nsColor(from value: Any) -> NSColor? {
        let ref = value as CFTypeRef
        guard CFGetTypeID(ref) == CGColor.typeID else { return nil }
        return NSColor(cgColor: ref as! CGColor)
    }

    /// AXLink's value is the link's AXUIElement; its AXURL is the target.
    private func linkURL(from value: Any?) -> URL? {
        guard let value else { return nil }
        let ref = value as CFTypeRef
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            ref as! AXUIElement,
            "AXURL" as CFString,
            &urlRef
        ) == .success,
              let urlRef,
              CFGetTypeID(urlRef) == CFURLGetTypeID()
        else { return nil }
        return (urlRef as! CFURL) as URL
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