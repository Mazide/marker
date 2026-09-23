import AppKit
import ApplicationServices

/// Opaque identity captured at the start of a double-tap sequence. Keeping
/// the AX element itself lets the final guard reject a focus change even when
/// the replacement happens to have the same role.
struct FocusedPasteTarget {
    fileprivate let pid: pid_t
    fileprivate let element: AXUIElement
    fileprivate let role: String?
    fileprivate let frame: CGRect?
    fileprivate let focusGeneration: UInt64
}

/// AX element underneath a physical click. Retaining its process identity is
/// essential: a session event tap runs before the click activates another app.
struct PasteHitTarget {
    fileprivate let pid: pid_t
    fileprivate let element: AXUIElement
    let role: String?
}

/// Thin AX adapter: subscribes to selection-changed notifications on the
/// frontmost app, watches keystrokes for selection intent, and reads
/// selections on demand. All decisions live in CaptureEngine.
final class AXSelectionMonitor: NSObject, SelectionReading {
    var onSelectionChanged: (() -> Void)?
    var onFocusedElementChanged: (() -> Void)?
    var onKeyDown: ((
        _ isSelectionIntent: Bool,
        _ isPlainTyping: Bool,
        _ isMarkerSynthetic: Bool
    ) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var keyMonitor: Any?
    private var pendingElement: AXUIElement?
    private let systemWide = AXUIElementCreateSystemWide()
    private var focusGeneration: UInt64 = 0

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
                let isMarkerSynthetic = CGEventKeySynthesizer.isMarkerSynthetic(event.cgEvent)
                self?.onKeyDown?(isSelectionIntent, isPlainTyping, isMarkerSynthetic)
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
        return role(of: focused)
    }

    /// Capture only an editable element owned by the frontmost process.
    /// Missing or inconsistent AX data fails closed.
    func focusedEditablePasteTarget() -> FocusedPasteTarget? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let focused = focusedElement(),
              MiddlePastePolicy.shouldPaste(role: role(of: focused))
        else { return nil }
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(focused, &elementPID) == .success,
              elementPID == frontmostPID
        else { return nil }
        return FocusedPasteTarget(
            pid: elementPID,
            element: focused,
            role: role(of: focused),
            frame: frame(of: focused),
            focusGeneration: focusGeneration
        )
    }

    /// Revalidate process, AX identity, and editable role immediately before
    /// a delayed gesture paste.
    func isStillFocusedEditable(_ target: FocusedPasteTarget) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              focusGeneration == target.focusGeneration,
              let focused = focusedElement(),
              CFEqual(focused, target.element),
              MiddlePastePolicy.shouldPaste(role: role(of: focused))
        else { return false }
        var elementPID: pid_t = 0
        return AXUIElementGetPid(focused, &elementPID) == .success
            && elementPID == target.pid
    }

    func pasteHitTarget(at point: CGPoint) -> PasteHitTarget? {
        guard let element = element(atScreenLocation: point) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return PasteHitTarget(pid: pid, element: element, role: role(of: element))
    }

    /// Proves that a click seen before event delivery belongs to the already
    /// focused editor. This prevents swallowing a click intended to activate
    /// another app/control and then pasting into the stale focus.
    func hitTargetsFocusedEditable(
        _ hit: PasteHitTarget,
        at point: CGPoint,
        target: FocusedPasteTarget
    ) -> Bool {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let generationMatches = focusGeneration == target.focusGeneration
        let sameElement = CFEqual(hit.element, target.element)
        let matches = Self.hitTargetsFocusedEditable(
            frontmostPID: frontmostPID,
            hitPID: hit.pid,
            targetPID: target.pid,
            focusGenerationMatches: generationMatches,
            sameAXElement: sameElement,
            targetRole: target.role,
            targetFrame: target.frame,
            point: point
        )
        // Use only the metadata already read for the decision: no extra AX
        // calls inside the event tap and no titles, values, URLs, or geometry.
        diagLog(
            "paste.hit_test matched=\(matches) "
                + "frontmost_pid=\(frontmostPID ?? 0) target_pid=\(target.pid) hit_pid=\(hit.pid) "
                + "focused_role=\(target.role ?? "nil") cursor_role=\(hit.role ?? "nil") "
                + "focus_generation_matches=\(generationMatches) same_element=\(sameElement) "
                + "frame_available=\(target.frame != nil) inside_frame=\(target.frame?.contains(point) ?? false)"
        )
        return matches
    }

    static func hitTargetsFocusedEditable(
        frontmostPID: pid_t?,
        hitPID: pid_t,
        targetPID: pid_t,
        focusGenerationMatches: Bool,
        sameAXElement: Bool,
        targetRole: String?,
        targetFrame: CGRect?,
        point: CGPoint
    ) -> Bool {
        guard frontmostPID == targetPID,
              hitPID == targetPID,
              focusGenerationMatches,
              MiddlePastePolicy.shouldPaste(role: targetRole)
        else { return false }
        if sameAXElement { return true }
        guard let targetFrame else { return false }
        return targetFrame.contains(point)
    }

    func isScreenPointInsideFocusedEditableTarget(
        _ point: CGPoint,
        target: FocusedPasteTarget
    ) -> Bool {
        guard MiddlePastePolicy.shouldPaste(role: target.role),
              let frame = target.frame
        else { return false }
        return frame.contains(point)
    }

    func role(atScreenLocation point: CGPoint) -> String? {
        guard let element = element(atScreenLocation: point) else { return nil }
        return role(of: element)
    }

    private func element(atScreenLocation point: CGPoint) -> AXUIElement? {
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &elementRef
        ) == .success else { return nil }
        return elementRef
    }

    func roleAtMouseLocation() -> String? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        return role(atScreenLocation: point)
    }

    // MARK: - AX observer wiring

    @objc private func frontAppChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        attach(to: app)
    }

    private func detach() {
        focusGeneration &+= 1
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
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<AXSelectionMonitor>.fromOpaque(refcon).takeUnretainedValue()
            if notification as String == kAXFocusedUIElementChangedNotification as String {
                monitor.focusGeneration &+= 1
                monitor.pendingElement = nil
                monitor.onFocusedElementChanged?()
                return
            }
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
        // Not every app exposes focus notifications. The final identity
        // check still protects those apps, so failure here is non-fatal.
        _ = AXObserverAddNotification(
            newObserver,
            element,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )

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

    private func role(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success else { return nil }
        return roleRef as? String
    }
    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success,
              AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeRef
              ) == .success,
              let positionRef,
              let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              position.x.isFinite,
              position.y.isFinite,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
