import GrimoraCore
import SwiftUI

struct CardArtworkContextMenuAction {
    var title: String
    var systemImage: String
    var accessibilityIdentifier: String
    var handler: () -> Void
}

extension View {
    func cardArtworkContextMenu(
        card: CardRecord,
        selectedCardIDs: [CardRecord.ID] = [],
        selectedCardIDsProvider: (() -> [CardRecord.ID])? = nil,
        onCreateListForCard: @escaping (CardRecord) -> Void,
        onCreateListForCards: (([CardRecord.ID]) -> Void)? = nil,
        onAddCardsToList: ((CardCollectionRecord.ID, CardRecord) -> Bool)? = nil,
        categoryEntry: CardCollectionEntryRecord? = nil,
        categories: [CardCollectionCategoryRecord] = [],
        onMoveToCategory: ((CardCollectionCategoryRecord.ID?) -> Void)? = nil,
        onCreateCategory: ((String) -> Void)? = nil,
        isMoveDestinationDisabled: ((CardCollectionCategoryRecord.ID?) -> Bool)? = nil,
        openAction: CardArtworkContextMenuAction? = nil
    ) -> some View {
        modifier(
            CardArtworkContextMenuModifier(
                card: card,
                selectedCardIDs: selectedCardIDs,
                selectedCardIDsProvider: selectedCardIDsProvider,
                onCreateListForCard: onCreateListForCard,
                onCreateListForCards: onCreateListForCards,
                onAddCardsToList: onAddCardsToList,
                categoryEntry: categoryEntry,
                categories: categories,
                onMoveToCategory: onMoveToCategory,
                onCreateCategory: onCreateCategory,
                isMoveDestinationDisabled: isMoveDestinationDisabled,
                openAction: openAction
            )
        )
    }
}

private struct CardArtworkContextMenuModifier: ViewModifier {
    @Environment(GrimoraAppModel.self) private var model
    @State private var isRefinementPresented = false
    @State private var refinementPresentationID = 0
    @State private var pendingAlwaysHiddenRefinement: SearchRefinement?
    @State private var isNamingNewCategory = false

    var card: CardRecord
    var selectedCardIDs: [CardRecord.ID]
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardCollectionRecord.ID, CardRecord) -> Bool)?
    var categoryEntry: CardCollectionEntryRecord?
    var categories: [CardCollectionCategoryRecord]
    var onMoveToCategory: ((CardCollectionCategoryRecord.ID?) -> Void)?
    var onCreateCategory: ((String) -> Void)?
    var isMoveDestinationDisabled: ((CardCollectionCategoryRecord.ID?) -> Bool)?
    var openAction: CardArtworkContextMenuAction?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                CardArtworkContextMenuContent(
                    card: card,
                    selectedCardIDs: selectedCardIDs,
                    selectedCardIDsProvider: selectedCardIDsProvider,
                    onCreateListForCard: onCreateListForCard,
                    onCreateListForCards: onCreateListForCards,
                    onAddCardsToList: onAddCardsToList,
                    categoryEntry: categoryEntry,
                    categories: categories,
                    onMoveToCategory: onMoveToCategory,
                    onCreateCategory: onCreateCategory == nil ? nil : { isNamingNewCategory = true },
                    isMoveDestinationDisabled: isMoveDestinationDisabled,
                    openAction: openAction,
                    onRefineSearch: presentRefinement,
                    onAlwaysHide: { pendingAlwaysHiddenRefinement = $0 }
                )
                .environment(model)
            }
            .cardCollectionNewCategoryPrompt(isPresented: $isNamingNewCategory) { name in
                onCreateCategory?(name)
            }
            .popover(isPresented: $isRefinementPresented, arrowEdge: .bottom) {
                SearchRefinementPanel(
                    groups: model.candidateRefinements(for: card),
                    currentQuery: currentQuery,
                    onApply: applyRefinements,
                    onCancel: { isRefinementPresented = false }
                )
                .id(refinementPresentationID)
                .presentationCompactAdaptation(.sheet)
            }
            .confirmationDialog(
                "Always Hide Matching Cards?",
                isPresented: alwaysHideConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingAlwaysHiddenRefinement
            ) { refinement in
                Button("Always Hide", role: .destructive) {
                    model.addHiddenTerm(refinement)
                    pendingAlwaysHiddenRefinement = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAlwaysHiddenRefinement = nil
                }
            } message: { refinement in
                Text("Cards matching “\(refinement.displayLabel)” will be excluded from every search and synced through iCloud. You can undo this in Settings → Always Hidden.")
            }
    }

    private var currentQuery: String {
        model.submittedSearchText
    }

    private var alwaysHideConfirmationPresented: Binding<Bool> {
        Binding {
            pendingAlwaysHiddenRefinement != nil
        } set: { isPresented in
            if !isPresented {
                pendingAlwaysHiddenRefinement = nil
            }
        }
    }

    private func presentRefinement() {
        refinementPresentationID += 1
        isRefinementPresented = true
    }

    private func applyRefinements(_ updates: [SearchRefinementUpdate]) {
        model.applySearchRefinements(updates)
        isRefinementPresented = false
    }
}

private struct CardArtworkContextMenuContent: View {
    @Environment(GrimoraAppModel.self) private var model

    var card: CardRecord
    var selectedCardIDs: [CardRecord.ID]
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardCollectionRecord.ID, CardRecord) -> Bool)?
    var categoryEntry: CardCollectionEntryRecord?
    var categories: [CardCollectionCategoryRecord] = []
    var onMoveToCategory: ((CardCollectionCategoryRecord.ID?) -> Void)?
    var onCreateCategory: (() -> Void)?
    var isMoveDestinationDisabled: ((CardCollectionCategoryRecord.ID?) -> Bool)?
    var openAction: CardArtworkContextMenuAction?
    var onRefineSearch: () -> Void
    var onAlwaysHide: (SearchRefinement) -> Void

    var body: some View {
        let refinementGroups = model.candidateRefinements(for: card)

        shareMenu

        CardBuyMenu(card: card)

        Divider()

        Button {
            model.addCardsToFavourites(targetCardIDs, primaryCard: card)
        } label: {
            Label("Add to Favourites", systemImage: "star")
        }
        .accessibilityIdentifier("card-artwork-add-favourites-\(card.id)")

        if !availableLists.isEmpty {
            addToListMenu
        }

        Button {
            createListForTargetCards()
        } label: {
            Label("Create New Collection", systemImage: "plus.rectangle.on.folder")
        }
        .accessibilityIdentifier("card-artwork-create-list-\(card.id)")

        moveCategoryMenu

        if !refinementGroups.isEmpty {
            Divider()
            Button(action: onRefineSearch) {
                Label("Refine Search…", systemImage: "checklist")
            }
            .accessibilityIdentifier("card-artwork-refine-search-\(card.id)")

            alwaysHideMenu(groups: refinementGroups)
        }

        if let openAction {
            Divider()

            Button {
                openAction.handler()
            } label: {
                Label(openAction.title, systemImage: openAction.systemImage)
            }
            .accessibilityIdentifier(openAction.accessibilityIdentifier)
        }
    }

    private var shareMenu: some View {
        Menu {
            ShareLink(item: shareContent.scryfallURL) {
                Label("Link", systemImage: "link")
            }
            .accessibilityIdentifier("card-artwork-share-link-\(card.id)")

            if let imageShareItem = shareContent.imageShareItem {
                ShareLink(item: imageShareItem, preview: SharePreview(imageShareItem.filename)) {
                    Label("Image", systemImage: "photo")
                }
                .accessibilityIdentifier("card-artwork-share-image-\(card.id)")
            } else {
                Label("Image", systemImage: "photo")
                    .disabled(true)
                    .accessibilityIdentifier("card-artwork-share-image-unavailable-\(card.id)")
            }

            ShareLink(item: shareContent.detailsMarkdown) {
                Label("Details", systemImage: "doc.text")
            }
            .accessibilityIdentifier("card-artwork-share-details-\(card.id)")
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("card-artwork-share-menu-\(card.id)")
    }

    @ViewBuilder
    private var moveCategoryMenu: some View {
        if let categoryEntry,
           onCreateCategory != nil || !categories.isEmpty || categoryEntry.categoryID != nil {
            Divider()

            Menu {
                CardCollectionMoveCategoryMenuContent(
                    entry: categoryEntry,
                    categories: categories,
                    onMoveToCategory: onMoveToCategory,
                    isDestinationDisabled: isMoveDestinationDisabled,
                    onCreateCategory: onCreateCategory
                )
            } label: {
                Label("Move to Category", systemImage: "folder")
            }
            .accessibilityIdentifier("card-artwork-move-category-\(categoryEntry.id)")
        }
    }

    private var addToListMenu: some View {
        Menu {
            ForEach(availableLists) { list in
                Button {
                    addTargetCards(to: list.id)
                } label: {
                    Text(list.name)
                }
                .accessibilityIdentifier("card-artwork-add-\(card.id)-to-list-\(list.name)")
            }
        } label: {
            Label("Add to Collection", systemImage: "text.badge.plus")
        }
        .accessibilityIdentifier("card-artwork-add-to-list-menu-\(card.id)")
    }

    private func alwaysHideMenu(groups: [SearchRefinementGroup]) -> some View {
        Menu {
            ForEach(groups) { group in
                Menu(group.title) {
                    ForEach(group.refinements) { refinement in
                        Button(refinement.displayLabel) {
                            onAlwaysHide(refinement)
                        }
                    }
                }
            }
        } label: {
            Label("Always Hide…", systemImage: "eye.slash")
        }
        .accessibilityIdentifier("card-artwork-always-hide-\(card.id)")
    }

    private var availableLists: [CardCollectionRecord] {
        model.cardCollections.filter { !model.isProtectedFavouritesList($0) }
    }

    private var shareContent: CardShareContent {
        CardShareContent(card: card)
    }

    private var targetCardIDs: [CardRecord.ID] {
        let providedIDs = selectedCardIDsProvider?() ?? []
        let ids = providedIDs.isEmpty
            ? (selectedCardIDs.isEmpty ? [card.id] : selectedCardIDs)
            : providedIDs
        var seenIDs: Set<CardRecord.ID> = []
        return ids.filter { seenIDs.insert($0).inserted }
    }

    private func addTargetCards(to listID: CardCollectionRecord.ID) {
        if onAddCardsToList?(listID, card) == true {
            return
        }

        let ids = targetCardIDs
        if ids.count == 1 {
            if ids.first == card.id {
                model.addCard(card, toListID: listID)
            } else if let cardID = ids.first {
                model.addCardID(cardID, toListID: listID)
            }
        } else {
            model.addCards(ids, toListID: listID)
        }
    }

    private func createListForTargetCards() {
        let ids = targetCardIDs
        if ids.count > 1, let onCreateListForCards {
            onCreateListForCards(ids)
        } else {
            onCreateListForCard(card)
        }
    }
}
