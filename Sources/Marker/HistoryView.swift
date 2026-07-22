import SwiftUI

struct HistoryView: View {
    /// The panel shell closes through its presenter, not SwiftUI dismissal.
    let onDismiss: () -> Void

    private var model = AppModel.shared
    @Environment(\.openSettings) private var openSettingsAction
    @State private var searchText = ""
    @State private var filterBundleID: String?
    @FocusState private var searchFocused: Bool
    /// Keyboard selection, Spotlight-style: the first row is preselected,
    /// arrows move it, Return pastes it — all while search keeps focus.
    @State private var selectedID: UUID?
    /// Timestamps show only while the pointer is over the list — at rest
    /// the right edge stays clean.
    @State private var listHovered = false
    /// Scroll requests come only from arrow-key navigation. Scrolling on
    /// every selectedID change also fires on the initial preselect, which
    /// shoves the first day header above the viewport.
    @State private var scrollTarget: UUID?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    private func close() {
        onDismiss()
    }

    private func openSettings() {
        close()
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560)
        // The panel window is borderless and transparent; the view paints
        // its own chrome.
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.5))
        }
        .onAppear {
            // Typing right after ⇧⌥V should land in search. The async hop
            // waits out the popover window becoming key; setting the focus
            // synchronously here is dropped.
            DispatchQueue.main.async { searchFocused = true }
            model.history.refresh()
            adoptSearchRequest()
            selectedID = filteredItems.first?.id
        }
        .onChange(of: model.popoverSearchRequest) { _, _ in adoptSearchRequest() }
        .onChange(of: searchText) { _, _ in selectedID = filteredItems.first?.id }
        .onChange(of: filterBundleID) { _, _ in selectedID = filteredItems.first?.id }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.return) { pickSelected() }
        .onKeyPress(.escape) {
            // Standard search-field staging: first Esc clears the query,
            // the next one closes the panel.
            if !searchText.isEmpty {
                searchText = ""
                return .handled
            }
            close()
            return .handled
        }
    }

    /// marker://search landed a query for the popover.
    private func adoptSearchRequest() {
        guard let query = model.popoverSearchRequest else { return }
        model.popoverSearchRequest = nil
        searchText = query
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let items = filteredItems
        guard !items.isEmpty else { return .ignored }
        let current = items.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
        scrollTarget = items[next].id
        return .handled
    }

    private func pickSelected() -> KeyPress.Result {
        guard let item = filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
        else { return .ignored }
        close()
        model.pickFromPanel(item)
        return .handled
    }

    static let accent = Color(red: 0.91, green: 0.46, blue: 0.05)

    // MARK: - Header (search + filter is the header)

    /// Spotlight-style header: the search field IS the header — no pill,
    /// a large light-weight input across the panel's full width.
    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            TextField("Search selections", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .light))
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            appFilter
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
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
                message: "Select text in any app — it lands here, ready to copy or paste."
            )
        } else if filteredItems.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Nothing selected like that. Try fewer letters or another app filter."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.items) { item in
                                HistoryRow(
                                    item: item,
                                    isSelected: item.id == selectedID,
                                    showsTime: listHovered,
                                    onPick: {
                                        close()
                                        model.pickFromPanel(item)
                                    },
                                    onCopy: {
                                        model.copyToClipboard(item)
                                        close()
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
                            // Quiet small-caps label instead of a pinned
                            // material band — the list reads as one surface.
                            Text(dayTitle(group.day).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Aligns with the row's app icon: 6pt pill
                                // inset + 8pt content inset.
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                                .padding(.bottom, 3)
                        }
                    }
                }
                .padding(.bottom, 6)
                }
                .frame(maxHeight: 400)
                .onHover { listHovered = $0 }
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                    scrollTarget = nil
                }
            }
        }
    }

    // MARK: - Footer (hint + gear menu)

    private var footer: some View {
        HStack {
            Text("↩ pastes · \(model.pasteHotkey.label) repeats it · right-click copies")
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
    let isSelected: Bool
    /// Pointer is over the list: timestamps fade in as a group.
    let showsTime: Bool
    let onPick: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    /// One shared line box: mono at 11pt sits on the same 18pt line as the
    /// 12pt proportional face, so row heights never jump while scanning.
    private let lineHeight: CGFloat = 18

    /// Everything is collapsed to a single run — one row, one line, one
    /// rhythm. Code loses its line breaks but keeps its tokens; the middle
    /// truncation preserves both ends, which carry the identity.
    private var snippet: String {
        item.text
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
        Button(action: onPick) {
            HStack(alignment: .center, spacing: 8) {
                // The icon *is* the source label — hence no app-name caption.
                // Desaturated so the content, not the chrome, is loudest.
                Image(nsImage: AppIcons.icon(for: item.bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .saturation(0.72)
                    .opacity(0.88)
                    .frame(height: lineHeight)
                    .help(item.appName)

                // Captured text: rendered like content, not chrome — the
                // list itself is the context, the way Maccy and Raycast do
                // it. Chrome around it recedes to tertiary.
                Text(snippet)
                    .font(isCodeLike
                          ? .system(size: 11, design: .monospaced)
                          : .callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(isCodeLike ? .middle : .tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // One trailing slot: the timestamp lives here when the
                // pointer is over the list and cross-fades to the actions
                // on row hover, so the row never reflows and the actions
                // stay pinned to the edge.
                ZStack(alignment: .trailing) {
                    Text(item.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .opacity(showsTime && !isHovered ? 1 : 0)

                    HStack(spacing: 8) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")

                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                }
                .fixedSize()
                .frame(height: lineHeight)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? AnyShapeStyle(HistoryView.accent.opacity(0.22))
                      : AnyShapeStyle(.quaternary))
                .opacity(isSelected || isHovered ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
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
        .accessibilityHint("Makes this what the paste hotkey inserts")
    }
}