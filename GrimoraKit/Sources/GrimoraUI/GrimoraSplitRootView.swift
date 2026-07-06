import GrimoraCore
import SwiftUI

#if os(macOS)
@Observable
@MainActor
public final class GrimoraSearchFocusController {
    public static let shared = GrimoraSearchFocusController()

    var focusRequestID = 0
    var advancedSearchRequestID = 0

    public init() {}

    public func focusSearch() {
        focusRequestID += 1
    }

    /// Bumped by the ⇧⌘F menu command so the search content view presents the
    /// Advanced Search sheet, mirroring the in-field launch button.
    public func presentAdvancedSearch() {
        advancedSearchRequestID += 1
    }
}

struct MacRootView: View {
    var body: some View {
        SplitRootView()
    }
}

private struct SplitRootView: View {
    @Environment(GrimoraAppModel.self) private var model
    @State private var gridZoom = GridZoomController()
    @State private var searchFocus = GrimoraSearchFocusController.shared
    @State private var listCommands = GrimoraCollectionCommandController()
    @State private var libraryMaintenance = GrimoraLibraryMaintenanceController()
    @State private var listNameAction: CollectionNameAction?
    @State private var previousSidebarSelection: GrimoraSidebarSelection = .search
    @State private var listNameDraft = ""

    /// Resting width of the detail pane — drag-adjustable and persisted. The pane
    /// opens at this width; double-clicking the divider grows it to the maximized
    /// "fit the card" width and back.
    @AppStorage("cardDetailPaneNormalWidth") private var detailPaneNormalWidth: Double = 440
    @State private var isDetailPaneMaximized = false
    @State private var windowSize: CGSize = .zero
    @State private var detailContentMinWidth: CGFloat = 0

    private static let sidebarMinimumWidth: CGFloat = 160
    private static let sidebarIdealWidth: CGFloat = 190
    private static let centerColumnIdealWidth: CGFloat = 320
    private static let inspectorMinimumWidth: CGFloat = 320
    // Card art renders at Scryfall "large" (~672pt); cap the pane so the artwork
    // fills it without upscaling past the source resolution.
    private static let inspectorNativeArtworkWidth: CGFloat = 672
    // Chrome around the artwork inside the scrolling layout: the `.padding()` on
    // `detailLayout` horizontally, plus breathing room above/below vertically.
    private static let inspectorArtworkHorizontalInsets: CGFloat = 32
    private static let inspectorArtworkVerticalInsets: CGFloat = 48

    var body: some View {
        navigationContent
        .focusedSceneValue(\.gridZoomController, gridZoom)
        .focusedSceneValue(\.listCommandController, listCommands)
        .focusedSceneValue(\.appModel, model)
        .focusedSceneValue(\.libraryMaintenanceController, libraryMaintenance)
        .environment(libraryMaintenance)
        .libraryMaintenanceConfirmationDialog(controller: libraryMaintenance)
        .onAppear {
            GridZoomController.activeForCommands = gridZoom
        }
        .onChange(of: searchFocus.focusRequestID) { _, _ in
            model.selectSearch()
        }
        .onChange(of: model.selectedCard?.id) { _, _ in
            // Each newly opened card starts at the resting width so double-clicking
            // the divider grows it.
            isDetailPaneMaximized = false
        }
        .onChange(of: listCommands.renameRequest?.id) { _, _ in
            guard let list = listCommands.consumeRenameRequest() else {
                return
            }
            presentRenameListPrompt(list)
        }
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

    private var navigationContent: some View {
        HStack(spacing: 0) {
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
                    // iCloud sync is global, so this lives at the detail-column level —
                    // present in the window toolbar across the dashboard, search, and any
                    // open collection alike (joining the per-collection Undo button).
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task { await model.syncWithCloudNow() }
                            } label: {
                                if model.isPerformingCloudSync {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Sync with iCloud", systemImage: "arrow.triangle.2.circlepath")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            .disabled(!model.canSyncWithCloudNow || model.isPerformingCloudSync)
                            .help(model.isPerformingCloudSync ? "Syncing with iCloud…" : "Sync with iCloud")
                            .accessibilityIdentifier("sync-with-icloud-button")
                        }
                    }
            }

            if model.selectedCard != nil {
                detailPaneColumn
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: model.selectedCard?.id)
        // Read the window content size without wrapping the NavigationSplitView in
        // a GeometryReader (which can disturb toolbar plumbing). The background's
        // size equals the HStack's, and is independent of the pane width, so this
        // can't form a layout loop.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { windowSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in
                        windowSize = newValue
                    }
            }
        }
    }

    private var detailPaneColumn: some View {
        let width = effectiveDetailWidth(for: windowSize)
        return HStack(spacing: 0) {
            CardDetailPaneDivider(
                currentWidth: width,
                minWidth: Self.inspectorMinimumWidth,
                maxWidth: maximizedDetailWidth(for: windowSize),
                onResize: { newWidth in
                    isDetailPaneMaximized = false
                    detailPaneNormalWidth = Double(newWidth)
                },
                onToggleMaximized: {
                    withAnimation(.snappy) {
                        isDetailPaneMaximized.toggle()
                    }
                }
            )
            cardDetailInspector
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .onPreferenceChange(CardDetailContentMinWidthKey.self) { value in
                    detailContentMinWidth = value ?? 0
                }
        }
    }

    /// The width that makes the card art as big as the window height allows.
    private func maximizedDetailWidth(for size: CGSize) -> CGFloat {
        cardDetailMaximizedPaneWidth(
            paneHeight: size.height,
            windowWidth: size.width,
            minWidth: Self.inspectorMinimumWidth,
            nativeCardWidth: Self.inspectorNativeArtworkWidth,
            reservedLeadingWidth: Self.sidebarMinimumWidth + centerColumnMinimumWidth,
            horizontalInsets: Self.inspectorArtworkHorizontalInsets,
            verticalInsets: Self.inspectorArtworkVerticalInsets
        )
    }

    private func effectiveDetailWidth(for size: CGSize) -> CGFloat {
        let maxWidth = maximizedDetailWidth(for: size)
        let resting = min(max(CGFloat(detailPaneNormalWidth), Self.inspectorMinimumWidth), maxWidth)
        let base = isDetailPaneMaximized ? maxWidth : resting
        // Honour content that needs more room than the pane currently offers
        // (the wide "Show All" expanded printings browser).
        return max(base, detailContentMinWidth)
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
                presentationStyle: .inspector,
                onSelectPrinting: { printing in
                    model.selectPrinting(printing)
                },
                selectedFinish: { model.selectedFinish(for: $0) },
                onSetFinish: { printing, finish in
                    model.setFinish(finish, for: printing)
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
                onClose: {
                    model.closeSelectedCard()
                }
            )
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
            CardCollectionsOverviewView(
                gridZoom: gridZoom,
                onCreateList: {
                    presentCreateListDestination()
                },
                onSelectList: { _ in },
                onRenameList: { presentRenameListPrompt($0) }
            )
        case .newList:
            CardCollectionCreateDestinationView(
                onCancel: {
                    model.cancelNewListCreation(returningTo: previousSidebarSelection)
                },
                onComplete: {
                    previousSidebarSelection = model.sidebarSelection
                }
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
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.undoLastListAction()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!model.canUndoListAction)
                    .help("Undo Collection Action")
                    .accessibilityIdentifier("undo-list-action-button")

                }
            }
        case .list:
            CardCollectionsOverviewView(
                gridZoom: gridZoom,
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
            }
        )
        .navigationTitle("Cards")
        .toolbarBackground(.hidden, for: .windowToolbar)

        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
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
                await model.createCardCollectionFromCurrentSearch(named: name)
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
#endif
