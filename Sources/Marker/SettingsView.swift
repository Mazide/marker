import Carbon.HIToolbox
import SwiftUI

/// Two panes' worth of settings do not need a tab bar: one scrolling
/// window, with the links as a centered footer.
struct SettingsView: View {
    var body: some View {
        GeneralSettingsView()
            .frame(width: 520, height: 520)
            .navigationTitle("Settings")
    }
}

private struct GeneralSettingsView: View {
    private var model = AppModel.shared
    @State private var autoUpdates = AppModel.shared.autoUpdatesEnabled

    var body: some View {
        VStack(spacing: 0) {
            form
            footer
        }
    }

    private var form: some View {
        Form {
            Section("Updates") {
                LabeledContent("Version \(model.appVersion)") {
                    Button("Check Now…") {
                        model.checkForUpdates()
                    }
                }
                Toggle("Update Marker automatically", isOn: $autoUpdates)
                    .onChange(of: autoUpdates) { _, newValue in
                        model.autoUpdatesEnabled = newValue
                    }
            }

            Section("Capture") {
                SettingToggle(
                    "Ignore selections you immediately edit",
                    caption: "Typing over a fresh selection cancels its capture.",
                    isOn: Bindable(model).retractEditedEnabled
                )
                SettingToggle(
                    "Never save secrets",
                    caption: "Keys and tokens are never captured into history.",
                    isOn: Bindable(model).skipSecretsEnabled
                )
                SettingToggle(
                    "Fall back to ⌘C on web pages and Electron apps",
                    caption: "Keeps real formatting from web content.",
                    detail: "Browsers and web-based apps (Slack, Discord, …) expose their formatting only through their own Copy command. When you select text there, Marker synthesizes a brief ⌘C to grab the formatted copy, then restores your clipboard.",
                    isOn: Bindable(model).richCopyEnabled
                )
            }

            Section {
                ForEach(model.excludedBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        Image(nsImage: AppIcons.icon(for: bundleID))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(Self.appDisplayName(for: bundleID))
                        Spacer()
                        Button {
                            model.excludedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop ignoring")
                    }
                }
                addIgnoredAppMenu
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Selections in these apps are never captured — no history entry, no ⌘C fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                HotkeyRecorder(
                    "Paste latest selection",
                    combo: Bindable(model).pasteHotkey,
                    defaultCombo: AppModel.defaultPasteCombo,
                    isTaken: { $0 == model.historyHotkey }
                )
                HotkeyRecorder(
                    "Open history",
                    combo: Bindable(model).historyHotkey,
                    defaultCombo: AppModel.defaultHistoryCombo,
                    isTaken: { $0 == model.pasteHotkey }
                )
            }

            Section("Paste") {
                SettingToggle(
                    "Middle-click pastes the latest selection",
                    caption: "Works over text fields; clicks anywhere else pass through untouched.",
                    isOn: Bindable(model).middleClickPasteEnabled
                )
                Picker(selection: Bindable(model).threeFingerPasteMode) {
                    Text("Off").tag(ThreeFingerPasteMode.off)
                    Text("Physical click").tag(ThreeFingerPasteMode.click)
                    Text("Double tap").tag(ThreeFingerPasteMode.doubleTap)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Three-finger paste")
                        Text("Middle-click for the trackpad: pastes the latest selection. Experimental.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Interface") {
                Toggle("Show a popup on capture", isOn: Bindable(model).toastEnabled)
                Toggle("Start at login", isOn: Bindable(model).launchAtLogin)
            }

            Section("History") {
                Picker("Keep history for", selection: Bindable(model).historyRetentionDays) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                LabeledContent("Remove every captured selection") {
                    Button("Clear History…", role: .destructive) {
                        model.history.clear()
                    }
                    .disabled(model.history.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Running regular apps first — the app someone wants to ignore is
    /// usually open right now — with an open panel for everything else.
    private var addIgnoredAppMenu: some View {
        Menu("Add App…") {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
                .filter { $0 != Bundle.main.bundleIdentifier && !model.excludedBundleIDs.contains($0) }
                .sorted { Self.appDisplayName(for: $0) < Self.appDisplayName(for: $1) }
            ForEach(running, id: \.self) { bundleID in
                Button {
                    model.excludedBundleIDs.append(bundleID)
                } label: {
                    Image(nsImage: AppIcons.icon(for: bundleID))
                    Text(Self.appDisplayName(for: bundleID))
                }
            }
            Divider()
            Button("Other…") { pickIgnoredApp() }
        }
        .fixedSize()
    }

    private func pickIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !model.excludedBundleIDs.contains(bundleID)
        else { return }
        model.excludedBundleIDs.append(bundleID)
    }

    private static func appDisplayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Link("Website", destination: URL(string: "https://getmarkerapp.net")!)
            Link("GitHub", destination: URL(string: "https://github.com/Mazide/marker")!)
            Link("Privacy Policy", destination: URL(string: "https://getmarkerapp.net/privacy/")!)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// Click-to-record shortcut field. While recording, a local key monitor
/// grabs the next chord: Esc cancels, a chord without modifiers is
/// refused (bare letters must keep typing), a chord already used by the
/// other action beeps. Key codes are stored, so shortcuts survive layout
/// switches; the label shows what was typed at record time.
private struct HotkeyRecorder: View {
    let title: LocalizedStringKey
    @Binding var combo: KeyCombo
    let defaultCombo: KeyCombo
    let isTaken: (KeyCombo) -> Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    init(
        _ title: LocalizedStringKey,
        combo: Binding<KeyCombo>,
        defaultCombo: KeyCombo,
        isTaken: @escaping (KeyCombo) -> Bool
    ) {
        self.title = title
        self._combo = combo
        self.defaultCombo = defaultCombo
        self.isTaken = isTaken
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if combo != defaultCombo, !isRecording {
                    Button {
                        combo = defaultCombo
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reset to \(defaultCombo.label)")
                }
                Button(isRecording ? "Type shortcut…" : combo.label) {
                    isRecording ? stopRecording() : startRecording()
                }
                .font(isRecording ? .body : .body.monospaced())
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            guard !flags.isEmpty else {
                NSSound.beep()
                return nil
            }
            let candidate = KeyCombo(
                keyCode: UInt32(event.keyCode),
                modifiers: KeyCombo.carbonModifiers(from: flags),
                label: Self.label(for: event, flags: flags)
            )
            guard !isTaken(candidate) else {
                NSSound.beep()
                return nil
            }
            combo = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func label(for event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts + keyName(for: event)
    }

    private static func keyName(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}

/// A toggle whose explanation lives inside the row, the way System
/// Settings does it — a separate caption row splits the form into
/// alternating stripes.
private struct SettingToggle: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var isOn: Bool
    @State private var showingDetail = false

    init(
        _ title: LocalizedStringKey,
        caption: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.caption = caption
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                    if let detail {
                        Button {
                            showingDetail = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More about this setting")
                        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
                            Text(detail)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 280)
                                .padding()
                        }
                    }
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
