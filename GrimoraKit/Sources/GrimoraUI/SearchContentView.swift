import GrimoraCore
import SwiftUI

struct SearchContentView: View {
    var gridZoom: GridZoomController
    #if os(macOS)
    var searchFocus: GrimoraSearchFocusController
    #endif
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }
    var onCreateListFromSearch: () -> Void

    // Touch platforms surface Advanced Search from the search tab's top toolbar
    // (see `TouchRootView`); only macOS keeps the in-content launch button + sheet.
    // On macOS the feature is always available — through the search-field button
    // and the ⇧⌘F menu command — rather than gated behind a setting, so it stays
    // discoverable.
    #if os(macOS)
    @Environment(GrimoraAppModel.self) private var model
    @State private var advancedSearchBuilder = AdvancedSearchBuilder()
    @State private var isAdvancedSearchPresented = false
    #endif

    var body: some View {
        #if os(macOS)
        platformContent
            .sheet(isPresented: $isAdvancedSearchPresented) {
                AdvancedSearchSheet(builder: $advancedSearchBuilder) { builder in
                    Task { await model.applyAdvancedSearch(builder) }
                } onReset: {
                    model.clearSearch()
                }
            }
            .onChange(of: searchFocus.advancedSearchRequestID) { _, _ in
                isAdvancedSearchPresented = true
            }
        #else
        platformContent
        #endif
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        MacSearchContentView(
            gridZoom: gridZoom,
            searchFocus: searchFocus,
            onSelect: onSelect,
            onCreateListForCard: onCreateListForCard,
            onCreateListForCards: onCreateListForCards,
            onCreateListFromSearch: onCreateListFromSearch,
            onOpenAdvancedSearch: { isAdvancedSearchPresented = true }
        )
        #elseif os(visionOS)
        VisionSearchContentView(
            gridZoom: gridZoom,
            onSelect: onSelect,
            onCreateListForCard: onCreateListForCard,
            onCreateListForCards: onCreateListForCards
        )
        #elseif os(iOS)
        PhoneSearchContentView(
            gridZoom: gridZoom,
            onSelect: onSelect,
            onCreateListForCard: onCreateListForCard,
            onCreateListForCards: onCreateListForCards
        )
        #endif
    }
}

#if os(visionOS)
private struct VisionSearchContentView: View {
    var gridZoom: GridZoomController
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void

    var body: some View {
        ResultsContentView(
            gridZoom: gridZoom,
            searchHeaderTopInset: 0,
            onSelect: onSelect,
            onCreateListForCard: onCreateListForCard,
            onCreateListForCards: onCreateListForCards
        )
    }
}
#endif

#if os(iOS)
private struct PhoneSearchContentView: View {
    var gridZoom: GridZoomController
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void

    var body: some View {
        ResultsContentView(
            gridZoom: gridZoom,
            searchHeaderTopInset: 0,
            onSelect: onSelect,
            onCreateListForCard: onCreateListForCard,
            onCreateListForCards: onCreateListForCards
        )
    }
}
#endif
