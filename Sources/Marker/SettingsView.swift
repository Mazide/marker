import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440)
    }
}

private struct GeneralSettingsView: View {
    private var model = AppModel.shared

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Copy selections to the clipboard", isOn: Bindable(model).copyToClipboardEnabled)
                Text("Every selection lands on the system clipboard, ready to ⌘V. Off: selections stay in Marker's history only, and ⌥V pastes the latest.")
                    .settingsCaption()
                Toggle("Ignore selections you immediately edit", isOn: Bindable(model).retractEditedEnabled)
                Text("In editable fields Marker waits half a second before saving a selection. If you type over it in that window, nothing is captured.")
                    .settingsCaption()
                Toggle("Never save secrets", isOn: Bindable(model).skipSecretsEnabled)
                Text("API keys, tokens and private keys still reach your clipboard, but are kept out of history.")
                    .settingsCaption()
            }
            Section("Paste") {
                Toggle("Middle-click pastes the latest selection", isOn: Bindable(model).middleClickPasteEnabled)
                Toggle("Three-finger tap pastes the latest selection", isOn: Bindable(model).threeFingerTapEnabled)
                Text("Both work only over text fields; clicks elsewhere pass through. Three-finger tap is experimental.")
                    .settingsCaption()
            }
            Section("Interface") {
                Toggle("Show a popup on capture", isOn: Bindable(model).toastEnabled)
                Toggle("Start at login", isOn: Bindable(model).launchAtLogin)
            }
            Section("History") {
                LabeledContent("Remove all captured selections") {
                    Button("Clear History…", role: .destructive) {
                        model.history.clear()
                    }
                    .disabled(model.history.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 4)
    }
}

private struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.25), radius: 9, y: 4)
                .padding(.bottom, 10)
            Text("Marker")
                .font(.title2.weight(.semibold))
            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text("Select text. It's already copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Divider()
                .frame(width: 220)
                .padding(.vertical, 14)

            HStack(spacing: 18) {
                Link("Website", destination: URL(string: "https://getmarkerapp.net")!)
                Link("GitHub", destination: URL(string: "https://github.com/Mazide/marker")!)
                Link("Privacy", destination: URL(string: "https://getmarkerapp.net/privacy/")!)
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button("Check for Updates…") {
                    AppModel.shared.checkForUpdates()
                }
                Button("Quit Marker") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.top, 12)

            Text("MIT-licensed. No analytics, no telemetry.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }
}

private extension Text {
    func settingsCaption() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}