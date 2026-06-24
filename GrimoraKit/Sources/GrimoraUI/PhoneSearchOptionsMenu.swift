#if os(iOS) || os(visionOS)
import GrimoraCore
import SwiftUI

struct SearchOptionsMenu: View {
    @EnvironmentObject private var model: GrimoraAppModel
    var gridZoom: GridZoomController
    @State private var feedbackTrigger = 0

    var onCreateListFromSearch: () -> Void
    var onOpenSearchSettings: () -> Void

    var body: some View {
        Menu {
            viewOptionsMenu
            libraryMenu

            Button {
                feedbackTrigger += 1
                onCreateListFromSearch()
            } label: {
                Text("Create List")
            }
            .accessibilityIdentifier("create-list-from-search-button")
            .disabled(!model.canCreateListFromCurrentSearch)

            Button {
                feedbackTrigger += 1
                model.clearSearch()
            } label: {
                Text("Clear Search")
            }
            .accessibilityIdentifier("clear-search-button")
            .disabled(!model.canClearSearch)

            Button {
                feedbackTrigger += 1
                onOpenSearchSettings()
            } label: {
                Text("Search Settings")
            }
            .accessibilityIdentifier("search-settings-button")
        } label: {
            searchOptionsMenuLabel
        }
        .accessibilityLabel("Search Options")
        .accessibilityIdentifier("search-options-menu")
        .help("Search Options")
        .grimoraSelectionFeedback(trigger: feedbackTrigger)
    }

    @ViewBuilder
    private var searchOptionsMenuLabel: some View {
        Label("Search Options", systemImage: "ellipsis")
            .labelStyle(.iconOnly)
            .imageScale(.large)
    }

    private var viewOptionsMenu: some View {
        Menu {
            Section("Sort") {
                sortButtons
            }

            Section("Order") {
                orderButtons
            }

            Section("Printings") {
                printingModeButtons
            }

            if GridZoomAvailability.isSupported {
                Section("Zoom") {
                    gridZoomButtons
                }
            }
        } label: {
            Text("View Options")
        }
        .accessibilityIdentifier("search-view-options-menu")
    }

    private var libraryMenu: some View {
        Menu {
            LibraryMaintenanceMenuItems()
        } label: {
            Text("Library")
        }
        .accessibilityIdentifier("library-maintenance-menu")
    }

    private var sortButtons: some View {
        ForEach(SortMode.allCases) { mode in
            Button {
                feedbackTrigger += 1
                model.sortMode = mode
            } label: {
                GrimoraMenuSelectionLabel(title: mode.title, isSelected: model.sortMode == mode)
            }
            .accessibilityIdentifier("search-sort-option-\(mode.rawValue)")
        }
    }

    private var orderButtons: some View {
        ForEach(searchSortDirections, id: \.self) { direction in
            Button {
                feedbackTrigger += 1
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

    private var printingModeButtons: some View {
        ForEach(PrintingDisplayMode.allCases) { mode in
            Button {
                feedbackTrigger += 1
                model.printingDisplayMode = mode
            } label: {
                GrimoraMenuSelectionLabel(
                    title: mode.title,
                    isSelected: model.printingDisplayMode == mode
                )
            }
            .accessibilityIdentifier("printing-mode-\(mode.rawValue)")
        }
    }

    private var gridZoomButtons: some View {
        Group {
            Button {
                feedbackTrigger += 1
                gridZoom.zoomOut()
            } label: {
                Text("Zoom Out")
            }
            .accessibilityIdentifier("grid-zoom-out-button")
            .disabled(!gridZoom.canZoomOut)

            Button {
                feedbackTrigger += 1
                gridZoom.zoomIn()
            } label: {
                Text("Zoom In")
            }
            .accessibilityIdentifier("grid-zoom-in-button")
            .disabled(!gridZoom.canZoomIn)

            Button {
                feedbackTrigger += 1
                gridZoom.reset()
            } label: {
                Text("Actual Size")
            }
            .accessibilityIdentifier("grid-zoom-reset-button")
            .disabled(!gridZoom.canReset)
        }
    }

    private var searchSortDirections: [SearchSortDirection] {
        [.ascending, .descending]
    }

}

enum TouchRootTab: String, CaseIterable, Identifiable {
    case search
    case lists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search:
            "Search"
        case .lists:
            "Lists"
        }
    }

    var systemImage: String {
        switch self {
        case .search:
            "magnifyingglass"
        case .lists:
            "list.bullet.rectangle"
        }
    }
}
#endif
