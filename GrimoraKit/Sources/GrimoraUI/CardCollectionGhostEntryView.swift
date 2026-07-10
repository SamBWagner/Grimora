import GrimoraCore
import SwiftUI

/// Shared look and actions for a card drawn in a category it's only *tagged* into. The card
/// lives in its primary category; this is a dimmed reference, so it offers no quantity controls,
/// no selection, and no drag — only the two things you'd want from here: promote this category to
/// primary, or drop the tag.
private struct CardCollectionGhostEntryActions: View {
    @Environment(GrimoraAppModel.self) private var model

    var entry: CardCollectionEntryRecord
    var category: CardCollectionCategoryRecord
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label("Open Details", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityIdentifier("ghost-list-entry-\(entry.id)-open")

        Divider()

        Button {
            model.makePrimaryCategory(entryID: entry.id, categoryID: category.id)
        } label: {
            Label("Move Here", systemImage: "folder")
        }
        .accessibilityIdentifier("ghost-list-entry-\(entry.id)-make-primary")

        Button(role: .destructive) {
            model.toggleSecondaryCategory(entryID: entry.id, categoryID: category.id)
        } label: {
            Label("Remove from \(category.name)", systemImage: "tag.slash")
        }
        .accessibilityIdentifier("ghost-list-entry-\(entry.id)-remove-tag")
    }
}

/// The grid presentation of a ghost: the artwork at reduced contrast, badged with the category
/// the card actually lives in.
struct CardCollectionGhostGridItemView: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let tileCornerRadius: CGFloat = 8

    var entry: CardCollectionEntryRecord
    var card: CardRecord
    var category: CardCollectionCategoryRecord
    var primaryCategoryName: String?
    var onOpen: () -> Void

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    var body: some View {
        tileContent
            .contentShape(RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous))
            .onTapGesture { onOpen() }
            .contextMenu {
                CardCollectionGhostEntryActions(
                    entry: entry,
                    category: category,
                    onOpen: onOpen
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("ghost-list-entry-\(entry.id)")
            .accessibilityLabel(card.name)
            .accessibilityValue(accessibilityValue)
            .accessibilityAction { onOpen() }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            dimmedArtwork

            homeCaption
        }
        .background {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                .fill(palette.cardSurface.color.opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                .strokeBorder(
                    palette.hairline.color,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        }
    }

    private var dimmedArtwork: some View {
        CardArtworkView(
            card: card,
            cornerRadius: Self.tileCornerRadius,
            showsControls: false
        )
        .frame(maxWidth: .infinity)
        .saturation(0.35)
        .opacity(0.5)
        .overlay(alignment: .topTrailing) {
            homeBadge
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    private var homeBadge: some View {
        Image(systemName: "tag.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(palette.secondaryText.color.opacity(0.85), in: Circle())
    }

    private var homeCaption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(card.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(homeText)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var homeText: String {
        guard let primaryCategoryName else {
            return "Filed under Uncategorized"
        }
        return "Filed under \(primaryCategoryName)"
    }

    private var accessibilityValue: String {
        "\(homeText). Tagged into \(category.name)."
    }
}

/// The text-mode presentation of a ghost — same reduced-contrast treatment, row-shaped.
struct CardCollectionGhostTextRowView: View {
    var entry: CardCollectionEntryRecord
    var card: CardRecord?
    var category: CardCollectionCategoryRecord
    var primaryCategoryName: String?
    var palette: GrimoraPalette
    var onOpen: () -> Void

    var body: some View {
        rowContent
            .padding(.vertical, 6)
            .opacity(0.65)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .contextMenu {
                CardCollectionGhostEntryActions(
                    entry: entry,
                    category: category,
                    onOpen: onOpen
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("ghost-list-text-row-\(entry.id)")
            .accessibilityLabel(card?.name ?? entry.cardID)
            .accessibilityValue("\(homeText). Tagged into \(category.name).")
            .accessibilityAction { onOpen() }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(card?.name ?? entry.cardID)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(homeText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)
        }
    }

    private var homeText: String {
        guard let primaryCategoryName else {
            return "Filed under Uncategorized"
        }
        return "Filed under \(primaryCategoryName)"
    }
}
