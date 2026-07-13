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
                    caption: "Every selection lands on the system clipboard, ready to ⌘V. Off: selections stay in Marker's history only, and ⌥V pastes the latest.",
                    isOn: Bindable(model).copyToClipboardEnabled
                )
                SettingToggle(
                    "Ignore selections you immediately edit",
                    caption: "In editable fields Marker waits half a second before saving. Type over the selection in that window and nothing is captured.",
                    isOn: Bindable(model).retractEditedEnabled
                )
                SettingToggle(
                    "Never save secrets",
                    caption: "API keys, tokens and private keys still reach your clipboard, but are kept out of history.",
                    isOn: Bindable(model).skipSecretsEnabled
                )
            }

            Section("Paste") {
                SettingToggle(
                    "Middle-click pastes the latest selection",
                    caption: "Works over text fields; clicks anywhere else pass through untouched.",
                    isOn: Bindable(model).middleClickPasteEnabled
                )
                SettingToggle(
                    "Three-finger tap pastes the latest selection",
                    caption: "The trackpad equivalent of middle-click. Experimental.",
                    isOn: Bindable(model).threeFingerTapEnabled
                )
            }

            Section("Interface") {
                Toggle("Show a popup on capture", isOn: Bindable(model).toastEnabled)
                Toggle("Start at login", isOn: Bindable(model).launchAtLogin)
            }

            Section("History") {
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
    let title: String
    let caption: String
    @Binding var isOn: Bool

    init(_ title: String, caption: String, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
