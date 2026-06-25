#if os(iOS) || os(visionOS)
import GrimoraCore
import SwiftUI

struct SearchOptionsMenu: View {
    @Environment(GrimoraAppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    var gridZoom: GridZoomController
    @State private var feedbackTrigger = 0

    var onCreateListFromSearch: () -> Void
    var onOpenSearchSettings: () -> Void

    var body: some View {
        Menu {
            viewOptionsMenu

            Button {
                feedbackTrigger += 1
                onCreateListFromSearch()
            } label: {
                Label("Create List", systemImage: "plus")
            }
            .accessibilityIdentifier("create-list-from-search-button")
            .disabled(!model.canCreateListFromCurrentSearch)

            Divider()

            moreMenu
        } label: {
            searchOptionsMenuLabel
        }
        .accessibilityLabel("Search Options")
        .accessibilityIdentifier("search-options-menu")
        .help("Search Options")
        .grimoraSelectionFeedback(trigger: feedbackTrigger)
    }

    /// Low-touch entries (library maintenance, app settings) tucked behind a
    /// "More" flyout so the frequently used actions above stay one tap away.
    /// Library items are inlined (not nested in another submenu) and rely on the
    /// section headings `LibraryMaintenanceMenuItems` already provides; Settings
    /// gets its own section so the flat list stays scannable.
    private var moreMenu: some View {
        Menu {
            LibraryMaintenanceMenuItems()

            Section("App") {
                Button {
                    feedbackTrigger += 1
                    onOpenSearchSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("search-settings-button")
            }
        } label: {
            Text("More")
        }
        .accessibilityIdentifier("search-more-menu")
    }

    private var searchOptionsMenuLabel: some View {
        Image(systemName: "gearshape")
            .floatingCircleChrome(palette: palette)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
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
