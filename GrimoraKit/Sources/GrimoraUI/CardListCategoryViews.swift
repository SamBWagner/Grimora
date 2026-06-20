import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardListCategorySectionView: View {
    @State private var dropFeedbackTrigger = 0

    var section: CardListEntrySection
    var palette: GrimoraPalette
    var isCollapsed: Bool
    var onToggleCollapsed: () -> Void
    var onMoveEntriesToCategory: ([CardListEntryRecord.ID]) -> Void
    var onRenameCategory: (CardListCategoryRecord) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: section.category == nil ? "tray" : "folder")
                .foregroundStyle(palette.secondaryText.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if let category = section.category {
                            onRenameCategory(category)
                        }
                    }

                Text(section.entryCountText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onToggleCollapsed) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .frame(width: collapseControlSize, height: collapseControlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText.color)
            .help(isCollapsed ? "Show Category" : "Collapse Category")
            .accessibilityLabel(isCollapsed ? "Show Category" : "Collapse Category")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityIdentifier("toggle-list-category-collapse-\(section.title)")

            if let category = section.category {
                CardListCategoryMovementControls(
                    category: category,
                    categoryIndex: section.categoryIndex ?? 0,
                    categoryCount: section.categoryCount,
                    palette: palette,
                    showsMoveToTop: false,
                    onRenameCategory: onRenameCategory
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list-category-section-\(section.title)")
        #if os(macOS) || os(iOS) || os(visionOS)
        .dropDestination(for: String.self) { tokens, _ in
            let entryIDs = CardListEntryDragToken.entryIDs(from: tokens)
            guard !entryIDs.isEmpty else {
                return false
            }
            onMoveEntriesToCategory(entryIDs)
            dropFeedbackTrigger += 1
            return true
        }
        .grimoraDropSuccessFeedback(trigger: dropFeedbackTrigger)
        #endif
    }

    private var collapseControlSize: CGFloat {
        #if os(macOS)
        26
        #else
        44
        #endif
    }
}

struct CardListCategoryReorderView: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var draggedCategoryID: CardListCategoryRecord.ID?

    var categories: [CardListCategoryRecord]
    var palette: GrimoraPalette
    var onRenameCategory: (CardListCategoryRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                CardListCategoryReorderRow(
                    category: category,
                    categoryIndex: index,
                    categoryCount: categories.count,
                    palette: palette,
                    draggedCategoryID: $draggedCategoryID,
                    model: model,
                    categories: categories,
                    onRenameCategory: onRenameCategory
                )
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardListCategoryReorderRow: View {
    var category: CardListCategoryRecord
    var categoryIndex: Int
    var categoryCount: Int
    var palette: GrimoraPalette
    @Binding var draggedCategoryID: CardListCategoryRecord.ID?
    var model: GrimoraAppModel
    var categories: [CardListCategoryRecord]
    var onRenameCategory: (CardListCategoryRecord) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondaryText.color.opacity(0.72))
                .frame(width: 18)
                .help("Drag Category")
                .accessibilityLabel("Drag Category")

            Image(systemName: "folder")
                .foregroundStyle(palette.secondaryText.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(1)

                Text(entryCountText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            CardListCategoryMovementControls(
                category: category,
                categoryIndex: categoryIndex,
                categoryCount: categoryCount,
                palette: palette,
                showsMoveToTop: true,
                onRenameCategory: onRenameCategory
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.cardSurface.color.opacity(isDragging ? 0.44 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDragging ? palette.accent.color.opacity(0.52) : palette.hairline.color, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        #if os(macOS)
        .onDrag {
            draggedCategoryID = category.id
            return NSItemProvider(object: Self.dragToken(for: category.id) as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: CardListCategoryDropDelegate(
                targetCategory: category,
                categories: categories,
                draggedCategoryID: $draggedCategoryID,
                model: model
            )
        )
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compact-list-category-row-\(category.name)")
    }

    private var isDragging: Bool {
        draggedCategoryID == category.id
    }

    private var entryCountText: String {
        let count = category.entryCount
        let noun = count == 1 ? "card" : "cards"
        return "\(count.formatted()) \(noun)"
    }

    private static func dragToken(for categoryID: CardListCategoryRecord.ID) -> String {
        CardListCategoryDropDelegate.dragTokenPrefix + categoryID
    }
}

struct CardListCategoryDropDelegate: DropDelegate {
    static let dragTokenPrefix = "grimora-category:"

    var targetCategory: CardListCategoryRecord
    var categories: [CardListCategoryRecord]
    @Binding var draggedCategoryID: CardListCategoryRecord.ID?
    var model: GrimoraAppModel

    func dropEntered(info: DropInfo) {
        moveDraggedCategoryIfNeeded()
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedCategoryID = nil
        }

        moveDraggedCategoryIfNeeded()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private func moveDraggedCategoryIfNeeded() {
        guard let draggedCategoryID,
              draggedCategoryID != targetCategory.id,
              categories.contains(where: { $0.id == draggedCategoryID }),
              let toIndex = categories.firstIndex(where: { $0.id == targetCategory.id })
        else {
            return
        }

        model.moveCardListCategory(id: draggedCategoryID, toPosition: toIndex)
    }
}

struct CardListCategoryMovementControls: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var category: CardListCategoryRecord
    var categoryIndex: Int
    var categoryCount: Int
    var palette: GrimoraPalette
    var showsMoveToTop: Bool
    var onRenameCategory: (CardListCategoryRecord) -> Void

    private var isFirst: Bool {
        categoryIndex == 0
    }

    private var isLast: Bool {
        categoryIndex == categoryCount - 1
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsMoveToTop {
                Button {
                    model.moveCardListCategory(id: category.id, toPosition: 0)
                } label: {
                    Image(systemName: "arrow.up.to.line")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText.color)
                .disabled(isFirst)
                .help("Move to Top")
                .accessibilityLabel("Move to Top")
                .accessibilityIdentifier("move-list-category-top-\(category.name)")
            }

            Button {
                model.moveCardListCategory(id: category.id, by: -1)
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText.color)
            .disabled(isFirst)
            .help("Move Up")
            .accessibilityLabel("Move Up")
            .accessibilityIdentifier("move-list-category-up-\(category.name)")

            categoryActionsMenu

            Button {
                model.moveCardListCategory(id: category.id, by: 1)
            } label: {
                Image(systemName: "arrow.down")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText.color)
            .disabled(isLast)
            .help("Move Down")
            .accessibilityLabel("Move Down")
            .accessibilityIdentifier("move-list-category-down-\(category.name)")
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var categoryActionsMenu: some View {
        Menu {
            Button {
                onRenameCategory(category)
            } label: {
                Text("Rename")
            }
            .accessibilityIdentifier("rename-list-category-\(category.name)")

            Button {
                model.moveCardListCategory(id: category.id, toPosition: 0)
            } label: {
                Text("Move to Top")
            }
            .disabled(isFirst)
            .accessibilityIdentifier("move-list-category-top-\(category.name)")

            Button {
                model.moveCardListCategory(id: category.id, toPosition: categoryCount - 1)
            } label: {
                Text("Move to Bottom")
            }
            .disabled(isLast)
            .accessibilityIdentifier("move-list-category-bottom-\(category.name)")

            Divider()

            Button(role: .destructive) {
                model.deleteCardListCategory(id: category.id)
            } label: {
                Text("Delete")
            }
            .accessibilityIdentifier("delete-list-category-\(category.name)")
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryText.color)
        .help("Category Actions")
        .accessibilityLabel("Category Actions")
        .accessibilityIdentifier("list-category-actions-\(category.name)")
    }
}

struct CardListEmptyCategoryView: View {
    var palette: GrimoraPalette
    var onMoveEntriesToCategory: ([CardListEntryRecord.ID]) -> Void

    var body: some View {
        Text("No Cards")
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText.color)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
            .background(palette.cardSurface.color.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .accessibilityIdentifier("empty-list-category")
            #if os(macOS) || os(iOS) || os(visionOS)
            .dropDestination(for: String.self) { tokens, _ in
                let entryIDs = CardListEntryDragToken.entryIDs(from: tokens)
                guard !entryIDs.isEmpty else {
                    return false
                }
                onMoveEntriesToCategory(entryIDs)
                return true
            }
            #endif
    }
}

struct CardListMoveCategoryMenu: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var moveFeedbackTrigger = 0

    var entry: CardListEntryRecord
    var categories: [CardListCategoryRecord]
    var onMoveToCategory: ((CardListCategoryRecord.ID?) -> Void)?
    var isDestinationDisabled: ((CardListCategoryRecord.ID?) -> Bool)?

    var body: some View {
        if !categories.isEmpty || entry.categoryID != nil {
            HStack(spacing: 5) {
                Menu {
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
                } label: {
                    CardGridControlIcon(
                        systemName: "folder.badge.gearshape",
                        feedbackTrigger: moveFeedbackTrigger
                    )
                }
                .buttonStyle(GrimoraIconButtonStyle())
                .help("Move to Category")
                .accessibilityLabel("Move to Category")
                .accessibilityIdentifier("move-list-entry-\(entry.id)-category")
                .id("\(entry.id)-category-menu-\(entry.categoryID ?? CardListEntrySection.uncategorizedID)")
                .grimoraSelectionFeedback(trigger: moveFeedbackTrigger)
            }
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    private func move(to categoryID: CardListCategoryRecord.ID?) {
        if let onMoveToCategory {
            onMoveToCategory(categoryID)
        } else {
            model.moveCardListEntry(id: entry.id, toCategoryID: categoryID)
        }
        moveFeedbackTrigger += 1
    }

    private func isMoveDisabled(to categoryID: CardListCategoryRecord.ID?) -> Bool {
        isDestinationDisabled?(categoryID) ?? (entry.categoryID == categoryID)
    }
}

struct CardListMoveZoneMenu: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var moveFeedbackTrigger = 0

    var entry: CardListEntryRecord
    var onMoveToZone: ((CardListZone) -> Void)?

    var body: some View {
        Menu {
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
        } label: {
            CardGridControlIcon(
                systemName: "rectangle.3.group",
                feedbackTrigger: moveFeedbackTrigger
            )
        }
        .buttonStyle(GrimoraIconButtonStyle())
        .help("Move to Zone")
        .accessibilityLabel("Move to Zone")
        .accessibilityIdentifier("move-list-entry-\(entry.id)-zone")
        .grimoraSelectionFeedback(trigger: moveFeedbackTrigger)
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
        moveFeedbackTrigger += 1
    }
}

struct MissingCardListEntryView: View {
    @State private var isHovered = false
    @State private var selectionFeedbackTrigger = 0

    var entry: CardListEntryRecord
    var categories: [CardListCategoryRecord] = []
    var palette: GrimoraPalette
    var onIncrementQuantity: () -> Void
    var onRemove: () -> Void
    var onRemoveCompletely: () -> Void
    var onEditQuantity: (() -> Void)?
    var isSelectionEnabled = false
    var isSelectedInSelection = false
    var selectionAccessibilityIdentifier: String?
    var showsSelectionIndicator = false
    var usesSelectionModeGestures = false
    var onSelectionInteraction: ((CardGridSelectionInteraction) -> Void)?
    var onMoveToCategory: ((CardListCategoryRecord.ID?) -> Void)?
    var onMoveToZone: ((CardListZone) -> Void)?
    var isMoveDestinationDisabled: ((CardListCategoryRecord.ID?) -> Bool)?
    var dragPayload: String?
    var dragItemCount: Int?
    var isDragEnabled = true

    var body: some View {
        tileContent
            .cardGridSelectionChrome(isSelected: isSelectedInSelection, palette: palette)
            .grimoraGridCardInteraction(isHovered: $isHovered)
            .overlay(alignment: .topLeading) {
                selectionIndicator
                    .padding(11)
            }
            .onLongPressGesture {
                onEditQuantity?()
            }
            .contextMenu {
                if let onEditQuantity {
                    Button {
                        onEditQuantity()
                    } label: {
                        Text("Set Quantity")
                    }
                    .accessibilityIdentifier("set-quantity-\(entry.id)")
                }
            }
            .modifier(
                CardGridDraggableModifier(
                    payload: resolvedDragPayload,
                    isEnabled: isDragEnabled,
                    itemCount: resolvedDragItemCount
                )
            )
            .grimoraSelectionFeedback(trigger: selectionFeedbackTrigger)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.placeholderFill.color.opacity(0.65))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "questionmark.rectangle.portrait")
                            .font(.largeTitle)
                        Text("Unavailable Print")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(palette.secondaryText.color)
                }
                .aspectRatio(0.716, contentMode: .fit)
                .padding([.top, .horizontal], 7)
                .contentShape(Rectangle())
                .cardGridPointerActivation(
                    onClick: handlePointerClick,
                    onDoubleClick: {},
                    onTouch: nil,
                    dragConfiguration: usesSelectionModeGestures ? nil : pointerDragConfiguration
                )
                .onTapGesture {
                    handleSelectionModeTap()
                }

            bottomBar
        }
        .background(palette.cardSurface.color.opacity(isHovered ? 1 : 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(
            color: palette.shadow.color.opacity(isHovered ? 0.16 : 0),
            radius: isHovered ? 14 : 0,
            x: 0,
            y: isHovered ? 8 : 0
        )
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                identityLabel
                    .frame(minWidth: 72, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .cardGridPointerActivation(
                        onClick: handlePointerClick,
                        onDoubleClick: {},
                        onTouch: nil,
                        dragConfiguration: usesSelectionModeGestures ? nil : pointerDragConfiguration
                    )
                    .onTapGesture {
                        handleSelectionModeTap()
                    }

                controls
            }

            VStack(alignment: .leading, spacing: 8) {
                identityLabel
                    .contentShape(Rectangle())
                    .cardGridPointerActivation(
                        onClick: handlePointerClick,
                        onDoubleClick: {},
                        onTouch: nil,
                        dragConfiguration: usesSelectionModeGestures ? nil : pointerDragConfiguration
                    )
                    .onTapGesture {
                        handleSelectionModeTap()
                    }

                controls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 8)
        .padding(.bottom, 9)
    }

    private var identityLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Unavailable Print")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)

            Text(entry.cardID)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedDragPayload: String {
        dragPayload ?? CardDragToken.token(for: [entry.cardID])
    }

    private var resolvedDragItemCount: Int {
        max(1, dragItemCount ?? 1)
    }

    private var pointerDragConfiguration: CardGridPointerDragConfiguration {
        CardGridPointerDragConfiguration(
            payload: resolvedDragPayload,
            itemCount: resolvedDragItemCount
        )
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if let selectionAccessibilityIdentifier,
           isSelectionEnabled,
           showsSelectionIndicator || isSelectedInSelection {
            CardGridSelectionIndicator(
                isSelected: isSelectedInSelection,
                palette: palette,
                accessibilityIdentifier: selectionAccessibilityIdentifier
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 5) {
            if entry.quantity > 1 {
                CardGridQuantityBadge(
                    quantity: entry.quantity,
                    accessibilityIdentifier: "quantity-list-entry-\(entry.id)"
                )
            }

            CardListMoveCategoryMenu(
                entry: entry,
                categories: categories,
                onMoveToCategory: onMoveToCategory,
                isDestinationDisabled: isMoveDestinationDisabled
            )

            CardListMoveZoneMenu(
                entry: entry,
                onMoveToZone: onMoveToZone
            )

            CardGridAddButton(
                action: onIncrementQuantity,
                accessibilityIdentifier: "increase-list-entry-\(entry.id)"
            )

            CardGridRemoveButton(
                action: onRemove,
                removeCompletelyAction: onRemoveCompletely,
                quantity: entry.quantity,
                accessibilityIdentifier: "remove-list-entry-\(entry.id)"
            )
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func handlePointerClick(_ modifiers: CardGridPointerModifiers) {
        guard isSelectionEnabled, let onSelectionInteraction else {
            return
        }

        selectionFeedbackTrigger += 1
        onSelectionInteraction(CardGridSelectionInteraction(pointerModifiers: modifiers))
    }

    private func handleSelectionModeTap() {
        guard usesSelectionModeGestures,
              isSelectionEnabled,
              let onSelectionInteraction
        else {
            return
        }

        selectionFeedbackTrigger += 1
        onSelectionInteraction(.replace)
    }
}
