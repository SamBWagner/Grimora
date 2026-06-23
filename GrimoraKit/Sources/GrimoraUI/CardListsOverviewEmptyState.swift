import SwiftUI

/// Empty state for the dashboard grid: a no-matches state while a cross-list
/// search is active, otherwise the first-run "No Lists" prompt.
struct CardListsOverviewEmptyState: View {
    var hasActiveSearch: Bool
    var searchText: String

    @ViewBuilder
    var body: some View {
        if hasActiveSearch {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityIdentifier("dashboard-search-no-matches")
        } else {
            ContentUnavailableView("No Lists", systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityIdentifier("empty-lists-overview")
        }
    }
}
