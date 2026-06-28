#if os(iOS) || os(visionOS)
import GrimoraCore
import SwiftUI

/// Bottom-corner floating controls for the Cards tab.
///
/// On compact width (iPhone) the settings cog parks in the bottom-leading
/// corner, flanking the floating tab bar so the centre stays clear for cards.
/// On regular width (iPad / visionOS) it rests on the trailing side.
struct SearchFloatingControls: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var onOpenSearchSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if horizontalSizeClass == .regular {
                Spacer(minLength: 0)
                SearchSettingsMenu(onOpenSearchSettings: onOpenSearchSettings)
            } else {
                SearchSettingsMenu(onOpenSearchSettings: onOpenSearchSettings)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The bottom-corner cog. Surfaces library-maintenance actions and app settings
/// directly — previously these were buried behind a nested "More" flyout inside
/// a busier options menu. Sort/printing/zoom moved up to the toolbar, leaving
/// the cog a focused settings affordance.
struct SearchSettingsMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var feedbackTrigger = 0

    var onOpenSearchSettings: () -> Void

    var body: some View {
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
            Image(systemName: "gearshape")
                .floatingCircleChrome(palette: palette)
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("search-options-menu")
        .help("Settings")
        .grimoraSelectionFeedback(trigger: feedbackTrigger)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

/// Result-display options (sort, order, printings, zoom) presented in the top
/// trailing toolbar alongside search history and advanced search — grouped with
/// the other controls that shape what the results look like.
struct SearchViewOptionsMenu: View {
    @Environment(GrimoraAppModel.self) private var model
    var gridZoom: GridZoomController
    @State private var feedbackTrigger = 0

    var body: some View {
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
            Label("View Options", systemImage: "square.grid.2x2")
        }
        .accessibilityIdentifier("search-view-options-menu")
        .help("View Options")
        .grimoraSelectionFeedback(trigger: feedbackTrigger)
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
    // Live camera card recognition. Only surfaced on iOS (iPhone/iPad); the
    // case exists on visionOS too so switches stay exhaustive, but no tab is
    // added there (consumer apps can't read the Vision Pro camera feed).
    case scry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search:
            "Cards"
        case .lists:
            "Collections"
        case .scry:
            "Scry"
        }
    }

    var systemImage: String {
        switch self {
        case .search:
            "magnifyingglass"
        case .lists:
            "list.bullet.rectangle"
        case .scry:
            "eye"
        }
    }
}
#endif
