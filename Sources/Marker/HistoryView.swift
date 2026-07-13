import SwiftUI

struct HistoryView: View {
    private var model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filterBundleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            Divider()
            footer
        }
        .frame(width: 360)
    }

    static let accent = Color(red: 0.91, green: 0.46, blue: 0.05)

    // MARK: - Header (search + filter is the header)

    private var header: some View {
        HStack(spacing: 8) {
            searchField
            appFilter
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var appFilter: some View {
        Menu {
            Picker("Filter", selection: $filterBundleID) {
                Text("All Apps").tag(String?.none)
                Divider()
                ForEach(model.history.apps, id: \.bundleID) { app in
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: AppIcons.icon(for: app.bundleID))
                    }
                    .tag(String?.some(app.bundleID))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: filterBundleID == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(filterBundleID == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Self.accent))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
            ContentUnavailableView {
                Label("Accessibility Access Needed", systemImage: "hand.raised")
            } description: {
                Text("Marker needs Accessibility access to see text selections.")
            } actions: {
                Button("Open System Settings") {
                    model.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 180)
        } else if model.history.items.isEmpty {
            ContentUnavailableView(
                "No Selections Yet",
                systemImage: "character.cursor.ibeam",
                description: Text("Select text in any app. It lands here.")
            )
            .frame(minHeight: 160)
        } else if filteredItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(minHeight: 160)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.items) { item in
                                HistoryRow(item: item) {
                                    Paster.copyToClipboard(item.text)
                                    dismiss()
                                }
                            }
                        } header: {
                            Text(dayTitle(group.day))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.regularMaterial)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 420)
        }
    }

    // MARK: - Footer (hint + gear menu)

    private var footer: some View {
        HStack {
            Text("⌥V pastes latest")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Menu {
                Toggle("Copy to Clipboard", isOn: Bindable(model).copyToClipboardEnabled)
                    .help("Place every captured selection on the system clipboard. Off: selections stay in Marker only.")
                Toggle("Show Popup", isOn: Bindable(model).toastEnabled)
                Toggle("Start at Login", isOn: Bindable(model).launchAtLogin)
                Divider()
                Button("Clear History…") { model.history.clear() }
                    .disabled(model.history.items.isEmpty)
                Divider()
                Button("Check for Updates…") { model.checkForUpdates() }
                Button("Quit Marker") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
                    .resizable()
                    .frame(width: 20, height: 20)
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
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}