import GrimoraCore
import SwiftUI

struct SearchToolbarButtons: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var createFeedbackTrigger = 0
    @State private var clearFeedbackTrigger = 0
    @State private var updateFeedbackTrigger = 0

    var onCreateListFromSearch: () -> Void

    var body: some View {
        Button {
            createFeedbackTrigger += 1
            onCreateListFromSearch()
        } label: {
            Text("Create List")
        }
        .accessibilityIdentifier("create-list-from-search-button")
        .disabled(!model.canCreateListFromCurrentSearch)
        .grimoraSelectionFeedback(trigger: createFeedbackTrigger)

        Button {
            clearFeedbackTrigger += 1
            model.clearSearch()
        } label: {
            Text("Clear Search")
        }
        .accessibilityIdentifier("clear-search-button")
        .disabled(!model.canClearSearch)
        .grimoraSelectionFeedback(trigger: clearFeedbackTrigger)

        Button {
            updateFeedbackTrigger += 1
            Task { await model.checkForUpdates() }
        } label: {
            Text("Check for Updates")
        }
        .accessibilityIdentifier("check-updates-button")
        .disabled(model.isWorking)
        .grimoraSelectionFeedback(trigger: updateFeedbackTrigger)
    }
}

struct SearchRefinementToolbar: ToolbarContent {
    var placement: ToolbarItemPlacement
    var usesCompactActions = false
    var onCreateListFromSearch: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            SearchSortMenu()
            SearchFiltersMenu()
            SearchPrintingsToggle()

            if usesCompactActions {
                SearchActionsMenu(onCreateListFromSearch: onCreateListFromSearch)
            } else {
                SearchToolbarButtons(onCreateListFromSearch: onCreateListFromSearch)
            }
        }
    }
}

struct SearchSortMenu: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var body: some View {
        Menu {
            Section("Sort") {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        model.sortMode = mode
                    } label: {
                        GrimoraMenuSelectionLabel(title: mode.title, isSelected: model.sortMode == mode)
                    }
                    .accessibilityIdentifier("search-sort-option-\(mode.rawValue)")
                }
            }

            Section("Order") {
                ForEach(searchSortDirections, id: \.self) { direction in
                    Button {
                        model.sortDirection = direction
                    } label: {
                        GrimoraMenuSelectionLabel(
                            title: GrimoraSearchPreferences.directionTitle(direction, for: model.sortMode),
                            isSelected: model.sortDirection == direction
                        )
                    }
                    .accessibilityIdentifier("search-sort-direction-option-\(direction.rawValue)")
                }
            }
        } label: {
            Text("Sort")
        }
        .accessibilityIdentifier("search-sort-menu")
        .help("Sort search results")
    }

    private var searchSortDirections: [SearchSortDirection] {
        [.ascending, .descending]
    }

}

struct SearchFiltersMenu: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var body: some View {
        Menu {
            ForEach(FilterPreset.allCases) { filter in
                Button {
                    model.toggleFilter(filter)
                } label: {
                    HStack {
                        Text(filter.title)
                        if model.activeFilters.contains(filter) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier(filter.accessibilityIdentifier)
            }
        } label: {
            Text("Filters")
        }
        .accessibilityIdentifier("search-filter-menu")
        .help("Filter search results")
    }
}

struct SearchPrintingsToggle: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var feedbackTrigger = 0

    var body: some View {
        Button {
            feedbackTrigger += 1
            model.printingDisplayMode = isShowingAllPrintings ? .preferred : .all
        } label: {
            Text("All Printings")
        }
        .accessibilityIdentifier("all-printings-toggle")
        .accessibilityValue(isShowingAllPrintings ? "On" : "Off")
        .help(isShowingAllPrintings ? "Showing all printings" : "Showing preferred printings")
        .grimoraSelectionFeedback(trigger: feedbackTrigger)
    }

    private var isShowingAllPrintings: Bool {
        model.printingDisplayMode == .all
    }
}

struct SearchActionsMenu: View {
    @EnvironmentObject private var model: GrimoraAppModel
    var onCreateListFromSearch: () -> Void

    var body: some View {
        Menu {
            SearchToolbarButtons(onCreateListFromSearch: onCreateListFromSearch)
        } label: {
            Text("Search Actions")
        }
        .accessibilityIdentifier("search-actions-menu")
        .help("Search actions")
    }
}
