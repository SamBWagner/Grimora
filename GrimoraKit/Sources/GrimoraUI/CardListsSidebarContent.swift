import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardListsSidebarContent: View {
    @Environment(GrimoraAppModel.self) private var model

    var lists: [CardListRecord]
    var isPinnedSection: Bool
    var emptyTitle: String
    var emptyAccessibilityIdentifier: String
    var palette: GrimoraPalette
    @Binding var draggedListID: CardListRecord.ID?
    var onRenameList: (CardListRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lists.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier(emptyAccessibilityIdentifier)
                    #if os(macOS)
                    .onDrop(
                        of: CardListDropDelegate.supportedContentTypes,
                        delegate: CardListDropDelegate(
                            targetList: nil,
                            targetIsPinned: isPinnedSection,
                            lists: lists,
                            draggedListID: $draggedListID,
                            model: model
                        )
                    )
                    #endif
            } else {
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    CardListSidebarRow(
                        list: list,
                        listIndex: index,
                        listCount: lists.count,
                        sectionLists: lists,
                        isPinnedSection: isPinnedSection,
                        palette: palette,
                        draggedListID: $draggedListID,
                        isSelected: model.sidebarSelection == .list(list.id),
                        onSelect: { model.selectCardList(id: list.id) },
                        onRename: { onRenameList(list) },
                        onTogglePin: {
                            model.setCardListPinned(id: list.id, isPinned: !list.isPinned)
                        },
                        onDelete: { model.deleteCardList(id: list.id) }
                    )
                }
            }
        }
    }
}

struct CardListSidebarRow: View {
    @Environment(GrimoraAppModel.self) private var model

    var list: CardListRecord
    var listIndex: Int
    var listCount: Int
    var sectionLists: [CardListRecord]
    var isPinnedSection: Bool
    var palette: GrimoraPalette
    @Binding var draggedListID: CardListRecord.ID?
    var isSelected: Bool
    var onSelect: () -> Void
    var onRename: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    #if os(macOS)
    @State private var isPinButtonHovered = false
    #endif
    @State private var isRowHovered = false
    @State private var selectionFeedbackTrigger = 0

    var body: some View {
        let isProtected = model.isProtectedFavouritesList(list)

        HStack(spacing: 8) {
            if isProtected {
                Image(systemName: "star.fill")
                    .foregroundStyle(pinColor)
                    .frame(width: 16, height: 16)
            } else if list.isPinned {
                #if os(macOS)
                Button {
                    onTogglePin()
                } label: {
                    pinButtonLabel
                }
                .buttonStyle(GrimoraIconButtonStyle())
                .contentShape(Rectangle())
                .onHover { isPinButtonHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isPinButtonHovered)
                .help("Unpin")
                .accessibilityLabel("Unpin \(list.name)")
                .accessibilityHint("Unpins this list")
                .accessibilityIdentifier("unpin-list-pin-\(list.name)")
                .contextMenu {
                    listActionMenuContent
                }
                #else
                pinImage
                #endif
            }

            HStack(spacing: 8) {
                Text(list.name)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(entryCountText)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            #if os(macOS)
            .onDrop(
                of: CardListDropDelegate.supportedContentTypes,
                delegate: CardListDropDelegate(
                    targetList: list,
                    targetIsPinned: isPinnedSection,
                    lists: sectionLists,
                    draggedListID: $draggedListID,
                    model: model
                )
            )
            .contextMenu {
                if !isProtected {
                    listActionMenuContent
                }
            }
            #endif
        }
        .font(.callout.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? palette.primaryText.color : palette.secondaryText.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? palette.selectedAccent.color.opacity(0.58) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? palette.accent.color.opacity(0.32) : Color.clear, lineWidth: 1)
        }
        .grimoraSidebarRowHover(isHovered: $isRowHovered, palette: palette, isSelected: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2) {
            if !isProtected {
                onRename()
            }
        }
        .onTapGesture {
            selectionFeedbackTrigger += 1
            onSelect()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("card-list-row-\(list.name)")
        .accessibilityValue(entryCountText)
        .grimoraSelectionFeedback(trigger: selectionFeedbackTrigger)
        #if os(macOS)
        .draggableList(if: !isProtected, draggedListID: $draggedListID, listID: list.id)
        .onDrop(
            of: CardListDropDelegate.supportedContentTypes,
            delegate: CardListDropDelegate(
                targetList: list,
                targetIsPinned: isPinnedSection,
                lists: sectionLists,
                draggedListID: $draggedListID,
                model: model
            )
        )
        .contextMenu {
            if !isProtected {
                listActionMenuContent
            }
        }
        #endif
    }

    #if os(macOS)
    private var pinButtonLabel: some View {
        Image(systemName: isPinButtonHovered ? "pin.slash.fill" : "pin.fill")
            .foregroundStyle(isPinButtonHovered ? palette.accent.color : pinColor)
            .frame(width: 16, height: 16)
            .frame(width: 24, height: 24)
            .background {
                Circle()
                    .fill(isPinButtonHovered ? palette.accent.color.opacity(isSelected ? 0.22 : 0.14) : Color.clear)
            }
    }
    #endif

    private var pinImage: some View {
        Image(systemName: "pin.fill")
            .foregroundStyle(pinColor)
            .frame(width: 16, height: 16)
    }

    private var pinColor: Color {
        isSelected ? palette.primaryText.color : palette.secondaryText.color
    }

    @ViewBuilder
    private var listActionMenuContent: some View {
        Button {
            onTogglePin()
        } label: {
            Text(list.isPinned ? "Unpin" : "Pin")
        }
        .accessibilityIdentifier("\(list.isPinned ? "unpin" : "pin")-list-\(list.name)")

        if !isFirst || !isLast {
            Divider()

            if !isFirst {
                Button {
                    model.moveCardList(id: list.id, toPosition: 0, isPinned: list.isPinned)
                } label: {
                    Text("Move to Top")
                }
                .accessibilityIdentifier("move-list-top-\(list.name)")

                Button {
                    model.moveCardList(id: list.id, by: -1)
                } label: {
                    Text("Move Up")
                }
                .accessibilityIdentifier("move-list-up-\(list.name)")
            }

            if !isLast {
                Button {
                    model.moveCardList(id: list.id, by: 1)
                } label: {
                    Text("Move Down")
                }
                .accessibilityIdentifier("move-list-down-\(list.name)")

                Button {
                    model.moveCardList(id: list.id, toPosition: listCount - 1, isPinned: list.isPinned)
                } label: {
                    Text("Move to Bottom")
                }
                .accessibilityIdentifier("move-list-bottom-\(list.name)")
            }
        }

        Divider()

        Button {
            onRename()
        } label: {
            Text("Rename")
        }
        .accessibilityIdentifier("rename-list-\(list.name)")

        Button(role: .destructive) {
            onDelete()
        } label: {
            Text("Delete")
        }
        .accessibilityIdentifier("delete-list-\(list.name)")
    }

    private var entryCountText: String {
        let noun = list.entryCount == 1 ? "card" : "cards"
        return "\(list.entryCount.formatted()) \(noun)"
    }

    private var isFirst: Bool {
        listIndex == 0
    }

    private var isLast: Bool {
        listIndex == listCount - 1
    }
}

private struct CardListDropDelegate: DropDelegate {
    static let listUTType = UTType(exportedAs: "com.grimora.card-list")
    static let supportedContentTypes = [listUTType] + CardDropTokenLoader.supportedContentTypes

    var targetList: CardListRecord?
    var targetIsPinned: Bool
    var lists: [CardListRecord]
    @Binding var draggedListID: CardListRecord.ID?
    var model: GrimoraAppModel

    static func dragProvider(for listID: CardListRecord.ID) -> NSItemProvider {
        let token = CardListDragToken.token(for: listID)
        let provider = NSItemProvider(object: token as NSString)
        provider.registerDataRepresentation(
            forTypeIdentifier: listUTType.identifier,
            visibility: .all
        ) { completion in
            completion(token.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    static func isListDragToken(_ value: String) -> Bool {
        CardListDragToken.isListDragToken(value)
    }

    func dropEntered(info: DropInfo) {
        moveDraggedListIfNeeded()
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedListID = nil
        }

        guard draggedListID == nil else {
            moveDraggedListIfNeeded()
            return true
        }

        guard let targetList else {
            return false
        }

        let providers = info.itemProviders(for: CardDropTokenLoader.supportedContentTypes)
        guard !providers.isEmpty else {
            return false
        }

        return CardDropTokenLoader.loadCardIDs(from: providers) { cardIDs in
            model.addCards(cardIDs, toListID: targetList.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggedListID == nil ? .copy : .move)
    }

    private func moveDraggedListIfNeeded() {
        guard let draggedListID else {
            return
        }
        if let targetList, model.isProtectedFavouritesList(targetList) {
            return
        }

        if targetList?.id == draggedListID,
           targetList?.isPinned == targetIsPinned {
            return
        }

        let targetIndex: Int
        if let targetList,
           let listIndex = lists.firstIndex(where: { $0.id == targetList.id }) {
            targetIndex = listIndex
        } else {
            targetIndex = lists.count
        }

        model.moveCardList(id: draggedListID, toPosition: targetIndex, isPinned: targetIsPinned)
    }
}

#if os(macOS)
private extension View {
    @ViewBuilder
    func draggableList(
        if isEnabled: Bool,
        draggedListID: Binding<CardListRecord.ID?>,
        listID: CardListRecord.ID
    ) -> some View {
        if isEnabled {
            onDrag {
                draggedListID.wrappedValue = listID
                return CardListDropDelegate.dragProvider(for: listID)
            }
        } else {
            self
        }
    }
}
#endif
