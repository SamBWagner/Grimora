import Foundation
import GrimoraCore
import SwiftUI

struct CardGridItemView: View {
    private static let tileCornerRadius: CGFloat = 8
    private static let rotatedArtworkGridOverflowAllowance: CGFloat = 12
    private static let bottomBarMinimumHeight: CGFloat = 60
    private static let selectionChromeHorizontalInset = CardGridSelectionChrome.horizontalContentInset

    @Environment(\.colorScheme) private var colorScheme
    @State private var hasOverflowingArtwork = false
    @State private var usesLandscapeArtworkLayout = false
    @State private var measuredTileWidth: CGFloat = 0
    @State private var isHovered = false
    @State private var openFeedbackTrigger = 0
    @State private var selectionFeedbackTrigger = 0

    var card: CardRecord
    var quantity: Int = 1
    var openAccessibilityIdentifier: String
    var accessibilityValue: String
    var showsPreviewLoadingIndicator = false
    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onIncrementQuantity: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onRemoveCompletely: (() -> Void)? = nil
    var onEditQuantity: (() -> Void)? = nil
    var removeAccessibilityIdentifier: String?
    var quantityAccessibilityIdentifier: String?
    var categoryEntry: CardListEntryRecord?
    var categories: [CardListCategoryRecord] = []
    var isSelectionEnabled = false
    var isSelectedInSelection = false
    var isActiveDetail = false
    var selectionAccessibilityIdentifier: String?
    var showsSelectionIndicator = false
    var showsSelectionIndicatorWhenSelected = true
    var usesSelectionModeGestures = false
    var selectedCardIDsForBulkActions: [CardRecord.ID] = []
    var selectedCardIDsForBulkActionsProvider: (() -> [CardRecord.ID])?
    var onSelectionInteraction: ((CardGridSelectionInteraction) -> Void)?
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)?
    var onPrepareAddMenu: ((CardRecord) -> Void)?
    var onMoveToCategory: ((CardListCategoryRecord.ID?) -> Void)?
    var onMoveToZone: ((CardListZone) -> Void)?
    var isMoveDestinationDisabled: ((CardListCategoryRecord.ID?) -> Bool)?
    var dragPayload: String?
    var dragItemCount: Int?
    var isDragEnabled = true
    var onArtworkOverflowChange: (Bool) -> Void = { _ in }
    var onArtworkLandscapeLayoutChange: (Bool) -> Void = { _ in }

    var body: some View {
        tileContent
            .cardGridSelectionChrome(
                isSelected: isSelectedInSelection,
                isActive: isActiveDetail,
                palette: palette
            )
            .grimoraGridCardInteraction(isHovered: $isHovered)
            .overlay(alignment: .topLeading) {
                selectionIndicator
                    .padding(11)
            }
            .contextMenu {
                if let onEditQuantity {
                    Button {
                        onEditQuantity()
                    } label: {
                        Text("Set Quantity")
                    }
                    .accessibilityIdentifier("set-quantity-\(categoryEntry?.id ?? card.id)")
                }
            }
            .modifier(cardDragModifier)
            .zIndex(hasOverflowingArtwork ? 10 : 0)
            .grimoraOpenFeedback(trigger: openFeedbackTrigger)
            .grimoraSelectionFeedback(trigger: selectionFeedbackTrigger)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(tileAccessibilityIdentifier)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardArtworkOpener

            bottomBar
        }
        .background {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                .fill(tileFillColor)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardGridItemWidthPreferenceKey.self,
                    value: sanitizedCardGridItemWidth(proxy.size.width)
                )
            }
        }
        .onPreferenceChange(CardGridItemWidthPreferenceKey.self) { width in
            measuredTileWidth = width
        }
        .shadow(
            color: palette.shadow.color.opacity(isHovered ? 0.18 : 0),
            radius: isHovered ? 14 : 0,
            x: 0,
            y: isHovered ? 8 : 0
        )
    }

    @ViewBuilder
    private var cardArtworkOpener: some View {
        if usesSelectionModeGestures {
            selectionModeCardArtwork
        } else {
            cardArtwork
                .cardGridPointerActivation(
                    onClick: handlePointerClick,
                    onDoubleClick: openCard,
                    onKeyboardActivate: handleKeyboardActivate,
                    onTouch: openCard,
                    dragConfiguration: pointerDragConfiguration,
                    ignoredBottomTrailingSize: CardArtworkView.controlHitSize
                )
                .modifier(cardDragModifier)
                .modifier(cardAccessibilityModifier)
        }
    }

    private var selectionModeCardArtwork: some View {
        cardArtwork
            .modifier(selectionModeActivationModifier)
            .modifier(cardAccessibilityModifier)
    }

    private var cardArtwork: some View {
        CardArtworkView(
            card: card,
            cornerRadius: Self.tileCornerRadius,
            showsPreviewLoadingIndicator: showsPreviewLoadingIndicator,
            maximumVisualWidthExpansion: Self.rotatedArtworkGridOverflowAllowance,
            onVisualOverflowChange: updateArtworkOverflow,
            onLandscapeLayoutChange: updateArtworkLandscapeLayout
        )
            .shadow(
                color: palette.shadow.color.opacity(isHovered ? 0.95 : 0.75),
                radius: isHovered ? 7 : 5,
                x: 0,
                y: isHovered ? 5 : 3
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .cardArtworkContextMenu(
                card: card,
                selectedCardIDs: selectedCardIDsForBulkActions,
                selectedCardIDsProvider: selectedCardIDsForBulkActionsProvider,
                onCreateListForCard: onCreateListForCard,
                onCreateListForCards: onCreateListForCards,
                onAddCardsToList: onAddCardsToList,
                openAction: CardArtworkContextMenuAction(
                    title: "Open Details",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    accessibilityIdentifier: "card-artwork-open-details-\(card.id)",
                    handler: openCard
                )
            )
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                leadingControls

                Spacer(minLength: 0)

                trailingControls
            }
            .padding(.horizontal, 9)
            .frame(height: Self.bottomBarMinimumHeight)

            Spacer(minLength: 0)
        }
        .frame(height: resolvedBottomBarHeight, alignment: .top)
        .modifier(CardGridEditLongPressModifier(onEditQuantity: onEditQuantity))
    }

    @ViewBuilder
    private var leadingControls: some View {
        if let onIncrementQuantity, let onRemove {
            CardGridQuantityStepper(
                quantity: quantity,
                onIncrement: onIncrementQuantity,
                onDecrement: onRemove,
                incrementAccessibilityIdentifier: "increase-list-entry-\(categoryEntry?.id ?? card.id)",
                decrementAccessibilityIdentifier: removeAccessibilityIdentifier ?? "remove-list-entry-\(card.id)",
                quantityAccessibilityIdentifier: quantityAccessibilityIdentifier ?? "card-quantity-\(card.id)"
            )
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if onIncrementQuantity != nil {
            CardGridMoreMenu(
                card: card,
                selectedCardIDs: selectedCardIDsForBulkActions,
                selectedCardIDsProvider: selectedCardIDsForBulkActionsProvider,
                onCreateListForCard: onCreateListForCard,
                onCreateListForCards: onCreateListForCards,
                onAddCardsToList: onAddCardsToList,
                categoryEntry: categoryEntry,
                categories: categories,
                onMoveToCategory: onMoveToCategory,
                onMoveToZone: onMoveToZone,
                isMoveDestinationDisabled: isMoveDestinationDisabled,
                onEditQuantity: onEditQuantity,
                onRemoveCompletely: onRemoveCompletely,
                quantity: quantity,
                accessibilityIdentifier: "more-list-entry-\(categoryEntry?.id ?? card.id)"
            )
        } else {
            CardListAddMenu(
                card: card,
                selectedCardIDs: selectedCardIDsForBulkActions,
                selectedCardIDsProvider: selectedCardIDsForBulkActionsProvider,
                onCreateListForCard: onCreateListForCard,
                onCreateListForCards: onCreateListForCards,
                onAddCardsToList: onAddCardsToList,
                onPrepareAddMenu: onPrepareAddMenu
            )
        }
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var tileFillColor: Color {
        if isActiveDetail {
            return palette.accent.color.opacity(isHovered ? 0.18 : 0.12)
        }
        return palette.cardSurface.color.opacity(isHovered ? 1 : 0.88)
    }

    private var tileAccessibilityIdentifier: String {
        "card-grid-item-\(categoryEntry?.id ?? card.id)"
    }

    private var resolvedBottomBarHeight: CGFloat {
        cardGridBottomBarHeight(
            tileWidth: measuredTileWidth,
            usesLandscapeLayout: usesLandscapeArtworkLayout,
            minimumHeight: Self.bottomBarMinimumHeight,
            landscapeLayoutHorizontalInset: Self.selectionChromeHorizontalInset
        )
    }

    private func updateArtworkOverflow(_ isOverflowing: Bool) {
        if hasOverflowingArtwork != isOverflowing {
            hasOverflowingArtwork = isOverflowing
        }
        onArtworkOverflowChange(isOverflowing)
    }

    private func updateArtworkLandscapeLayout(_ usesLandscapeLayout: Bool) {
        if usesLandscapeArtworkLayout != usesLandscapeLayout {
            usesLandscapeArtworkLayout = usesLandscapeLayout
        }
        onArtworkLandscapeLayoutChange(usesLandscapeLayout)
    }

    private var cardAccessibilityModifier: CardGridItemAccessibilityModifier {
        CardGridItemAccessibilityModifier(
            identifier: openAccessibilityIdentifier,
            label: cardAccessibilityLabel,
            value: cardAccessibilityValue,
            action: openCard
        )
    }

    private var selectionModeActivationModifier: CardGridSelectionModeActivationModifier {
        CardGridSelectionModeActivationModifier(
            onClick: handlePointerClick,
            onTouch: handleSelectionModeTap
        )
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if let selectionAccessibilityIdentifier,
           isSelectionEnabled,
           showsSelectionIndicator || (showsSelectionIndicatorWhenSelected && isSelectedInSelection) {
            CardGridSelectionIndicator(
                isSelected: isSelectedInSelection,
                palette: palette,
                accessibilityIdentifier: selectionAccessibilityIdentifier
            )
        }
    }

    private func openCard() {
        openFeedbackTrigger += 1
        onSelect(card)
    }

    private var resolvedDragCardIDs: [CardRecord.ID] {
        selectedCardIDsForBulkActions.isEmpty ? [card.id] : selectedCardIDsForBulkActions
    }

    private var resolvedDragPayload: String {
        dragPayload ?? CardDragToken.token(for: resolvedDragCardIDs)
    }

    private var resolvedDragItemCount: Int {
        max(1, dragItemCount ?? resolvedDragCardIDs.count)
    }

    private var cardDragModifier: CardGridDraggableModifier {
        CardGridDraggableModifier(
            payload: resolvedDragPayload,
            isEnabled: isDragEnabled,
            previewCard: card,
            itemCount: resolvedDragItemCount,
            palette: palette
        )
    }

    private var pointerDragConfiguration: CardGridPointerDragConfiguration? {
        guard isDragEnabled else {
            return nil
        }

        return CardGridPointerDragConfiguration(
            payload: resolvedDragPayload,
            itemCount: resolvedDragItemCount
        )
    }

    private func handleSelectionModeTap() {
        guard isSelectionEnabled, let onSelectionInteraction else {
            openCard()
            return
        }

        selectionFeedbackTrigger += 1
        onSelectionInteraction(.replace)
    }

    private func handlePointerClick(_ modifiers: CardGridPointerModifiers) {
        guard isSelectionEnabled, let onSelectionInteraction else {
            openCard()
            return
        }

        selectionFeedbackTrigger += 1
        onSelectionInteraction(CardGridSelectionInteraction(pointerModifiers: modifiers))
    }

    private func handleKeyboardActivate() {
        guard isSelectionEnabled, let onSelectionInteraction else {
            openCard()
            return
        }

        guard isSelectedInSelection else {
            selectionFeedbackTrigger += 1
            onSelectionInteraction(.replace)
            return
        }

        openCard()
    }

    private var cardAccessibilityLabel: String {
        "\(card.name), \(card.setCode.uppercased()) #\(card.collectorNumber)"
    }

    private var cardAccessibilityValue: String {
        [
            accessibilityValue,
            isSelectedInSelection ? "Selected" : nil,
            isActiveDetail ? "Showing Details" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct CardGridSelectionModeActivationModifier: ViewModifier {
    var onClick: (CardGridPointerModifiers) -> Void
    var onTouch: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.cardGridPointerActivation(
            onClick: onClick,
            onDoubleClick: { onClick(CardGridPointerModifiers()) },
            onTouch: onTouch
        )
        #else
        content.onTapGesture(perform: onTouch)
        #endif
    }
}

private struct CardGridItemAccessibilityModifier: ViewModifier {
    var identifier: String
    var label: String
    var value: String
    var action: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

struct CardGridSelectionIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isSelected: Bool
    var palette: GrimoraPalette
    var accessibilityIdentifier: String

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isSelected ? palette.accent.color : palette.secondaryText.color)
            .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
            .frame(width: 30, height: 30)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .shadow(color: palette.shadow.color.opacity(0.28), radius: 5, x: 0, y: 2)
            .allowsHitTesting(false)
            .accessibilityLabel(isSelected ? "Selected" : "Not Selected")
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct CardGridEditLongPressModifier: ViewModifier {
    var onEditQuantity: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.onLongPressGesture {
            onEditQuantity?()
        }
        #endif
    }
}

extension View {
    func cardGridSelectionChrome(
        isSelected: Bool,
        isActive: Bool = false,
        palette: GrimoraPalette
    ) -> some View {
        modifier(CardGridSelectionChrome(isSelected: isSelected, isActive: isActive, palette: palette))
    }
}

func cardGridBottomBarHeight(
    tileWidth: CGFloat,
    usesLandscapeLayout: Bool,
    minimumHeight: CGFloat = 60,
    artworkAspectRatio: CGFloat = cardArtworkAspectRatio,
    landscapeLayoutHorizontalInset: CGFloat = 0
) -> CGFloat {
    guard usesLandscapeLayout,
          tileWidth.isFinite,
          tileWidth > 0,
          artworkAspectRatio.isFinite,
          artworkAspectRatio > 0,
          artworkAspectRatio < 1
    else {
        return minimumHeight
    }

    let horizontalInset = landscapeLayoutHorizontalInset.isFinite
        ? max(0, landscapeLayoutHorizontalInset)
        : 0
    let portraitArtworkWidth = max(1, (tileWidth + horizontalInset) * artworkAspectRatio - horizontalInset)
    let portraitArtworkHeight = portraitArtworkWidth / artworkAspectRatio
    let landscapeArtworkHeight = tileWidth * artworkAspectRatio

    return max(minimumHeight, minimumHeight + portraitArtworkHeight - landscapeArtworkHeight)
}

private struct CardGridItemWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private func sanitizedCardGridItemWidth(_ width: CGFloat) -> CGFloat {
    guard width.isFinite, width > 0 else {
        return 0
    }

    return width
}

struct CardGridSelectionChrome: ViewModifier {
    private static let tileCornerRadius: CGFloat = 8
    private static let outlineGap: CGFloat = 4
    private static let outlineLineWidth: CGFloat = 3
    private static let outlinePadding = outlineGap + outlineLineWidth
    private static let outlineStrokeInset = outlineLineWidth / 2
    static let horizontalContentInset = outlinePadding * 2

    var isSelected: Bool
    var isActive: Bool = false
    var palette: GrimoraPalette

    func body(content: Content) -> some View {
        content
            .padding(Self.outlinePadding)
            .background {
                RoundedRectangle(cornerRadius: outlineCornerRadius, style: .continuous)
                    .stroke(
                        palette.accent.color.opacity(outlineOpacity),
                        lineWidth: resolvedOutlineLineWidth
                    )
                    .padding(Self.outlineStrokeInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: outlineCornerRadius, style: .continuous))
    }

    private var outlineCornerRadius: CGFloat {
        Self.tileCornerRadius + Self.outlineGap + Self.outlineLineWidth
    }

    private var outlineOpacity: Double {
        if isSelected {
            return 1
        }
        return isActive ? 0.68 : 0
    }

    private var resolvedOutlineLineWidth: CGFloat {
        isSelected ? Self.outlineLineWidth : 2
    }
}

struct CardGridDraggableModifier: ViewModifier {
    var payload: String
    var isEnabled: Bool
    var previewCard: CardRecord? = nil
    var itemCount = 1
    var palette: GrimoraPalette? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        if isEnabled {
            if let previewCard, let palette {
                content.draggable(payload) {
                    CardGridDragPreview(
                        card: previewCard,
                        count: max(1, itemCount),
                        palette: palette
                    )
                }
            } else {
                content.draggable(payload)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct CardGridDragPreview: View {
    var card: CardRecord
    var count: Int
    var palette: GrimoraPalette

    private let cardSize = CGSize(width: 96, height: 134)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if count > 1 {
                previewLayer(offset: CGSize(width: 14, height: 10), rotation: 7)
                previewLayer(offset: CGSize(width: 7, height: 5), rotation: 3)
            }

            CardArtworkView(card: card, cornerRadius: 8, showsControls: false)
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.hairline.color, lineWidth: 1)
                }
                .shadow(color: palette.shadow.color.opacity(0.36), radius: 10, x: 0, y: 6)

            if count > 1 {
                Text(count.formatted())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.primaryText.color)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(minWidth: 28, minHeight: 24)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(palette.accent.color.opacity(0.55), lineWidth: 1)
                    }
                    .offset(x: 12, y: -10)
            }
        }
        .frame(
            width: count > 1 ? cardSize.width + 22 : cardSize.width,
            height: count > 1 ? cardSize.height + 16 : cardSize.height
        )
        .accessibilityHidden(true)
    }

    private func previewLayer(offset: CGSize, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(palette.cardSurface.color.opacity(0.92))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .shadow(color: palette.shadow.color.opacity(0.22), radius: 6, x: 0, y: 4)
    }
}

enum CardListAddMenuPresentation {
    case gridOverlay
    case toolbar
    case floatingAction
    case detailAction
}

struct CardListAddMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var addFeedbackTrigger = 0

    var card: CardRecord
    var presentation: CardListAddMenuPresentation = .gridOverlay
    var accessibilityIdentifier: String?
    var selectedCardIDs: [CardRecord.ID] = []
    var selectedCardIDsProvider: (() -> [CardRecord.ID])?
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: (([CardRecord.ID]) -> Void)?
    var onAddCardsToList: ((CardListRecord.ID, CardRecord) -> Bool)?
    var onPrepareAddMenu: ((CardRecord) -> Void)?

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .gridOverlay:
            menu
                .buttonStyle(GrimoraIconButtonStyle())
                .help("Add to List")
                .accessibilityLabel("Add to List")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
                .grimoraSuccessFeedback(trigger: addFeedbackTrigger)
        case .toolbar:
            #if os(iOS) || os(visionOS)
            menu
                .help("Add to List")
                .accessibilityLabel("Add to List")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
                .grimoraSuccessFeedback(trigger: addFeedbackTrigger)
            #else
            menu
                .buttonStyle(GrimoraIconButtonStyle())
                .help("Add to List")
                .accessibilityLabel("Add to List")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
                .grimoraSuccessFeedback(trigger: addFeedbackTrigger)
            #endif
        case .floatingAction:
            menu
                .buttonStyle(GrimoraIconButtonStyle())
                .help("Add to List")
                .accessibilityLabel("Add to List")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
                .grimoraSuccessFeedback(trigger: addFeedbackTrigger)
        case .detailAction:
            menu
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Add to List")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
                .grimoraSuccessFeedback(trigger: addFeedbackTrigger)
        }
    }

    private var menu: some View {
        Menu {
            CardListAddMenuContent(
                card: card,
                selectedCardIDs: selectedCardIDs,
                selectedCardIDsProvider: selectedCardIDsProvider,
                onCreateListForCard: onCreateListForCard,
                onCreateListForCards: onCreateListForCards,
                onAddCardsToList: onAddCardsToList,
                onAdded: { addFeedbackTrigger += 1 }
            )
        } label: {
            menuLabel
        }
    }

    @ViewBuilder
    private var menuLabel: some View {
        switch presentation {
        case .gridOverlay:
            CardGridControlIcon(systemName: "plus", feedbackTrigger: addFeedbackTrigger)
                .onHover { isHovering in
                    if isHovering {
                        prepareTargetCards()
                    }
                }
        case .toolbar:
            #if os(iOS) || os(visionOS)
            Label("Add to List", systemImage: "plus")
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .accessibilityLabel("Add to List")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
            #else
            CardGridControlIcon(systemName: "plus", feedbackTrigger: addFeedbackTrigger)
            #endif
        case .floatingAction:
            GrimoraFloatingActionIcon(
                title: "Add to List",
                systemName: "plus",
                palette: palette,
                foregroundColor: palette.accent.color,
                feedbackTrigger: addFeedbackTrigger
            )
        case .detailAction:
            Label("Add to List", systemImage: "plus")
                .accessibilityIdentifier(resolvedAccessibilityIdentifier)
        }
    }

    private var resolvedAccessibilityIdentifier: String {
        accessibilityIdentifier ?? "add-card-to-list-\(card.id)"
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private func prepareTargetCards() {
        onPrepareAddMenu?(card)
    }
}

struct CardGridControlIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var systemName: String
    var foregroundColor: Color?
    var tone: GrimoraControlTone = .normal
    var feedbackTrigger = 0

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        control
            .onHover { isHovered = $0 }
        #elseif os(iOS)
        control
            .hoverEffect(.lift)
        #else
        control
        #endif
    }

    private var control: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .symbolEffect(.bounce, value: reduceMotion ? 0 : feedbackTrigger)
            .frame(width: visualSize, height: visualSize)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(strokeColor, lineWidth: 1)
            }
            .shadow(
                color: palette.shadow.color.opacity(isHovered ? 0.28 : 0.12),
                radius: isHovered ? 7 : 3,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.48)
            .animation(reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.hoverSpring, value: isHovered)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var foreground: Color {
        foregroundColor ?? tone.foregroundColor(palette: palette)
    }

    private var strokeColor: Color {
        .primary.opacity(isHovered ? 0.12 : 0.08)
    }

    private var visualSize: CGFloat {
        #if os(visionOS)
        38
        #else
        32
        #endif
    }

    private var hitSize: CGFloat {
        #if os(visionOS)
        60
        #else
        44
        #endif
    }
}

