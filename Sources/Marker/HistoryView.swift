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
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
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
                                        model.copyToClipboard(item)
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
                                // Aligns with the row's app icon: 6pt pill
                                // inset + 8pt content inset.
                                .padding(.horizontal, 14)
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
                Button("Settings…") {
                    openSettings()
                }
                .keyboardShortcut(",")
                Button("Check for Updates…") {
                    model.checkForUpdates()
                }
                Divider()
                // The app has no Dock icon and no main menu (LSUIElement);
                // without this item there is no way to quit it at all.
                Button("Quit Marker") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    // The glyph is 13pt; the row is short, so the button
                    // needs its own hit area to be comfortably clickable.
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings, updates, quit")
            .accessibilityLabel("Settings and app actions")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
    }
}

private struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
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

/// One captured selection. Three columns, one surface: app icon · snippet ·
/// time. The row highlight is the only rounded rect — the text sits directly
/// on it, the way a Finder or Spotlight row does.
private struct HistoryRow: View {
    let item: SelectionItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    /// Line box of the snippet's first line — the vertical anchor the icon
    /// and the timestamp are centered on.
    private var firstLineHeight: CGFloat {
        isCodeLike ? 16 : 18
    }

    /// Prose is collapsed to a single run so every row has the same shape.
    /// Code keeps its line breaks (minus the source indentation) — the
    /// shape of the lines is half of what makes code readable.
    private var snippet: String {
        if isCodeLike {
            return item.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: "\n")
        }
        return item.text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Monospace for what is meant to be read as literal text — URLs,
    /// paths, identifiers, code — and the proportional face for prose.
    /// Cyrillic and English sentences look wrong in monospace, which is
    /// why this is a heuristic and not a global switch.
    private var isCodeLike: Bool {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        if text.contains("://") { return true }
        if text.hasPrefix("/") || text.hasPrefix("~/") { return true }
        if text.contains("\n"), text.contains(where: { "{};=<>()".contains($0) }) { return true }
        // A single unbroken token (identifier, hash, key, filename).
        if !text.contains(where: \.isWhitespace), text.count >= 8 { return true }

        // Dense punctuation is a good proxy for source code.
        let symbols = text.filter { "{}[]()<>;=+*/\\|&^%$#@_`~".contains($0) }.count
        return Double(symbols) / Double(text.count) > 0.08
    }

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 8) {
                // The icon *is* the source label — hence no app-name caption.
                // It is centered on the snippet's first line: baseline
                // alignment drifts because the mono and proportional faces
                // have different metrics, this does not.
                Image(nsImage: AppIcons.icon(for: item.bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .frame(height: firstLineHeight)
                    .help(item.appName)

                // Captured text: rendered like content, not chrome — the
                // list itself is the context, the way Maccy and Raycast do
                // it. Chrome around it recedes to tertiary.
                Text(snippet)
                    .font(isCodeLike
                          ? .system(.footnote, design: .monospaced)
                          : .callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(isCodeLike ? .middle : .tail)
                    .lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // One trailing slot: the timestamp lives here at rest and
                // cross-fades to the delete button on hover, so the row
                // never reflows and the actions stay pinned to the edge.
                ZStack(alignment: .trailing) {
                    Text(item.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered ? 0 : 1)

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                }
                .fixedSize()
                .frame(height: firstLineHeight)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        // The app name is gone from the visuals, so keep it in the label.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snippet), \(item.appName)")
        .accessibilityHint("Copies this selection")
    }
}