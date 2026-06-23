import GrimoraCore
import SwiftUI

struct SearchContentView: View {
    @ObservedObject var gridZoom: GridZoomController
    #if os(macOS)
    @ObservedObject var searchFocus: GrimoraSearchFocusController
    #endif
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }
    var onCreateListFromSearch: () -> Void

    @EnvironmentObject private var model: GrimoraAppModel
    @AppStorage(GrimoraSearchPreferences.advancedSearchEnabledKey)
    private var advancedSearchEnabled = GrimoraSearchPreferences.defaultAdvancedSearchEnabled
    @State private var advancedSearchBuilder = AdvancedSearchBuilder()
    @State private var isAdvancedSearchPresented = false

    var body: some View {
        platformContent
            .overlay(alignment: .bottomLeading) {
                if advancedSearchEnabled {
                    AdvancedSearchLaunchButton {
                        isAdvancedSearchPresented = true
                    }
                    .padding(.leading)
                    .padding(.bottom, 12)
                }
            }
            .sheet(isPresented: $isAdvancedSearchPresented) {
                AdvancedSearchSheet(builder: $advancedSearchBuilder) { builder in
                    Task { await model.applyAdvancedSearch(builder) }
                }
            }
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
            onCreateListFromSearch: onCreateListFromSearch
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
    @ObservedObject var gridZoom: GridZoomController
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
    @ObservedObject var gridZoom: GridZoomController
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
