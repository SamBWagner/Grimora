#if os(macOS)
import GrimoraCore
import SwiftUI

struct MacSearchContentView: View {
    var gridZoom: GridZoomController
    var searchFocus: GrimoraSearchFocusController
    @State private var isScrolledPastHeader = false
    @State private var isSearchFocused = false
    @State private var fieldFocusRequestID = 0
    @State private var handledSceneFocusRequestID = 0
    @State private var searchSelectionClearRequestID = 0
    @State private var allowsScrollCollapseWhileFocused = true
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void
    var onCreateListFromSearch: () -> Void

    private static let hiddenToolbarOverlap: CGFloat = 56

    private var isHeaderExpanded: Bool {
        !isScrolledPastHeader || isSearchFocused
    }

    var body: some View {
        ZStack(alignment: .top) {
            ResultsContentView(
                gridZoom: gridZoom,
                showsSearchLoadingOverlay: false,
                showsPlainTextSearchStatusOverlay: false,
                searchHeaderTopInset: MacSearchFloatingHeader.expandedContentInset - Self.hiddenToolbarOverlap,
                searchSelectionClearRequestID: searchSelectionClearRequestID,
                onSearchScrollTriggerChange: updateSearchHeaderScrollState,
                onSelect: onSelect,
                onCreateListForCard: onCreateListForCard,
                onCreateListForCards: onCreateListForCards
            )

            MacSearchFloatingHeader(
                isExpanded: isHeaderExpanded,
                isSearchFocused: $isSearchFocused,
                focusRequestID: fieldFocusRequestID,
                onCreateListFromSearch: onCreateListFromSearch,
                onMouseDown: requestSearchSelectionClear,
                onSearchActivated: requestFocusedHeaderExpansion
            )
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .offset(y: -Self.hiddenToolbarOverlap)
        }
        .onAppear {
            handleSceneFocusRequestIfNeeded()
            requestFieldFocus()
        }
        .onChange(of: searchFocus.focusRequestID) { _, _ in
            handleSceneFocusRequestIfNeeded()
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            if !isFocused {
                allowsScrollCollapseWhileFocused = true
            }
        }
        .onExitCommand {
            isSearchFocused = false
            allowsScrollCollapseWhileFocused = true
        }
    }

    private func requestSearchSelectionClear() {
        searchSelectionClearRequestID += 1
    }

    private func requestFieldFocus() {
        isSearchFocused = true
        fieldFocusRequestID += 1
    }

    private func requestFocusedHeaderExpansion() {
        allowsScrollCollapseWhileFocused = false
        requestFieldFocus()
    }

    private func updateSearchHeaderScrollState(_ trigger: MacSearchHeaderScrollTrigger) {
        switch trigger {
        case .hold:
            return

        case .expand:
            guard isScrolledPastHeader else {
                return
            }

            isScrolledPastHeader = false

        case .collapse:
            guard !isScrolledPastHeader || isSearchFocused else {
                return
            }

            if isSearchFocused && !allowsScrollCollapseWhileFocused {
                return
            }

            isScrolledPastHeader = true
            if isSearchFocused {
                isSearchFocused = false
            }
        }
    }

    private func handleSceneFocusRequestIfNeeded() {
        guard searchFocus.focusRequestID != handledSceneFocusRequestID else {
            return
        }

        handledSceneFocusRequestID = searchFocus.focusRequestID
        focusSearchFromShortcut()
    }

    private func focusSearchFromShortcut() {
        requestFieldFocus()
    }

}
#endif
