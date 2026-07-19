import AppIntents

/// Marker's automation surface: Shortcuts, Spotlight, Siri, and anything
/// that can run a shortcut (Raycast, Alfred). The GUI-less counterpart of
/// marker-cli — same reads, but in-process and typed.

enum MarkerIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyHistory
    case notEnoughEntries(available: Int)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyHistory:
            return "Marker's history is empty."
        case .notEnoughEntries(let available):
            return "Only \(available) entries in Marker's history."
        }
    }
}

struct GetLatestSelectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Selection"
    static let description = IntentDescription(
        "Returns the text of the most recent selection in Marker's history.",
        categoryName: "History"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        AppModel.shared.history.refresh()
        guard let item = AppModel.shared.history.items.first else {
            throw MarkerIntentError.emptyHistory
        }
        return .result(value: item.text)
    }
}

struct SearchHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search History"
    static let description = IntentDescription(
        "Case-insensitive search over captured selections and their source app names; returns matching texts, newest first.",
        categoryName: "History"
    )

    @Parameter(title: "Query") var query: String
    @Parameter(title: "Limit", default: 20, inclusiveRange: (1, 200)) var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search history for \(\.$query)") {
            \.$limit
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let items = AppModel.shared.history.search(text: query, bundleID: nil)
        return .result(value: items.prefix(limit).map(\.text))
    }
}

struct CopyEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Entry to Clipboard"
    static let description = IntentDescription(
        "Puts a history entry on the system clipboard, with its rich-text flavors intact. Position 1 is the newest entry.",
        categoryName: "History"
    )

    @Parameter(title: "Position", default: 1, inclusiveRange: (1, 200)) var position: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Copy entry \(\.$position) to the clipboard")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        AppModel.shared.history.refresh()
        let items = AppModel.shared.history.items
        guard items.count >= position else {
            throw MarkerIntentError.notEnoughEntries(available: items.count)
        }
        let item = items[position - 1]
        AppModel.shared.copyToClipboard(item)
        return .result(value: item.text)
    }
}

struct MarkerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetLatestSelectionIntent(),
            phrases: ["Get the latest selection from \(.applicationName)"],
            shortTitle: "Latest Selection",
            systemImageName: "highlighter"
        )
        AppShortcut(
            intent: SearchHistoryIntent(),
            phrases: ["Search \(.applicationName) history"],
            shortTitle: "Search History",
            systemImageName: "magnifyingglass"
        )
    }
}
