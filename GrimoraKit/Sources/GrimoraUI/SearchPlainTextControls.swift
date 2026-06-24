import GrimoraCore
import SwiftUI

enum MacSearchHeaderScrollTrigger: Equatable {
    case expand
    case hold
    case collapse

    static let expandThreshold: CGFloat = 8
    static let collapseThreshold: CGFloat = 48

    init(contentOffsetY: CGFloat) {
        let offsetY = max(0, contentOffsetY)
        if offsetY <= Self.expandThreshold {
            self = .expand
        } else if offsetY >= Self.collapseThreshold {
            self = .collapse
        } else {
            self = .hold
        }
    }

    init(legacyContentMinY: CGFloat) {
        self.init(contentOffsetY: -legacyContentMinY)
    }
}

struct SearchHistorySuggestions: View {
    var searchText: String
    var history: [String]
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        ForEach(filteredHistory, id: \.self) { query in
            Button {
                onSelect(query)
            } label: {
                Label(query, systemImage: "clock.arrow.circlepath")
            }
            .searchCompletion(query)
            .accessibilityIdentifier("search-history-suggestion-\(query)")
        }
    }

    private var filteredHistory: [String] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return history
        }

        return history.filter {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Dedicated recent-searches affordance for touch platforms, mirroring the
/// native recents menu macOS gets from `NSSearchField`. The `.searchSuggestions`
/// dropdown only appears while the field is focused and offers no way to clear
/// history, so this surfaces the same list (plus a clear action) from a toolbar
/// button. History selection and clearing follow the active search input mode
/// via `GrimoraAppModel`.
struct SearchHistoryMenu: View {
    @Environment(GrimoraAppModel.self) private var model
    @State private var feedbackTrigger = 0

    /// Applies a recent query to the search field and runs it.
    var onSelect: (String) -> Void

    var body: some View {
        Menu {
            SearchHistoryMenuContent(
                history: model.visibleSearchHistory,
                onSelect: { query in
                    feedbackTrigger += 1
                    onSelect(query)
                },
                onClear: {
                    feedbackTrigger += 1
                    model.clearSearchHistory()
                }
            )
        } label: {
            Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                .labelStyle(.iconOnly)
                .imageScale(.large)
        }
        .accessibilityLabel("Recent Searches")
        .accessibilityIdentifier("search-history-menu")
        .help("Recent Searches")
        .disabled(model.visibleSearchHistory.isEmpty)
        .grimoraSelectionFeedback(trigger: feedbackTrigger)
    }
}

struct SearchHistoryMenuContent: View {
    var history: [String]
    var onSelect: (String) -> Void
    var onClear: () -> Void

    var body: some View {
        if history.isEmpty {
            Text("No Recent Searches")
                .accessibilityIdentifier("search-history-empty")
        } else {
            Section("Recent Searches") {
                ForEach(history, id: \.self) { query in
                    Button {
                        onSelect(query)
                    } label: {
                        Label(query, systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("search-history-menu-item-\(query)")
                }
            }

            Section {
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear Recent Searches", systemImage: "trash")
                }
                .accessibilityIdentifier("clear-search-history-button")
            }
        }
    }
}

struct SearchInputModeToggle: View {
    @Environment(GrimoraAppModel.self) private var model

    var body: some View {
        Button {
            model.togglePlainTextSearchMode()
        } label: {
            Label(accessibilityLabel, systemImage: searchAISymbolName)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityIdentifier("plain-text-search-mode-toggle")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .disabled(!model.isPlainTextSearchAvailable && !model.isPlainTextSearchModeActive)
        .help(helpText)
    }

    private var accessibilityLabel: String {
        model.isPlainTextSearchModeActive ? "Disable Plain Text Search" : "Enable Plain Text Search"
    }

    private var accessibilityValue: String {
        if model.isPlainTextSearchModeActive {
            return "On"
        }
        if let unavailableMessage = model.plainTextSearchUnavailableMessage {
            return unavailableMessage
        }
        return "Off"
    }

    private var helpText: String {
        if let unavailableMessage = model.plainTextSearchUnavailableMessage,
           !model.isPlainTextSearchModeActive {
            return unavailableMessage
        }
        return model.isPlainTextSearchModeActive ? "Using plain-text search" : "Use plain-text search"
    }
}

struct PlainTextSearchStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model

    var body: some View {
        if model.isPlainTextSearchModeActive {
            statusContent
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if model.isTranslatingSearch {
            statusLabel("Translating", systemImage: searchAISymbolName)
                .accessibilityIdentifier("plain-text-search-translating")
        } else if let message = model.plainTextSearchErrorMessage {
            statusLabel(message, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("plain-text-search-error")
        } else if let query = model.generatedSearchQuery {
            statusLabel(query, systemImage: "curlybraces")
                .accessibilityIdentifier("plain-text-generated-query")
        }
    }

    private func statusLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText.color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

var searchAISymbolName: String {
    #if os(macOS)
    if #available(macOS 26.0, *) {
        return "apple.intelligence"
    }
    return "atom"
    #elseif os(iOS)
    if #available(iOS 26.0, *) {
        return "apple.intelligence"
    }
    return "sparkles"
    #elseif os(visionOS)
    if #available(visionOS 26.0, *) {
        return "apple.intelligence"
    }
    return "sparkles"
    #else
    return "sparkles"
    #endif
}
