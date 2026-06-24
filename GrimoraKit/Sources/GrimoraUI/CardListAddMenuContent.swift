import GrimoraCore
import SwiftUI

/// The menu items for adding a card (or the active bulk selection) to a list.
/// Extracted so the same items can back both the standalone add button and the
/// consolidated more menu.
struct CardListAddMenuContent: View {
    @Environment(GrimoraAppModel.self) private var model

    var card: CardRecord
    var selectedCardIDs: [CardRecord.ID] = []
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)?
    var onAdded: () -> Void = {}

    var body: some View {
        if !model.cardLists.isEmpty {
            Section(addSectionTitle) {
                ForEach(model.cardLists) { list in
                    Button {
                        addTargetCards(to: list.id)
                    } label: {
                        Text(list.name)
                    }
                    .accessibilityIdentifier("add-card-\(card.id)-to-list-\(list.name)")
                }
            }
        }

        Button {
            createListForTargetCards()
        } label: {
            Text("New List...")
        }
        .accessibilityIdentifier("new-list-from-card-\(card.id)")
    }

    private var targetCardIDs: [CardRecord.ID] {
        let providedIDs = selectedCardIDsProvider?() ?? []
        let ids = providedIDs.isEmpty
            ? (selectedCardIDs.isEmpty ? [card.id] : selectedCardIDs)
            : providedIDs
        var seenIDs: Set<CardRecord.ID> = []
        return ids.filter { seenIDs.insert($0).inserted }
    }

    private var addSectionTitle: String {
        let count = targetCardIDs.count
        return count > 1 ? "Add \(count.formatted()) Selected Cards to List" : "Add to List"
    }

    private func addTargetCards(to listID: CardListRecord.ID) {
        if onAddCardsToList?(listID, card) == true {
            onAdded()
            return
        }

        let ids = targetCardIDs
        if ids.count == 1, ids.first == card.id {
            model.addCard(card, toListID: listID)
        } else {
            model.addCards(ids, toListID: listID)
        }
        onAdded()
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
