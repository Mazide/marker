import SwiftUI

struct HistoryView: View {
    private var model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettingsAction
    @State private var searchText = ""
    @State private var filterBundleID: String?

    private func openSettings() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction()
    }

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

    private var isFiltering: Bool {
        !searchText.isEmpty || filterBundleID != nil
    }

    private var filteredItems: [SelectionItem] {
        guard isFiltering else { return model.history.items }
        // Filtered views search the whole database, not just the loaded window.
        return model.history.search(
            text: searchText.isEmpty ? nil : searchText,
            bundleID: filterBundleID
        )
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
            EmptyState(
                icon: "hand.raised.fill",
                title: "One permission needed",
                message: "Marker reads selections through macOS Accessibility. Nothing leaves your Mac.",
                actionTitle: "Open System Settings",
                action: { model.openAccessibilitySettings() }
            )
        } else if model.history.items.isEmpty {
            EmptyState(
                icon: "cursorarrow.motionlines",
                title: "Nothing here yet",
                message: "Select text in any app — it lands here, already copied."
            )
        } else if filteredItems.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Nothing selected like that. Try fewer letters or another app filter."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.items) { item in
                                HistoryRow(
                                    item: item,
                                    onCopy: {
                                        model.copyToClipboard(item.text)
                                        dismiss()
                                    },
                                    onDelete: { model.history.delete(item) }
                                )
                                .onAppear {
                                    // Infinite scroll: reaching the oldest
                                    // loaded row pulls the next page.
                                    if !isFiltering, item.id == model.history.items.last?.id {
                                        model.history.loadMore()
                                    }
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
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(HistoryView.accent)
                .frame(width: 42, height: 42)
                .background(HistoryView.accent.opacity(0.14), in: Circle())
                .padding(.bottom, 2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(HistoryView.accent)
                    .controlSize(.small)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(.vertical, 14)
    }
}

private struct HistoryRow: View {
    let item: SelectionItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: AppIcons.icon(for: item.bundleID))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    // The snippet sits on a chip so it reads as a copied
                    // fragment, not as UI text.
                    Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    HStack(spacing: 4) {
                        Text(item.appName)
                        Text("·")
                        Text(item.date, format: .dateTime.hour().minute())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)
                }
                VStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this entry")
                }
                .padding(.top, 3)
                .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .background(
            isHovered ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}