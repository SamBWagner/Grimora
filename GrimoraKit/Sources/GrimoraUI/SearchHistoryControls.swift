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
/// button.
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
