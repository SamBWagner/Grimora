import GrimoraCore
import SwiftUI

#if os(macOS)
@MainActor
public final class GrimoraSearchFocusController: ObservableObject {
    public static let shared = GrimoraSearchFocusController()

    @Published var focusRequestID = 0

    public init() {}

    public func focusSearch() {
        focusRequestID += 1
    }
}

struct MacRootView: View {
    var body: some View {
        SplitRootView()
    }
}

private struct SplitRootView: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @StateObject private var gridZoom = GridZoomController()
    @StateObject private var searchFocus = GrimoraSearchFocusController.shared
    @StateObject private var listCommands = GrimoraListCommandController()
    @StateObject private var libraryMaintenance = GrimoraLibraryMaintenanceController()
    @State private var listNameAction: ListNameAction?
    @State private var previousSidebarSelection: GrimoraSidebarSelection = .search
    @State private var listNameDraft = ""

    private static let sidebarMinimumWidth: CGFloat = 160
    private static let sidebarIdealWidth: CGFloat = 190
    private static let centerColumnIdealWidth: CGFloat = 320
    private static let inspectorMinimumWidth: CGFloat = 320
    private static let inspectorIdealWidth: CGFloat = 380
    private static let inspectorMaximumWidth: CGFloat = 600

    var body: some View {
        navigationContent
        .focusedSceneObject(gridZoom)
        .focusedSceneObject(searchFocus)
        .focusedSceneObject(listCommands)
        .focusedSceneObject(model)
        .focusedSceneObject(libraryMaintenance)
        .environmentObject(libraryMaintenance)
        .libraryMaintenanceConfirmationDialog(controller: libraryMaintenance)
        .onAppear {
            GridZoomController.activeForCommands = gridZoom
        }
        .onChange(of: searchFocus.focusRequestID) { _, _ in
            model.selectSearch()
        }
        .onChange(of: listCommands.renameRequest?.id) { _, _ in
            guard let list = listCommands.consumeRenameRequest() else {
                return
            }
            presentRenameListPrompt(list)
        }
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

    private var navigationContent: some View {
        NavigationSplitView {
            ControlPanelView(
                onCreateList: {
                    presentCreateListDestination()
                },
                onRenameList: { list in
                    presentRenameListPrompt(list)
                }
            )
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarMinimumWidth,
                    ideal: Self.sidebarIdealWidth
                )
        } detail: {
            detailContent
                .navigationSplitViewColumnWidth(
                    min: centerColumnMinimumWidth,
                    ideal: Self.centerColumnIdealWidth
                )
        }
        .inspector(isPresented: detailSheetBinding) {
            cardDetailInspector
                .inspectorColumnWidth(
                    min: Self.inspectorMinimumWidth,
                    ideal: Self.inspectorIdealWidth,
                    max: Self.inspectorMaximumWidth
                )
        }
    }

    private var centerColumnMinimumWidth: CGFloat {
        max(
            gridZoom.minimumSingleColumnContentWidth,
            MacSearchFloatingHeader.minimumExpandedSurfaceWidth + GridZoomController.gridHorizontalContentPadding
        )
    }

    @ViewBuilder
    private var cardDetailInspector: some View {
        if let card = model.selectedCard {
            CardDetailView(
                card: card,
                printings: model.selectedCardPrintings,
                valueGuide: model.selectedCardValueGuide,
                valueHistoryBackgroundActivity: model.valueHistoryBackgroundActivity,
                valueExchangeRate: model.valueExchangeRate,
                presentationStyle: .inspector
            ) { printing in
                model.selectPrinting(printing)
            } onLoadPrintingThumbnailImage: { printing in
                await model.cachePrintingThumbnailImage(for: printing)
            } onLoadPrintingPreviewImage: { printing in
                await model.cachePrintingPreviewImages(for: printing)
            } onLoadAvailablePrintingPreviewImages: { printings in
                await model.cachePrintingPreviewImages(for: printings)
            } onLoadValueExchangeRate: { currency in
                await model.loadValueExchangeRateIfNeeded(for: currency)
            } onCreateListForCard: { card in
                presentCreateListPrompt(adding: card, selectAfterCreate: false)
            } onSearchArtist: { artist in
                Task { await model.searchArtworks(byArtist: artist) }
            } onClose: {
                model.closeSelectedCard()
            }
            .task(id: card.id) {
                async let imageCaching: Void = model.cacheDetailImages(for: card)
                async let printingLoad: Void = model.loadPrintings(for: card)
                async let valueLoad: Void = model.loadValueGuide(for: card)
                _ = await (imageCaching, printingLoad, valueLoad)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.sidebarSelection {
        case .listsOverview:
            CardListsOverviewView(
                onCreateList: {
                    presentCreateListDestination()
                },
                onSelectList: { _ in },
                onRenameList: { presentRenameListPrompt($0) }
            )
        case .newList:
            CardListCreateDestinationView(
                onCancel: {
                    model.cancelNewListCreation(returningTo: previousSidebarSelection)
                },
                onComplete: {
                    previousSidebarSelection = model.sidebarSelection
                }
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
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.undoLastListAction()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!model.canUndoListAction)
                    .help("Undo List Action")
                    .accessibilityIdentifier("undo-list-action-button")

                }
            }
        case .list:
            CardListsOverviewView(
                onCreateList: {
                    presentCreateListDestination()
                },
                onSelectList: { _ in },
                onRenameList: { presentRenameListPrompt($0) }
            )
        case .search:
            searchDestination
        }
    }

    @ViewBuilder
    private var searchDestination: some View {
        let content = SearchContentView(
            gridZoom: gridZoom,
            searchFocus: searchFocus,
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
        .navigationTitle("Search")
        .toolbarBackground(.hidden, for: .windowToolbar)

        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
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

    private func presentCreateListDestination() {
        if model.sidebarSelection != .newList {
            previousSidebarSelection = model.sidebarSelection
        }
        model.selectNewList()
    }

    private func presentCreateSearchListPrompt() {
        listNameDraft = ""
        listNameAction = .createFromSearch
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
                await model.createCardListFromCurrentSearch(named: name)
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
#endif
