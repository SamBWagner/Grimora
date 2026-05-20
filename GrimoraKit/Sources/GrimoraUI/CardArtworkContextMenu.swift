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
        onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)? = nil,
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
                openAction: openAction
            )
        )
    }
}

private struct CardArtworkContextMenuModifier: ViewModifier {
    @EnvironmentObject private var model: GrimoraAppModel

    var card: CardRecord
    var selectedCardIDs: [CardRecord.ID]
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)?
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
                    openAction: openAction
                )
                .environmentObject(model)
            }
    }
}

private struct CardArtworkContextMenuContent: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var card: CardRecord
    var selectedCardIDs: [CardRecord.ID]
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)?
    var openAction: CardArtworkContextMenuAction?

    var body: some View {
        shareMenu

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
            Label("Create New List", systemImage: "plus.rectangle.on.folder")
        }
        .accessibilityIdentifier("card-artwork-create-list-\(card.id)")

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
            Label("Add to List", systemImage: "text.badge.plus")
        }
        .accessibilityIdentifier("card-artwork-add-to-list-menu-\(card.id)")
    }

    private var availableLists: [CardListRecord] {
        model.cardLists.filter { !model.isProtectedFavouritesList($0) }
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

    private func addTargetCards(to listID: CardListRecord.ID) {
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
