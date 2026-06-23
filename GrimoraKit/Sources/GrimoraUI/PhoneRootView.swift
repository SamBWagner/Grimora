#if os(iOS) || os(visionOS)
import Foundation
import GrimoraCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct TouchRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: GrimoraAppModel
    @StateObject private var gridZoom = GridZoomController()
    @StateObject private var libraryMaintenance = GrimoraLibraryMaintenanceController()
    @State private var selectedTab = TouchRootTab.search
    @State private var listNavigationPath: [CardListsBrowserRoute] = []
    @State private var listNameAction: ListNameAction?
    @State private var listNameDraft = ""
    @State private var isSearchSettingsPresented = false
    @State private var previousListSplitSelection: GrimoraSidebarSelection = .search

    private static let wideListLayoutThreshold: CGFloat = 900
    private static let wideCardDetailLayoutThreshold: CGFloat = 980

    var body: some View {
        cardDetailPresentation
            .sheet(isPresented: $isSearchSettingsPresented) {
                searchSettingsSheet
            }
            .focusedSceneObject(GridZoomAvailability.isSupported ? gridZoom : nil)
            .focusedSceneObject(libraryMaintenance)
            .environmentObject(libraryMaintenance)
            .libraryMaintenanceConfirmationDialog(controller: libraryMaintenance)
            .alert(listNameAction?.title ?? "List", isPresented: listNamePromptBinding) {
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
        }
        .onChange(of: model.selectedListID) { _, selectedListID in
            guard selectedTab == .lists, let selectedListID else {
                return
            }
            let selectedRoute = CardListsBrowserRoute.list(selectedListID)
            if listNavigationPath.last != selectedRoute {
                listNavigationPath = [selectedRoute]
            }
        }
    }

    @ViewBuilder
    private var cardDetailPresentation: some View {
        #if os(iOS)
        if usesPhoneCardDetailSheet {
            rootTabs
                .sheet(isPresented: detailSheetBinding) {
                    cardDetailSheet
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.black)
                        .presentationCornerRadius(28)
                }
        } else {
            rootTabs
                .inspector(isPresented: detailSheetBinding) {
                    cardDetailInspector
                        .inspectorColumnWidth(min: 420, ideal: 520, max: 680)
                }
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
                    },
                    onCreateListFromSearch: {
                        presentCreateSearchListPrompt()
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
                ToolbarItem(placement: .topBarTrailing) {
                    SearchHistoryMenu { query in
                        model.setSearchDraft(query)
                        Task {
                            await model.submitSearch()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SearchOptionsMenu(
                        gridZoom: gridZoom,
                        onCreateListFromSearch: {
                            presentCreateSearchListPrompt()
                        },
                        onOpenSearchSettings: {
                            isSearchSettingsPresented = true
                        }
                    )
                }
            }
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
            CardListsBrowserView(
                gridZoom: gridZoom,
                onCreateList: {
                    listNavigationPath = [.newList]
                },
                onCancelCreateList: {
                    listNavigationPath = []
                },
                onCompleteCreateList: {
                    if let selectedListID = model.selectedListID {
                        listNavigationPath = [.list(selectedListID)]
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
            .navigationTitle("Lists")
        }
        .accessibilityIdentifier("card-lists-compact-stack")
    }

    private var listsSplitTab: some View {
        NavigationSplitView {
            CardListsBrowserSidebarView(
                onCreateList: {
                    presentCreateListDestinationInSplit()
                },
                onRenameList: { list in
                    presentRenameListPrompt(list)
                }
            )
            .navigationTitle("Lists")
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
            CardListsOverviewView(
                onCreateList: {
                    presentCreateListDestinationInSplit()
                },
                onSelectList: { _ in },
                onRenameList: { presentRenameListPrompt($0) }
            )
        case .newList:
            CardListCreateDestinationView(
                onCancel: {
                    model.cancelNewListCreation(returningTo: previousListSplitSelection)
                },
                onComplete: {}
            )
            .navigationTitle("New List")
        case .list(let listID) where model.selectedList?.id == listID:
            CardListDetailView(
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
            .navigationTitle(model.selectedList?.name ?? "List")
        case .list, .search:
            CardListsOverviewView(
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

    private var usesPhoneCardDetailSheet: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
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

    private var cardDetailInspector: some View {
        cardDetailContent(
            presentationStyle: .inspector,
            onClose: { model.closeSelectedCard() }
        )
        .touchChromeBackground(palette: palette, colorScheme: colorScheme)
    }

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

    private func presentCreateSearchListPrompt() {
        listNameDraft = ""
        listNameAction = .createFromSearch
    }

    private func presentCreateListDestinationInSplit() {
        if model.sidebarSelection != .newList {
            previousListSplitSelection = model.sidebarSelection
        }
        listNavigationPath = []
        model.selectNewList()
    }

    private func presentRenameListPrompt(_ list: CardListRecord) {
        listNameDraft = list.name
        listNameAction = .rename(list)
    }

    private func presentCreateCategoryPrompt(in list: CardListRecord) {
        listNameDraft = ""
        listNameAction = .createCategory(listID: list.id)
    }

    private func presentRenameCategoryPrompt(_ category: CardListCategoryRecord) {
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
            model.createCardList(named: name, adding: card, selectAfterCreate: selectAfterCreate)
        case .createWithCardIDs(let cardIDs, let selectAfterCreate):
            model.createCardList(
                named: name,
                addingCardIDs: cardIDs,
                selectAfterCreate: selectAfterCreate
            )
        case .createFromSearch:
            Task {
                if let list = await model.createCardListFromCurrentSearch(named: name) {
                    selectedTab = .lists
                    listNavigationPath = [.list(list.id)]
                }
            }
        case .rename(let list):
            model.renameCardList(id: list.id, to: name)
        case .createCategory(let listID):
            model.createCardListCategory(named: name, inListID: listID)
        case .renameCategory(let category):
            model.renameCardListCategory(id: category.id, to: name)
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
