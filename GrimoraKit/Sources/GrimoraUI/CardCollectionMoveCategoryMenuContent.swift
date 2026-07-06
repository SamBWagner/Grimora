import GrimoraCore
import SwiftUI

/// The menu items for moving a list entry to a category (or uncategorized).
struct CardCollectionMoveCategoryMenuContent: View {
    @Environment(GrimoraAppModel.self) private var model

    var entry: CardCollectionEntryRecord
    var categories: [CardCollectionCategoryRecord]
    var onMoveToCategory: ((CardCollectionCategoryRecord.ID?) -> Void)?
    var isDestinationDisabled: ((CardCollectionCategoryRecord.ID?) -> Bool)?
    /// When provided, surfaces a "New Category…" item that lets the user file
    /// this entry into a brand-new category without leaving the card's context.
    var onCreateCategory: (() -> Void)?
    var onMoved: () -> Void = {}

    var body: some View {
        if let onCreateCategory {
            Button(action: onCreateCategory) {
                Label("New Category…", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("move-list-entry-\(entry.id)-new-category")

            Divider()
        }

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

        CardCollectionSecondaryCategoryMenuSection(
            entry: entry,
            categories: categories,
            onChanged: onMoved
        )
    }

    private func move(to categoryID: CardCollectionCategoryRecord.ID?) {
        if let onMoveToCategory {
            onMoveToCategory(categoryID)
        } else {
            model.moveCardCollectionEntry(id: entry.id, toCategoryID: categoryID)
        }
        onMoved()
    }

    private func isMoveDisabled(to categoryID: CardCollectionCategoryRecord.ID?) -> Bool {
        isDestinationDisabled?(categoryID) ?? (entry.categoryID == categoryID)
    }
}

/// The "Also in…" portion of a card's category menu: toggle any number of secondary-category
/// tags (same-zone categories other than the primary) and promote one to primary. Secondary
/// tags don't move the card between sections — they're labels for organizing and filtering.
struct CardCollectionSecondaryCategoryMenuSection: View {
    @Environment(GrimoraAppModel.self) private var model

    var entry: CardCollectionEntryRecord
    var categories: [CardCollectionCategoryRecord]
    var onChanged: () -> Void = {}

    var body: some View {
        let taggable = categories.filter { $0.zone == entry.zone && $0.id != entry.categoryID }
        if !taggable.isEmpty {
            Section("Also in") {
                ForEach(taggable) { category in
                    Button {
                        model.toggleSecondaryCategory(entryID: entry.id, categoryID: category.id)
                        onChanged()
                    } label: {
                        GrimoraMenuSelectionLabel(
                            title: category.name,
                            isSelected: entry.secondaryCategoryIDs.contains(category.id)
                        )
                    }
                    .accessibilityIdentifier("tag-list-entry-\(entry.id)-category-\(category.name)")
                }
            }

            let secondaryCategories = taggable.filter { entry.secondaryCategoryIDs.contains($0.id) }
            if !secondaryCategories.isEmpty {
                Menu("Make Primary") {
                    ForEach(secondaryCategories) { category in
                        Button {
                            model.makePrimaryCategory(entryID: entry.id, categoryID: category.id)
                            onChanged()
                        } label: {
                            Text(category.name)
                        }
                        .accessibilityIdentifier("make-primary-list-entry-\(entry.id)-category-\(category.name)")
                    }
                }
            }
        }
    }
}
