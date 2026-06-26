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
    @ScaledMetric private var controlHeight: Double = 32
    @ScaledMetric private var segmentWidth: Double = 38
    @ScaledMetric private var hitHeight: Double = 44

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
            .accessibilityLabel(quantity > 1 ? "Decrease Quantity" : "Remove from Collection")
            .accessibilityIdentifier(decrementAccessibilityIdentifier)
        }
        .frame(height: controlHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: palette.shadow.color.opacity(0.12), radius: 3, x: 0, y: 2)
        .frame(height: hitHeight)
        .fixedSize(horizontal: true, vertical: true)
        .grimoraIncreaseFeedback(trigger: incrementTrigger)
        .grimoraDecreaseFeedback(trigger: decrementTrigger)
    }

    private var quantityLabel: some View {
        Text(quantity.formatted())
            .font(.subheadline)
            .bold()
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
            .frame(width: 1, height: controlHeight * 0.5)
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
                .font(.subheadline)
                .bold()
                .foregroundStyle(foreground ?? palette.primaryText.color)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : trigger)
                .frame(width: segmentWidth, height: controlHeight)
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
        .cached(for: colorScheme)
    }
}

// MARK: - More menu

/// Consolidates the secondary card actions (add to list, move, set quantity,
/// remove) behind a single ellipsis menu so the tile only exposes the stepper
/// and this "more" control, keeping the bottom bar uncluttered.
struct CardGridMoreMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isNamingNewCategory = false

    var card: CardRecord?
    var selectedCardIDs: [CardRecord.ID] = []
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: ((CardRecord) -> Void)?
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardCollectionRecord.ID, CardRecord) -> Bool)?
    var categoryEntry: CardCollectionEntryRecord?
    var categories: [CardCollectionCategoryRecord] = []
    var onMoveToCategory: ((CardCollectionCategoryRecord.ID?) -> Void)?
    /// Creates a new category (named via the prompt) and files the entry into it.
    var onCreateCategory: ((String) -> Void)?
    var onMoveToZone: ((CardCollectionZone) -> Void)?
    var isMoveDestinationDisabled: ((CardCollectionCategoryRecord.ID?) -> Bool)?
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
        .cardCollectionNewCategoryPrompt(isPresented: $isNamingNewCategory) { name in
            onCreateCategory?(name)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let card, let onCreateListForCard {
            Menu("Add to Collection") {
                CardCollectionAddMenuContent(
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

        if let categoryEntry, onCreateCategory != nil || !categories.isEmpty || categoryEntry.categoryID != nil {
            Menu("Move to Category") {
                CardCollectionMoveCategoryMenuContent(
                    entry: categoryEntry,
                    categories: categories,
                    onMoveToCategory: onMoveToCategory,
                    isDestinationDisabled: isMoveDestinationDisabled,
                    onCreateCategory: onCreateCategory == nil ? nil : { isNamingNewCategory = true }
                )
            }
            .accessibilityIdentifier("move-list-entry-\(categoryEntry.id)-category")
        }

        if let categoryEntry {
            Menu("Move to Zone") {
                CardCollectionMoveZoneMenuContent(
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
