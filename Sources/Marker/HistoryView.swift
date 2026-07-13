import SwiftUI

struct HistoryView: View {
    private var model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filterBundleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Marker")
                    .font(.headline)
                Spacer()
                Text("⌥V pastes latest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                searchField
                appFilter
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
    }

    private var appFilter: some View {
        Menu {
            Button("All apps") { filterBundleID = nil }
            Divider()
            ForEach(model.history.apps, id: \.bundleID) { app in
                Button {
                    filterBundleID = app.bundleID
                } label: {
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: AppIcons.icon(for: app.bundleID))
                    }
                }
            }
        } label: {
            if let filterBundleID {
                Image(nsImage: AppIcons.icon(for: filterBundleID))
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by app")
    }

    // MARK: - List

    private var filteredItems: [SelectionItem] {
        model.history.items.filter { item in
            if let filterBundleID, item.bundleID != filterBundleID { return false }
            if !searchText.isEmpty,
               !item.text.localizedCaseInsensitiveContains(searchText),
               !item.appName.localizedCaseInsensitiveContains(searchText) { return false }
            return true
        }
    }

    private var dayGroups: [(day: Date, items: [SelectionItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredItems) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder
    private var content: some View {
        if !model.axTrusted {
            VStack(spacing: 8) {
                Text("Marker needs Accessibility access to see text selections.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Button("Open System Settings") {
                    model.openAccessibilitySettings()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        } else if model.history.items.isEmpty {
            Text("Select text in any app — it lands here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
        } else if filteredItems.isEmpty {
            Text("Nothing matches.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(dayGroups, id: \.day) { group in
                        Text(dayTitle(group.day))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(group.items) { item in
                            HistoryRow(item: item) {
                                Paster.copyToClipboard(item.text)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 420)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Toggle("To clipboard", isOn: Bindable(model).copyToClipboardEnabled)
                    .help("Also place every captured selection on the system clipboard (classic auto-copy). Off = history only, your clipboard stays untouched.")
                Toggle("Popup", isOn: Bindable(model).toastEnabled)
                Toggle("Start at login", isOn: Bindable(model).launchAtLogin)
                Spacer()
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            HStack {
                Button("Clear") {
                    model.history.clear()
                }
                .disabled(model.history.items.isEmpty)
                Spacer()
                Button("Updates…") {
                    model.checkForUpdates()
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct HistoryRow: View {
    let item: SelectionItem
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: AppIcons.icon(for: item.bundleID))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(item.appName)
                        Text("·")
                        Text(item.date, format: .dateTime.hour().minute())
                        if isHovered {
                            Spacer()
                            Text("Click to copy")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear)
        .onHover { isHovered = $0 }
    }
}