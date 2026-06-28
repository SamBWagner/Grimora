#if os(iOS) || os(visionOS)
import Foundation
import GrimoraCore
import SwiftUI

struct TouchRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model
    @State private var gridZoom = GridZoomController()
    @State private var libraryMaintenance = GrimoraLibraryMaintenanceController()
    @State private var selectedTab = TouchRootTab.search
    @State private var listNavigationPath: [CardCollectionsBrowserRoute] = []
    @State private var listNameAction: CollectionNameAction?
    @State private var listNameDraft = ""
    @State private var isSearchSettingsPresented = false
    @State private var previousListSplitSelection: GrimoraSidebarSelection = .search
    @AppStorage(GrimoraSearchPreferences.advancedSearchEnabledKey)
    private var advancedSearchEnabled = GrimoraSearchPreferences.defaultAdvancedSearchEnabled
    @State private var advancedSearchBuilder = AdvancedSearchBuilder()
    @State private var isAdvancedSearchPresented = false

    private static let wideListLayoutThreshold: CGFloat = 900
    private static let wideCardDetailLayoutThreshold: CGFloat = 980

    var body: some View {
        cardDetailPresentation
            .sheet(isPresented: $isSearchSettingsPresented) {
                searchSettingsSheet
            }
            .focusedSceneValue(\.gridZoomController, GridZoomAvailability.isSupported ? gridZoom : nil)
            .focusedSceneValue(\.libraryMaintenanceController, libraryMaintenance)
            .environment(libraryMaintenance)
            .libraryMaintenanceConfirmationDialog(controller: libraryMaintenance)
            .alert(listNameAction?.title ?? "Collection", isPresented: listNamePromptBinding) {
                TextField("Name", text: $listNameDraft)
                Button(listNameAction?.confirmationTitle ?? "Save") {
                    submitListNamePrompt()
                }
                .disabled(listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {
                    listNameAction = nil
                    listNameDraft = ""
                }
            }
    }

    private var rootTabs: some View {
        TabView(selection: $selectedTab) {
            Tab(
                TouchRootTab.search.title,
                systemImage: TouchRootTab.search.systemImage,
                value: TouchRootTab.search
            ) {
                searchTab
            }

            Tab(
                TouchRootTab.lists.title,
                systemImage: TouchRootTab.lists.systemImage,
                value: TouchRootTab.lists
            ) {
                listsTab
            }

            #if os(iOS)
            Tab(
                TouchRootTab.scry.title,
                systemImage: TouchRootTab.scry.systemImage,
                value: TouchRootTab.scry
            ) {
                scryTab
            }
            #endif
        }
        .adaptiveTouchTabViewStyle()
        .accessibilityIdentifier("touch-root-tab-view")
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .search {
                listNavigationPath = []
                model.selectSearch()
            } else if newValue == .lists {
                listNavigationPath = []
                model.selectListsOverview()
            }
            // `.scry` drives its own camera lifecycle from the tab view.
        }
        .onChange(of: model.selectedCollectionID) { _, selectedCollectionID in
            guard selectedTab == .lists, let selectedCollectionID else {
                return
            }
            let selectedRoute = CardCollectionsBrowserRoute.list(selectedCollectionID)
            if listNavigationPath.last != selectedRoute {
                listNavigationPath = [selectedRoute]
            }
        }
    }

    @ViewBuilder
    private var cardDetailPresentation: some View {
        #if os(iOS)
        // Card detail always presents as a fly-up sheet on iOS — iPhone and iPad
        // alike. The side inspector reserved a fixed 420pt column that overflowed
        // the viewport whenever a Stage Manager / Split View window was dragged
        // narrower than it could fit, and even a full 13" iPad isn't wide enough
        // for a comfortable grid-plus-inspector split. A sheet sidesteps the
        // whole responsiveness problem.
        rootTabs
            .sheet(isPresented: detailSheetBinding) {
                cardDetailSheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.black)
                    .presentationCornerRadius(28)
            }
        #elseif os(visionOS)
        GeometryReader { proxy in
            if shouldUseWideCardDetailLayout(for: proxy.size.width) {
                HStack(spacing: 0) {
                    rootTabs
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if model.selectedCard != nil {
                        Divider()
                        cardDetailInspector
                            .frame(width: cardDetailInspectorWidth(for: proxy.size.width))
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: model.selectedCard?.id)
            } else {
                rootTabs
                    .fullScreenCover(isPresented: detailSheetBinding) {
                        cardDetailSheet
                    }
            }
        }
        #endif
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    #if os(iOS)
    private var scryTab: some View {
        ScryTabView(isActive: selectedTab == .scry)
    }
    #endif

    private var searchTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchSyntaxHighlightBar(query: model.searchText)

                SearchContentView(
                    gridZoom: gridZoom,
                    onSelect: { card in
                        model.selectCard(card)
                    },
                    onCreateListForCard: { card in
                        presentCreateListPrompt(adding: card, selectAfterCreate: false)
                    },
                    onCreateListForCards: { cardIDs in
                        presentCreateListPrompt(addingCardIDs: cardIDs, selectAfterCreate: false)
                    }
                )
            }
            .navigationTitle("Cards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .searchable(
                text: searchTextBinding,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search cards"
            )
            #else
            .searchable(
                text: searchTextBinding,
                placement: .toolbarPrincipal,
                prompt: "Search cards"
            )
            #endif
            // Scryfall syntax is case-insensitive but not English prose — don't let
            // the keyboard auto-capitalise field keywords or autocorrect the query.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                Task {
                    await model.submitSearch()
                }
            }
            .searchSuggestions {
                SearchHistorySuggestions(searchText: model.searchText, history: model.visibleSearchHistory) { query in
                    model.setSearchDraft(query)
                }
                .searchSuggestions(.visible, for: .menu)
                .searchSuggestions(.hidden, for: .content)
            }
            #if os(iOS)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SearchHistoryMenu { query in
                        model.setSearchDraft(query)
                        Task {
                            await model.submitSearch()
                        }
                    }

                    SearchViewOptionsMenu(gridZoom: gridZoom)

                    if advancedSearchEnabled {
                        Button("Advanced Search", systemImage: "slider.horizontal.3") {
                            isAdvancedSearchPresented = true
                        }
                        .accessibilityIdentifier("advanced-search-launch-button")
                        .help("Advanced Search")
                    }
                }
            }
            .sheet(isPresented: $isAdvancedSearchPresented) {
                AdvancedSearchSheet(builder: $advancedSearchBuilder) { builder in
                    Task { await model.applyAdvancedSearch(builder) }
                } onReset: {
                    model.clearSearch()
                }
            }
        }
        // Float the settings cog just above the tab bar, in its natural resting
        // position — the overlay respects the tab-bar safe-area inset rather
        // than being pushed down onto the tab-bar row.
        .overlay(alignment: .bottom) {
            SearchFloatingControls(
                onOpenSearchSettings: {
                    isSearchSettingsPresented = true
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
    }

    private var searchTextBinding: Binding<String> {
        Binding {
            model.searchText
        } set: { newValue in
            model.setSearchDraft(newValue)
        }
    }

    private var searchSettingsSheet: some View {
        NavigationStack {
            GrimoraSettingsView()
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isSearchSettingsPresented = false
                        }
                    }
                }
        }
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
    }

    @ViewBuilder
    private var listsTab: some View {
        #if os(visionOS)
        GeometryReader { proxy in
            if shouldUseWideListLayout(for: proxy.size.width) {
                listsSplitTab
            } else {
                listsStackTab
            }
        }
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
        #else
        listsStackTab
            .touchChromeBackground(palette: palette, colorScheme: colorScheme)
        #endif
    }

    private var listsStackTab: some View {
        NavigationStack(path: $listNavigationPath) {
            CardCollectionsBrowserView(
                gridZoom: gridZoom,
                onCreateList: {
                    listNavigationPath = [.newList]
                },
                onCancelCreateList: {
                    listNavigationPath = []
                },
                onCompleteCreateList: {
                    if let selectedCollectionID = model.selectedCollectionID {
                        listNavigationPath = [.list(selectedCollectionID)]
                    } else {
                        listNavigationPath = []
                    }
                },
                onRenameList: { list in
                    presentRenameListPrompt(list)
                },
                onSelectCard: { card in
                    model.selectCard(card)
                },
                onCreateListForCard: { card in
                    presentCreateListPrompt(adding: card, selectAfterCreate: false)
                },
                onCreateListForCards: { cardIDs in
                    presentCreateListPrompt(addingCardIDs: cardIDs, selectAfterCreate: false)
                },
                onCreateCategory: { list in
                    presentCreateCategoryPrompt(in: list)
                },
                onRenameCategory: { category in
                    presentRenameCategoryPrompt(category)
                }
            )
            .navigationTitle("Collections")
        }
        .accessibilityIdentifier("card-lists-compact-stack")
    }

    private var listsSplitTab: some View {
        NavigationSplitView {
            CardCollectionsBrowserSidebarView(
                onCreateList: {
                    presentCreateListDestinationInSplit()
                },
                onRenameList: { list in
                    presentRenameListPrompt(list)
                }
            )
            .navigationTitle("Collections")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            listsSplitDetail
        }
        .accessibilityIdentifier("card-lists-split-view")
    }

    @ViewBuilder
    private var listsSplitDetail: some View {
        switch model.sidebarSelection {
        case .listsOverview:
            CardCollectionsOverviewView(
                gridZoom: gridZoom,
                onCreateList: {
                    presentCreateListDestinationInSplit()
                },
                onSelectList: { _ in },
                onRenameList: { presentRenameListPrompt($0) }
            )
        case .newList:
            CardCollectionCreateDestinationView(
                onCancel: {
                    model.cancelNewListCreation(returningTo: previousListSplitSelection)
                },
                onComplete: {}
            )
            .navigationTitle("New Collection")
        case .list(let listID) where model.selectedCollection?.id == listID:
            CardCollectionDetailView(
                gridZoom: gridZoom,
                onSelect: { card in
                    model.selectCard(card)
                },
                onCreateListForCard: { card in
                    presentCreateListPrompt(adding: card, selectAfterCreate: false)
                },
                onCreateListForCards: { cardIDs in
                    presentCreateListPrompt(addingCardIDs: cardIDs, selectAfterCreate: false)
                },
                onRenameList: { list in
                    presentRenameListPrompt(list)
                },
                onCreateCategory: { list in
                    presentCreateCategoryPrompt(in: list)
                },
                onRenameCategory: { category in
                    presentRenameCategoryPrompt(category)
                }
            )
            .navigationTitle(model.selectedCollection?.name ?? "Collection")
        case .list, .search:
            CardCollectionsOverviewView(
                gridZoom: gridZoom,
                onCreateList: {
                    presentCreateListDestinationInSplit()
                },
                onSelectList: { _ in },
                onRenameList: { presentRenameListPrompt($0) }
            )
        }
    }

    private func shouldUseWideListLayout(for width: CGFloat) -> Bool {
        #if os(visionOS)
        guard ProcessInfo.processInfo.environment["GRIMORA_TEST_FORCE_COMPACT_LISTS"] != "1" else {
            return false
        }
        #endif
        return width >= Self.wideListLayoutThreshold
    }

    private func shouldUseWideCardDetailLayout(for width: CGFloat) -> Bool {
        #if os(visionOS)
        guard ProcessInfo.processInfo.environment["GRIMORA_TEST_FORCE_COMPACT_CARD_DETAIL"] != "1" else {
            return false
        }
        #endif
        return width >= Self.wideCardDetailLayoutThreshold
    }

    private func cardDetailInspectorWidth(for width: CGFloat) -> CGFloat {
        min(max(420, width * 0.38), 560)
    }

    private var detailSheetBinding: Binding<Bool> {
        Binding {
            model.selectedCard != nil
        } set: { isPresented in
            if !isPresented {
                model.closeSelectedCard()
            }
        }
    }

    private var listNamePromptBinding: Binding<Bool> {
        Binding {
            listNameAction != nil
        } set: { isPresented in
            if !isPresented {
                listNameAction = nil
                listNameDraft = ""
            }
        }
    }

    private var cardDetailSheet: some View {
        NavigationStack {
            cardDetailContent(
                presentationStyle: .sheet,
                onClose: cardDetailCloseAction
            )
        }
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
    }

    #if os(visionOS)
    private var cardDetailInspector: some View {
        cardDetailContent(
            presentationStyle: .inspector,
            onClose: { model.closeSelectedCard() }
        )
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
    }
    #endif

    @ViewBuilder
    private func cardDetailContent(
        presentationStyle: CardDetailPresentationStyle,
        onClose: (() -> Void)?
    ) -> some View {
        if let card = model.selectedCard {
            CardDetailView(
                card: card,
                printings: model.selectedCardPrintings,
                valueGuide: model.selectedCardValueGuide,
                valueHistoryBackgroundActivity: model.valueHistoryBackgroundActivity,
                valueExchangeRate: model.valueExchangeRate,
                presentationStyle: presentationStyle,
                onSelectPrinting: { printing in
                    model.selectPrinting(printing)
                },
                isFoilSelected: { model.isFoilSelected(for: $0) },
                onSetFoil: { printing, isFoil in
                    model.setFoil(isFoil, for: printing)
                },
                onLoadPrintingThumbnailImage: { printing in
                    await model.cachePrintingThumbnailImage(for: printing)
                },
                onLoadPrintingPreviewImage: { printing in
                    await model.cachePrintingPreviewImages(for: printing)
                },
                onLoadAvailablePrintingPreviewImages: { printings in
                    await model.cachePrintingPreviewImages(for: printings)
                },
                onLoadValueExchangeRate: { currency in
                    await model.loadValueExchangeRateIfNeeded(for: currency)
                },
                onCreateListForCard: { card in
                    presentCreateListPrompt(adding: card, selectAfterCreate: false)
                },
                onSearchArtist: { artist in
                    Task { await model.searchArtworks(byArtist: artist) }
                },
                onClose: onClose
            )
            .task(id: card.id) {
                async let imageCaching: Void = model.cacheDetailImages(for: card)
                async let printingLoad: Void = model.loadPrintings(for: card)
                async let valueLoad: Void = model.loadValueGuide(for: card)
                _ = await (imageCaching, printingLoad, valueLoad)
            }
        }
    }

    private var cardDetailCloseAction: (() -> Void)? {
        #if os(iOS)
        nil
        #else
        { model.closeSelectedCard() }
        #endif
    }

    private func presentCreateListPrompt(adding card: CardRecord?, selectAfterCreate: Bool) {
        listNameDraft = ""
        listNameAction = .create(adding: card, selectAfterCreate: selectAfterCreate)
    }

    private func presentCreateListPrompt(
        addingCardIDs cardIDs: [CardRecord.ID],
        selectAfterCreate: Bool
    ) {
        listNameDraft = ""
        listNameAction = .createWithCardIDs(cardIDs, selectAfterCreate: selectAfterCreate)
    }

    private func presentCreateListDestinationInSplit() {
        if model.sidebarSelection != .newList {
            previousListSplitSelection = model.sidebarSelection
        }
        listNavigationPath = []
        model.selectNewList()
    }

    private func presentRenameListPrompt(_ list: CardCollectionRecord) {
        listNameDraft = list.name
        listNameAction = .rename(list)
    }

    private func presentCreateCategoryPrompt(in list: CardCollectionRecord) {
        listNameDraft = ""
        listNameAction = .createCategory(listID: list.id)
    }

    private func presentRenameCategoryPrompt(_ category: CardCollectionCategoryRecord) {
        listNameDraft = category.name
        listNameAction = .renameCategory(category)
    }

    private func submitListNamePrompt() {
        guard let listNameAction else {
            return
        }

        let name = listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }

        switch listNameAction {
        case .create(let card, let selectAfterCreate):
            model.createCardCollection(named: name, adding: card, selectAfterCreate: selectAfterCreate)
        case .createWithCardIDs(let cardIDs, let selectAfterCreate):
            model.createCardCollection(
                named: name,
                addingCardIDs: cardIDs,
                selectAfterCreate: selectAfterCreate
            )
        case .createFromSearch:
            Task {
                if let list = await model.createCardCollectionFromCurrentSearch(named: name) {
                    selectedTab = .lists
                    listNavigationPath = [.list(list.id)]
                }
            }
        case .rename(let list):
            model.renameCardCollection(id: list.id, to: name)
        case .createCategory(let listID):
            model.createCardCollectionCategory(named: name, inListID: listID)
        case .renameCategory(let category):
            model.renameCardCollectionCategory(id: category.id, to: name)
        }

        self.listNameAction = nil
        listNameDraft = ""
    }
}

private extension View {
    @ViewBuilder
    func adaptiveTouchTabViewStyle() -> some View {
        #if os(visionOS)
        self.tabViewStyle(.sidebarAdaptable)
        #else
        self
        #endif
    }

    func touchChromeBackground(
        palette: GrimoraPalette,
        colorScheme: ColorScheme
    ) -> some View {
        #if os(iOS)
        background {
            GrimoraAppBackground(palette: palette)
                .ignoresSafeArea()
        }
        .toolbarBackground(palette.appBackground.color, for: .navigationBar, .tabBar)
        .toolbarBackground(.visible, for: .navigationBar, .tabBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar, .tabBar)
        #else
        background {
            GrimoraAppBackground(palette: palette)
                .ignoresSafeArea()
        }
        #endif
    }
}
#endif
