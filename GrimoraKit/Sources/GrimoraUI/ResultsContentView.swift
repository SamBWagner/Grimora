import GrimoraCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ResultsContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: GrimoraAppModel
    var gridZoom: GridZoomController
    @State private var magnificationStartScale: Double?
    @State private var showsSearchLoadingIndicator = false
    @State private var searchJumpToTopState = JumpToTopScrollState.top
    @State private var searchResultSelection = CardGridSelectionState<CardRecord.ID>()
    @State private var raisedSearchArtworkCardID: CardRecord.ID?
    @State private var landscapeSearchArtworkCardIDs: Set<CardRecord.ID> = []
    @State private var searchResultBulkSelection = SearchResultBulkSelection()
    var showsSearchLoadingOverlay = true
    var showsPlainTextSearchStatusOverlay = true
    var searchHeaderTopInset: CGFloat = 0
    var searchSelectionClearRequestID = 0
    var onSearchScrollTriggerChange: (MacSearchHeaderScrollTrigger) -> Void = { _ in }
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }

    private static let initialVisibleImageCacheIdentityCount = 48
    private static let searchLoadingIndicatorDelayNanoseconds: UInt64 = 200_000_000
    private static let searchResultsTopAnchorID = "search-results-top-anchor"

    var body: some View {
        ZStack(alignment: .top) {
            content

            if showsPlainTextSearchStatusOverlay && !model.isTranslatingSearch {
                PlainTextSearchStatusView()
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            if showsSearchLoadingOverlay && showsSearchLoadingIndicator {
                searchLoadingIndicator
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: searchIsBusy) {
            guard showsSearchLoadingOverlay else {
                showsSearchLoadingIndicator = false
                return
            }

            let searchIsBusy = searchIsBusy
            guard searchIsBusy else {
                showsSearchLoadingIndicator = false
                return
            }

            try? await Task.sleep(nanoseconds: Self.searchLoadingIndicatorDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            showsSearchLoadingIndicator = true
        }
        .onAppear {
            syncSearchResultSelectionVisibleIDs()
        }
        .task(id: initialVisibleImageCacheTaskID) {
            guard await VisibleImageCacheTaskDeferral.waitBeforeStarting() else {
                return
            }
            await model.cacheVisibleImages(
                around: 0,
                quality: gridZoom.visibleImageQuality,
                forceRefresh: true
            )
        }
        .onChange(of: model.cards.map(\.id)) { _, _ in
            syncSearchResultSelectionVisibleIDs()
            keepRaisedSearchArtworkVisible()
            keepLandscapeSearchArtworkVisible()
        }
        .onChange(of: searchSelectionResetKey) { _, _ in
            clearSearchResultSelection()
            syncSearchResultSelectionVisibleIDs()
            searchJumpToTopState = .top
        }
        .onChange(of: searchSelectionClearRequestID) { _, _ in
            clearSearchResultSelection()
        }
        #if os(macOS)
        .onExitCommand {
            if !searchResultSelection.isEmpty {
                clearSearchResultSelection()
            }
        }
        .background {
            GridZoomKeyCommandBridge(gridZoom: gridZoom)
                .accessibilityHidden(true)
        }
        #endif
        .animation(.easeInOut(duration: 0.16), value: showsSearchLoadingIndicator)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if !model.hasLibrary {
                LibrarySetupView()
            } else if let message = model.unsupportedSearchMessage {
                ContentUnavailableView(
                    "Unsupported Search",
                    systemImage: "magnifyingglass",
                    description: Text(message)
                )
                .tint(palette.accent.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    GrimoraAppBackground(palette: palette)
                }
                .accessibilityIdentifier("unsupported-search")
            } else if model.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.stack")
                    .tint(palette.accent.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        GrimoraAppBackground(palette: palette)
                    }
                    .accessibilityIdentifier("empty-results")
            } else {
                resultsGrid
                    .background {
                        GrimoraAppBackground(palette: palette)
                    }
            }
        }
    }

    private var searchLoadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(model.isTranslatingSearch ? "Translating..." : "Searching...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .shadow(color: palette.shadow.color, radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search")
        .accessibilityValue(model.isTranslatingSearch ? "Translating search" : "Searching cards")
        .accessibilityIdentifier("search-loading-indicator")
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var searchIsBusy: Bool {
        model.isSearchingCards || model.isTranslatingSearch
    }

    private var searchSelectionResetKey: SearchResultSelectionResetKey {
        SearchResultSelectionResetKey(
            submittedSearchText: model.submittedSearchText,
            sortMode: model.sortMode,
            sortDirection: model.sortDirection,
            printingDisplayMode: model.printingDisplayMode
        )
    }

    private var initialVisibleImageCacheTaskID: InitialVisibleImageCacheTaskID {
        InitialVisibleImageCacheTaskID(
            searchSelectionResetKey: searchSelectionResetKey,
            cardIDs: Array(model.cards.prefix(Self.initialVisibleImageCacheIdentityCount).map(\.id)),
            quality: gridZoom.visibleImageQuality
        )
    }

    private func syncSearchResultSelectionVisibleIDs() {
        searchResultSelection.setVisibleIDs(model.cards.map(\.id))
        syncSearchResultBulkSelection()
    }

    private func clearSearchResultSelection() {
        guard !searchResultSelection.isEmpty else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            searchResultSelection.clear()
        }
        syncSearchResultBulkSelection()
    }

    private func applySearchResultSelectionInteraction(
        card: CardRecord,
        interaction: CardGridSelectionInteraction
    ) {
        if interaction == .range {
            syncSearchResultSelectionVisibleIDs()
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            searchResultSelection.select(card.id, interaction: interaction)
        }
        syncSearchResultBulkSelection()
    }

    private func bulkSearchCardIDs(triggeredBy card: CardRecord) -> [CardRecord.ID] {
        guard searchResultSelection.selectedIDs.contains(card.id) else {
            return []
        }

        return searchResultSelection.selectedOrderedIDs
    }

    private func liveBulkSearchCardIDs(triggeredBy card: CardRecord) -> [CardRecord.ID] {
        searchResultBulkSelection.cardIDs(triggeredBy: card.id)
    }

    private func prepareLiveSelectedSearchCardsMenu(for card: CardRecord) {
        searchResultBulkSelection.prepareMenu(triggeredBy: card.id)
    }

    private func addLiveSelectedSearchCards(to listID: CardListRecord.ID, triggeredBy card: CardRecord) -> Bool {
        let ids = searchResultBulkSelection.preparedOrCurrentCardIDs(triggeredBy: card.id)
        guard !ids.isEmpty else {
            return false
        }

        searchResultBulkSelection.clearPreparedMenu()
        model.addCards(ids, toListID: listID)
        return true
    }

    private func syncSearchResultBulkSelection() {
        searchResultBulkSelection.update(from: searchResultSelection)
    }

    @ViewBuilder
    private var resultsGrid: some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            scrollableResultsGrid(tracksLegacyScrollOffset: false)
        } else {
            scrollableResultsGrid(tracksLegacyScrollOffset: true)
        }
        #else
        scrollableResultsGrid(tracksLegacyScrollOffset: false)
        #endif
    }

    private func scrollableResultsGrid(tracksLegacyScrollOffset: Bool) -> some View {
        ScrollViewReader { proxy in
            ZStack {
                searchScrollTracking(
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(searchResultTotalText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.secondaryText.color)
                                .id(Self.searchResultsTopAnchorID)
                                .jumpToTopLegacyOffsetReader(coordinateSpaceName: "search-results-scroll")
                                .accessibilityLabel("Search Results")
                                .accessibilityValue(searchResultTotalText)
                                .accessibilityIdentifier("search-results-total")

                            AdaptiveCardGrid(
                                items: Array(model.cards.enumerated()),
                                id: { $0.element.id },
                                landscapeItemIDs: defaultLandscapeSearchArtworkCardIDs.union(landscapeSearchArtworkCardIDs),
                                minimumColumnWidth: gridZoom.minimumColumnWidth,
                                maximumColumnWidth: gridZoom.maximumColumnWidth
                            ) { indexedCard in
                                let index = indexedCard.offset
                                let card = indexedCard.element
                                let imageQuality = gridZoom.visibleImageQuality

                                VisiblePreviewLoadingObserver(
                                    entry: model.visiblePreviewLoadingEntry(
                                        for: card,
                                        quality: imageQuality
                                    ),
                                    card: card
                                ) { accessibilityValue, showsPreviewLoadingIndicator in
                                    CardGridItemView(
                                        card: card,
                                        openAccessibilityIdentifier: "open-card-\(card.id)",
                                        accessibilityValue: accessibilityValue,
                                        showsPreviewLoadingIndicator: showsPreviewLoadingIndicator,
                                        onSelect: onSelect,
                                        onCreateListForCard: onCreateListForCard,
                                        isSelectionEnabled: true,
                                        isSelectedInSelection: searchResultSelection.selectedIDs.contains(card.id),
                                        isActiveDetail: model.selectedCard?.id == card.id,
                                        selectionAccessibilityIdentifier: "select-card-\(card.id)",
                                        showsSelectionIndicatorWhenSelected: false,
                                        selectedCardIDsForBulkActions: bulkSearchCardIDs(triggeredBy: card),
                                        selectedCardIDsForBulkActionsProvider: {
                                            liveBulkSearchCardIDs(triggeredBy: card)
                                        },
                                        onSelectionInteraction: { interaction in
                                            applySearchResultSelectionInteraction(
                                                card: card,
                                                interaction: interaction
                                            )
                                        },
                                        onCreateListForCards: onCreateListForCards,
                                        onAddCardsToList: addLiveSelectedSearchCards,
                                        onPrepareAddMenu: prepareLiveSelectedSearchCardsMenu,
                                        onArtworkOverflowChange: { isOverflowing in
                                            updateRaisedSearchArtwork(cardID: card.id, isOverflowing: isOverflowing)
                                        },
                                        onArtworkLandscapeLayoutChange: { usesLandscapeLayout in
                                            updateLandscapeSearchArtwork(
                                                cardID: card.id,
                                                usesLandscapeLayout: usesLandscapeLayout
                                            )
                                        }
                                    )
                                }
                                .task(id: VisibleImageCacheTaskID(card: card, index: index, quality: imageQuality)) {
                                    guard await VisibleImageCacheTaskDeferral.waitBeforeStarting() else {
                                        return
                                    }
                                    await model.cacheVisibleImages(around: index, quality: imageQuality)
                                }
                                .onAppear {
                                    model.loadMoreCardsIfNeeded(afterAppearingCardAt: index)
                                }
                                .zIndex(raisedSearchArtworkCardID == card.id ? 100 : 0)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .padding(.top, 24 + searchHeaderTopInset)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background {
                            searchResultsBlankSpaceTapTarget
                        }
                        .background {
                            if tracksLegacyScrollOffset {
                                GeometryReader { proxy in
                                    let legacyContentMinY = proxy.frame(in: .named("search-results-scroll")).minY
                                    Color.clear
                                        .preference(
                                            key: SearchScrollTriggerPreferenceKey.self,
                                            value: MacSearchHeaderScrollTrigger(
                                                legacyContentMinY: legacyContentMinY
                                            )
                                        )
                                }
                            }
                        }

                        if model.isLoadingMoreCards {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.bottom, 24)
                                .accessibilityIdentifier("loading-more-results")
                        }
                    }
                    .cardArtworkViewport()
                    .coordinateSpace(name: "search-results-scroll")
                    .background {
                        searchResultsBlankSpaceTapTarget
                    }
                    .accessibilityIdentifier("search-results-scroll")
                    .simultaneousGesture(GridZoomAvailability.isSupported ? magnifyGesture : nil)
                )
            }
            .jumpToTopButtonInset(
                isVisible: searchJumpToTopState.showsButton,
                accessibilityIdentifier: "search-results-jump-to-top-button"
            ) {
                scrollSearchResultsToTop(using: proxy)
            }
        }
    }

    @ViewBuilder
    private func searchScrollTracking<Content: View>(_ content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: SearchScrollGeometryState.self) { geometry in
                    SearchScrollGeometryState(
                        contentOffsetY: geometry.contentOffset.y,
                        viewportHeight: geometry.containerSize.height
                    )
                } action: { _, trigger in
                    onSearchScrollTriggerChange(trigger.headerTrigger)
                    searchJumpToTopState = trigger.jumpToTopState
                }
        } else {
            content
                .onPreferenceChange(SearchScrollTriggerPreferenceKey.self) { trigger in
                    onSearchScrollTriggerChange(trigger)
                }
                .onPreferenceChange(JumpToTopScrollStatePreferenceKey.self) { state in
                    searchJumpToTopState = state
                }
        }
        #else
        content
            .jumpToTopScrollTracking($searchJumpToTopState)
        #endif
    }

    private func scrollSearchResultsToTop(using proxy: ScrollViewProxy) {
        let scroll = {
            proxy.scrollTo(Self.searchResultsTopAnchorID, anchor: .top)
            searchJumpToTopState = .top
        }

        if reduceMotion {
            scroll()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                scroll()
            }
        }
    }

    private var searchResultsBlankSpaceTapTarget: some View {
        BlankSpaceTapTarget {
            clearSearchResultSelection()
        }
    }

    private var searchResultTotalText: String {
        let formattedTotal = model.searchResultTotal.formatted()
        let noun = model.searchResultTotal == 1 ? "card" : "cards"
        return "\(formattedTotal) \(noun)"
    }

    private var defaultLandscapeSearchArtworkCardIDs: Set<CardRecord.ID> {
        Set(model.cards.compactMap { card in
            cardUsesDefaultLandscapeArtworkLayout(card) ? card.id : nil
        })
    }

    private func updateRaisedSearchArtwork(cardID: CardRecord.ID, isOverflowing: Bool) {
        if isOverflowing {
            raisedSearchArtworkCardID = cardID
        } else if raisedSearchArtworkCardID == cardID {
            raisedSearchArtworkCardID = nil
        }
    }

    private func updateLandscapeSearchArtwork(
        cardID: CardRecord.ID,
        usesLandscapeLayout: Bool
    ) {
        if usesLandscapeLayout {
            landscapeSearchArtworkCardIDs.insert(cardID)
        } else {
            landscapeSearchArtworkCardIDs.remove(cardID)
        }
    }

    private func keepRaisedSearchArtworkVisible() {
        guard let raisedSearchArtworkCardID else {
            return
        }

        if !model.cards.contains(where: { $0.id == raisedSearchArtworkCardID }) {
            self.raisedSearchArtworkCardID = nil
        }
    }

    private func keepLandscapeSearchArtworkVisible() {
        landscapeSearchArtworkCardIDs.formIntersection(Set(model.cards.map(\.id)))
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let startScale = magnificationStartScale ?? gridZoom.scale
                magnificationStartScale = startScale
                gridZoom.setMagnifiedScale(
                    startScale: startScale,
                    magnification: value.magnification
                )
            }
            .onEnded { _ in
                magnificationStartScale = nil
            }
    }
}

#if os(macOS)
private struct GridZoomKeyCommandBridge: NSViewRepresentable {
    var gridZoom: GridZoomController

    func makeCoordinator() -> Coordinator {
        Coordinator(gridZoom: gridZoom)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.gridZoom = gridZoom
        context.coordinator.install()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var gridZoom: GridZoomController
        private var monitor: Any?

        init(gridZoom: GridZoomController) {
            self.gridZoom = gridZoom
        }

        func install() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let character = event.charactersIgnoringModifiers?.lowercased()

            if flags == [.command, .shift], character == "." {
                Task { @MainActor [gridZoom] in
                    gridZoom.zoomIn()
                }
                return nil
            }

            if flags == [.command, .shift], character == "," {
                Task { @MainActor [gridZoom] in
                    gridZoom.zoomOut()
                }
                return nil
            }

            if flags == [.command], character == "0" {
                Task { @MainActor [gridZoom] in
                    gridZoom.reset()
                }
                return nil
            }

            return event
        }
    }
}
#endif

private struct SearchResultSelectionResetKey: Equatable {
    var submittedSearchText: String
    var sortMode: SortMode
    var sortDirection: SearchSortDirection
    var printingDisplayMode: PrintingDisplayMode
}

@Observable
@MainActor
private final class SearchResultBulkSelection {
    private var selectedIDs: Set<CardRecord.ID> = []
    private var selectedOrderedIDs: [CardRecord.ID] = []
    private var preparedMenuTriggerID: CardRecord.ID?
    private var preparedMenuCardIDs: [CardRecord.ID] = []

    func update(from selection: CardGridSelectionState<CardRecord.ID>) {
        selectedIDs = selection.selectedIDs
        selectedOrderedIDs = selection.selectedOrderedIDs
    }

    func prepareMenu(triggeredBy cardID: CardRecord.ID) {
        preparedMenuTriggerID = cardID
        preparedMenuCardIDs = cardIDs(triggeredBy: cardID)
    }

    func preparedOrCurrentCardIDs(triggeredBy cardID: CardRecord.ID) -> [CardRecord.ID] {
        if preparedMenuTriggerID == cardID, !preparedMenuCardIDs.isEmpty {
            return preparedMenuCardIDs
        }

        return cardIDs(triggeredBy: cardID)
    }

    func clearPreparedMenu() {
        preparedMenuTriggerID = nil
        preparedMenuCardIDs.removeAll()
    }

    func cardIDs(triggeredBy cardID: CardRecord.ID) -> [CardRecord.ID] {
        guard selectedIDs.contains(cardID) else {
            return []
        }

        return selectedOrderedIDs
    }
}

private struct SearchScrollTriggerPreferenceKey: PreferenceKey {
    static let defaultValue = MacSearchHeaderScrollTrigger.expand

    static func reduce(value: inout MacSearchHeaderScrollTrigger, nextValue: () -> MacSearchHeaderScrollTrigger) {
        value = nextValue()
    }
}

private struct SearchScrollGeometryState: Equatable {
    var headerTrigger: MacSearchHeaderScrollTrigger
    var jumpToTopState: JumpToTopScrollState

    init(contentOffsetY: CGFloat, viewportHeight: CGFloat) {
        headerTrigger = MacSearchHeaderScrollTrigger(contentOffsetY: contentOffsetY)
        jumpToTopState = JumpToTopScrollState(
            contentOffsetY: contentOffsetY,
            viewportHeight: viewportHeight
        )
    }
}

private struct VisibleImageCacheTaskID: Equatable {
    var cardID: String
    var index: Int
    var quality: CardImageQuality

    init(card: CardRecord, index: Int, quality: CardImageQuality) {
        cardID = card.id
        self.index = index
        self.quality = quality
    }
}

private struct InitialVisibleImageCacheTaskID: Equatable {
    var searchSelectionResetKey: SearchResultSelectionResetKey
    var cardIDs: [CardRecord.ID]
    var quality: CardImageQuality
}
