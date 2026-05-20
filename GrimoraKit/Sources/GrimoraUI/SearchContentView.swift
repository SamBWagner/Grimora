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

    var body: some View {
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
