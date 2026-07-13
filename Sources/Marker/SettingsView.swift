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
                Toggle("Forget selections you immediately edit", isOn: Bindable(model).retractEditedEnabled)
                Text("Selecting text and typing over it is editing, not copying — such captures are removed from history.")
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
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Marker")
                .font(.title2.weight(.semibold))
            Text("Select text. It's already copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Link("Website", destination: URL(string: "https://getmarkerapp.net")!)
                Link("GitHub", destination: URL(string: "https://github.com/Mazide/marker")!)
                Link("Privacy", destination: URL(string: "https://getmarkerapp.net/privacy/")!)
            }
            .font(.callout)

            Button("Check for Updates…") {
                AppModel.shared.checkForUpdates()
            }
            .padding(.top, 2)

            Text("MIT-licensed. No analytics, no telemetry.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private extension Text {
    func settingsCaption() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}