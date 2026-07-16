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
                    "Copy selections to the clipboard",
                    caption: "Every selection is ready to ⌘V; off keeps it in Marker's history only.",
                    isOn: Bindable(model).copyToClipboardEnabled
                )
                SettingToggle(
                    "Ignore selections you immediately edit",
                    caption: "Typing over a fresh selection cancels its capture.",
                    isOn: Bindable(model).retractEditedEnabled
                )
                SettingToggle(
                    "Never save secrets",
                    caption: "Keys and tokens reach the clipboard but stay out of history.",
                    isOn: Bindable(model).skipSecretsEnabled
                )
                SettingToggle(
                    "Fall back to ⌘C on web pages and Electron apps",
                    caption: "Keeps real formatting from web content.",
                    detail: "Browsers and web-based apps (Slack, Discord, …) expose their formatting only through their own Copy command. When you select text there, Marker synthesizes a brief ⌘C to grab the formatted copy, then restores your clipboard.",
                    isOn: Bindable(model).richCopyEnabled
                )
            }

            Section("Paste") {
                SettingToggle(
                    "Middle-click pastes the latest selection",
                    caption: "Works over text fields; clicks anywhere else pass through untouched.",
                    isOn: Bindable(model).middleClickPasteEnabled
                )
                SettingToggle(
                    "Three-finger click pastes the latest selection",
                    caption: "Press the trackpad with three fingers — a light tap is not enough. Experimental.",
                    isOn: Bindable(model).threeFingerClickEnabled
                )
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
