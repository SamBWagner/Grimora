import GrimoraCore
import SwiftUI

/// The menu items for moving a list entry to a category (or uncategorized).
struct CardListMoveCategoryMenuContent: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var entry: CardListEntryRecord
    var categories: [CardListCategoryRecord]
    var onMoveToCategory: ((CardListCategoryRecord.ID?) -> Void)?
    var isDestinationDisabled: ((CardListCategoryRecord.ID?) -> Bool)?
    var onMoved: () -> Void = {}

    var body: some View {
        Button {
            move(to: nil)
        } label: {
            GrimoraMenuSelectionLabel(
                title: "Uncategorized",
                isSelected: entry.categoryID == nil
            )
        }
        .disabled(isMoveDisabled(to: nil))
        .accessibilityIdentifier("move-list-entry-\(entry.id)-category-uncategorized")

        if !categories.isEmpty {
            Divider()
        }

        ForEach(categories) { category in
            Button {
                move(to: category.id)
            } label: {
                GrimoraMenuSelectionLabel(
                    title: category.name,
                    isSelected: entry.categoryID == category.id
                )
            }
            .disabled(isMoveDisabled(to: category.id))
            .accessibilityIdentifier("move-list-entry-\(entry.id)-category-\(category.name)")
        }
    }

    private func move(to categoryID: CardListCategoryRecord.ID?) {
        if let onMoveToCategory {
            onMoveToCategory(categoryID)
        } else {
            model.moveCardListEntry(id: entry.id, toCategoryID: categoryID)
        }
        onMoved()
    }

    private func isMoveDisabled(to categoryID: CardListCategoryRecord.ID?) -> Bool {
        isDestinationDisabled?(categoryID) ?? (entry.categoryID == categoryID)
    }
}
