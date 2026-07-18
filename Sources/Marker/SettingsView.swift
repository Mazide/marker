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
