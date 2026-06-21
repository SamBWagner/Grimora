import GrimoraCore
import SwiftUI

// MARK: - Quantity stepper

/// A combined "−  qty  +" control that groups the quantity-adjustment buttons
/// into a single capsule, mirroring the stepper pattern people expect from
/// deck builders like Archidekt. The quantity number is only shown when there
/// is more than one copy, matching the previous quantity-badge behaviour.
struct CardGridQuantityStepper: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var incrementTrigger = 0
    @State private var decrementTrigger = 0
    @State private var hoveredSegment: Segment?

    var quantity: Int
    var onIncrement: () -> Void
    var onDecrement: () -> Void
    var incrementAccessibilityIdentifier: String
    var decrementAccessibilityIdentifier: String
    var quantityAccessibilityIdentifier: String

    private enum Segment {
        case decrement
        case increment
    }

    private static let controlHeight: CGFloat = 32
    private static let segmentWidth: CGFloat = 38
    private static let hitHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            segment(
                systemName: "plus",
                segment: .increment,
                trigger: incrementTrigger,
                foreground: nil
            ) {
                incrementTrigger += 1
                onIncrement()
            }
            .accessibilityLabel("Increase Quantity")
            .accessibilityIdentifier(incrementAccessibilityIdentifier)

            if quantity > 1 {
                divider
                quantityLabel
            }

            divider

            segment(
                systemName: "minus",
                segment: .decrement,
                trigger: decrementTrigger,
                foreground: .red
            ) {
                decrementTrigger += 1
                onDecrement()
            }
            .accessibilityLabel(quantity > 1 ? "Decrease Quantity" : "Remove from List")
            .accessibilityIdentifier(decrementAccessibilityIdentifier)
        }
        .frame(height: Self.controlHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: palette.shadow.color.opacity(0.12), radius: 3, x: 0, y: 2)
        .frame(height: Self.hitHeight)
        .fixedSize(horizontal: true, vertical: true)
        .grimoraIncreaseFeedback(trigger: incrementTrigger)
        .grimoraDecreaseFeedback(trigger: decrementTrigger)
    }

    private var quantityLabel: some View {
        Text(quantity.formatted())
            .font(.system(size: 14, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.primaryText.color)
            .frame(minWidth: 20)
            .padding(.horizontal, 3)
            .accessibilityLabel("Quantity")
            .accessibilityValue(quantity.formatted())
            .accessibilityIdentifier(quantityAccessibilityIdentifier)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.hairline.color)
            .frame(width: 1, height: Self.controlHeight * 0.5)
    }

    private func segment(
        systemName: String,
        segment: Segment,
        trigger: Int,
        foreground: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground ?? palette.primaryText.color)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : trigger)
                .frame(width: Self.segmentWidth, height: Self.controlHeight)
                .background(hoveredSegment == segment ? palette.accent.color.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovering in
            if isHovering {
                hoveredSegment = segment
            } else if hoveredSegment == segment {
                hoveredSegment = nil
            }
        }
        #endif
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

// MARK: - More menu

/// Consolidates the secondary card actions (add to list, move, set quantity,
/// remove) behind a single ellipsis menu so the tile only exposes the stepper
/// and this "more" control, keeping the bottom bar uncluttered.
struct CardGridMoreMenu: View {
    @Environment(\.colorScheme) private var colorScheme

    var card: CardRecord?
    var selectedCardIDs: [CardRecord.ID] = []
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: ((CardRecord) -> Void)?
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)?
    var categoryEntry: CardListEntryRecord?
    var categories: [CardListCategoryRecord] = []
    var onMoveToCategory: ((CardListCategoryRecord.ID?) -> Void)?
    var onMoveToZone: ((CardListZone) -> Void)?
    var isMoveDestinationDisabled: ((CardListCategoryRecord.ID?) -> Bool)?
    var onEditQuantity: (() -> Void)?
    var onRemoveCompletely: (() -> Void)?
    var quantity = 1
    var accessibilityIdentifier: String

    var body: some View {
        Menu {
            menuContent
        } label: {
            CardGridControlIcon(systemName: "ellipsis")
        }
        .buttonStyle(GrimoraIconButtonStyle())
        .help("More Actions")
        .accessibilityLabel("More Actions")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var menuContent: some View {
        if let card, let onCreateListForCard {
            Menu("Add to List") {
                CardListAddMenuContent(
                    card: card,
                    selectedCardIDs: selectedCardIDs,
                    selectedCardIDsProvider: selectedCardIDsProvider,
                    onCreateListForCard: onCreateListForCard,
                    onCreateListForCards: onCreateListForCards,
                    onAddCardsToList: onAddCardsToList
                )
            }
            .accessibilityIdentifier("\(accessibilityIdentifier)-add-to-list")
        }

        if let categoryEntry, !categories.isEmpty || categoryEntry.categoryID != nil {
            Menu("Move to Category") {
                CardListMoveCategoryMenuContent(
                    entry: categoryEntry,
                    categories: categories,
                    onMoveToCategory: onMoveToCategory,
                    isDestinationDisabled: isMoveDestinationDisabled
                )
            }
            .accessibilityIdentifier("move-list-entry-\(categoryEntry.id)-category")
        }

        if let categoryEntry {
            Menu("Move to Zone") {
                CardListMoveZoneMenuContent(
                    entry: categoryEntry,
                    onMoveToZone: onMoveToZone
                )
            }
            .accessibilityIdentifier("move-list-entry-\(categoryEntry.id)-zone")
        }

        if let onEditQuantity {
            Button("Set Quantity", action: onEditQuantity)
                .accessibilityIdentifier("\(accessibilityIdentifier)-set-quantity")
        }

        if let onRemoveCompletely {
            Divider()
            Button("Remove", role: .destructive, action: onRemoveCompletely)
                .accessibilityIdentifier("\(accessibilityIdentifier)-remove")
        }
    }
}

// MARK: - Shared menu content

/// The menu items for adding a card (or the active bulk selection) to a list.
/// Extracted so the same items can back both the standalone add button and the
/// consolidated more menu.
struct CardListAddMenuContent: View {
    @EnvironmentObject private var model: GrimoraAppModel

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

/// The menu items for moving a list entry to a different zone.
struct CardListMoveZoneMenuContent: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var entry: CardListEntryRecord
    var onMoveToZone: ((CardListZone) -> Void)?
    var onMoved: () -> Void = {}

    var body: some View {
        ForEach(availableZones) { zone in
            Button {
                move(to: zone)
            } label: {
                HStack {
                    Text(zone.title)
                    if entry.zone == zone {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(entry.zone == zone)
            .accessibilityIdentifier("move-list-entry-\(entry.id)-zone-\(zone.rawValue)")
        }
    }

    private var availableZones: [CardListZone] {
        (model.selectedList?.ruleset ?? .none).allowedZones
    }

    private func move(to zone: CardListZone) {
        if let onMoveToZone {
            onMoveToZone(zone)
        } else {
            model.moveCardListEntry(id: entry.id, toZone: zone)
        }
        onMoved()
    }
}
