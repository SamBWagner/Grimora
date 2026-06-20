import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardListDetailView {
    var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    func makeListDetailSnapshot() -> CardListDetailSnapshot {
        let visibleEntries = model.searchedSelectedListEntries ?? model.selectedListEntries
        let totalCount = model.selectedList?.entryCount ?? model.selectedListEntries.reduce(0) { $0 + $1.quantity }
        return CardListDetailSnapshot(
            entries: visibleEntries,
            categories: model.selectedListCategories,
            ruleset: model.selectedList?.ruleset ?? .none,
            displaySortMode: model.selectedList?.displaySortMode,
            displaySortDirection: model.selectedList?.displaySortDirection ?? .ascending,
            collapsedSectionIDs: collapsedListCategoryIDs,
            isSearchActive: isListSearchActive,
            totalEntryCount: totalCount
        )
    }

    var selectedListEntryCountText: String {
        let count = listEntrySelection.selectedIDs.count
        return "\(count.formatted()) selected"
    }

    var isListSearchActive: Bool {
        !GrimoraSearchHistoryStore.normalizedQuery(model.selectedListSearchText).isEmpty
    }

    var listSearchUnsupportedMessage: String? {
        guard isListSearchActive else {
            return nil
        }

        return model.selectedListSearchUnsupportedMessage
    }

    func isSectionCollapsed(_ section: CardListEntrySection) -> Bool {
        collapsedListCategoryIDs.contains(section.id)
    }

    func toggleCollapsedSection(_ section: CardListEntrySection) {
        if collapsedListCategoryIDs.contains(section.id) {
            collapsedListCategoryIDs.remove(section.id)
        } else {
            collapsedListCategoryIDs.insert(section.id)
        }
    }

    func collapseAllSections(_ snapshot: CardListDetailSnapshot) {
        collapsedListCategoryIDs = Set(snapshot.sections.map(\.id))
    }

    func unfoldAllSections() {
        collapsedListCategoryIDs = []
    }

    var currentSelectionDragRect: CGRect? {
        guard let selectionDragStart, let selectionDragLocation else {
            return nil
        }

        return CGRect(
            x: min(selectionDragStart.x, selectionDragLocation.x),
            y: min(selectionDragStart.y, selectionDragLocation.y),
            width: abs(selectionDragStart.x - selectionDragLocation.x),
            height: abs(selectionDragStart.y - selectionDragLocation.y)
        )
    }

    @ViewBuilder
    func listEntryView(
        _ entry: CardListEntryRecord,
        displayedEntries: [CardListEntryRecord]
    ) -> some View {
        listEntryContent(entry, displayedEntries: displayedEntries)
            .modifier(
                CardListEntryFrameReportingModifier(
                    isEnabled: isSelectingListEntries,
                    entryID: entry.id,
                    coordinateSpaceName: Self.entrySelectionCoordinateSpace
                )
            )
            .zIndex(raisedArtworkEntryID == entry.id ? 100 : 0)
    }

    @ViewBuilder
    func listEntryTextRowView(_ entry: CardListEntryRecord) -> some View {
        listEntryTextRowContent(entry)
            .modifier(
                CardListEntryFrameReportingModifier(
                    isEnabled: isSelectingListEntries,
                    entryID: entry.id,
                    coordinateSpaceName: Self.entrySelectionCoordinateSpace
                )
            )
    }

    @ViewBuilder
    func listEntryContent(
        _ entry: CardListEntryRecord,
        displayedEntries: [CardListEntryRecord]
    ) -> some View {
        if let card = entry.card {
            let imageQuality = gridZoom.visibleImageQuality
            let dragEntryIDs = bulkTargetEntryIDs(for: entry)
            VisiblePreviewLoadingObserver(
                entry: model.visiblePreviewLoadingEntry(
                    for: card,
                    quality: imageQuality
                ),
                card: card
            ) { accessibilityValue, showsPreviewLoadingIndicator in
                CardGridItemView(
                    card: card,
                    quantity: entry.quantity,
                    openAccessibilityIdentifier: "open-list-entry-\(entry.id)",
                    accessibilityValue: accessibilityValue,
                    showsPreviewLoadingIndicator: showsPreviewLoadingIndicator,
                    onSelect: { selectedCard in
                        model.selectCard(selectedCard, fromListEntryID: entry.id)
                    },
                    onCreateListForCard: onCreateListForCard,
                    onIncrementQuantity: { incrementEntries(triggeredBy: entry) },
                    onRemove: { decreaseEntries(triggeredBy: entry) },
                    onRemoveCompletely: { removeEntries(triggeredBy: entry) },
                    onEditQuantity: { beginQuantityEdit(triggeredBy: entry) },
                    removeAccessibilityIdentifier: "remove-list-entry-\(entry.id)",
                    quantityAccessibilityIdentifier: "quantity-list-entry-\(entry.id)",
                    categoryEntry: entry,
                    categories: model.selectedListCategories,
                    isSelectionEnabled: true,
                    isSelectedInSelection: listEntrySelection.selectedIDs.contains(entry.id),
                    isActiveDetail: isDetailActive(for: entry, card: card),
                    selectionAccessibilityIdentifier: "select-list-entry-\(entry.id)",
                    showsSelectionIndicator: isSelectingListEntries,
                    usesSelectionModeGestures: isSelectingListEntries,
                    selectedCardIDsForBulkActionsProvider: {
                        bulkTargetCardIDs(for: entry)
                    },
                    onSelectionInteraction: { interaction in
                        applyListEntrySelectionInteraction(id: entry.id, interaction: interaction, card: card)
                    },
                    onCreateListForCards: onCreateListForCards,
                    onMoveToCategory: { categoryID in
                        moveEntryIDs(dragEntryIDs, toCategoryID: categoryID)
                    },
                    onMoveToZone: { zone in
                        moveEntryIDs(dragEntryIDs, toZone: zone)
                    },
                    isMoveDestinationDisabled: { categoryID in
                        isMoveDestinationDisabled(targetEntryIDs: dragEntryIDs, categoryID: categoryID)
                    },
                    dragPayload: CardListEntryDragToken.token(for: dragEntryIDs),
                    dragItemCount: dragEntryIDs.count,
                    isDragEnabled: !isSelectingListEntries,
                    onArtworkOverflowChange: { isOverflowing in
                        updateRaisedArtworkEntry(entryID: entry.id, isOverflowing: isOverflowing)
                    },
                    onArtworkLandscapeLayoutChange: { usesLandscapeLayout in
                        updateLandscapeArtworkEntry(
                            entryID: entry.id,
                            usesLandscapeLayout: usesLandscapeLayout
                        )
                    }
                )
            }
            .modifier(
                CardListVisibleImageCachingModifier(
                    entryID: entry.id,
                    card: card,
                    quality: imageQuality,
                    displayedEntries: displayedEntries
                )
            )
        } else {
            let dragEntryIDs = bulkTargetEntryIDs(for: entry)
            MissingCardListEntryView(
                entry: entry,
                categories: model.selectedListCategories,
                palette: palette,
                onIncrementQuantity: { incrementEntries(triggeredBy: entry) },
                onRemove: { decreaseEntries(triggeredBy: entry) },
                onRemoveCompletely: { removeEntries(triggeredBy: entry) },
                onEditQuantity: { beginQuantityEdit(triggeredBy: entry) },
                isSelectionEnabled: true,
                isSelectedInSelection: listEntrySelection.selectedIDs.contains(entry.id),
                selectionAccessibilityIdentifier: "select-list-entry-\(entry.id)",
                showsSelectionIndicator: isSelectingListEntries,
                usesSelectionModeGestures: isSelectingListEntries,
                onSelectionInteraction: { interaction in
                    applyListEntrySelectionInteraction(id: entry.id, interaction: interaction)
                },
                onMoveToCategory: { categoryID in
                    moveEntryIDs(dragEntryIDs, toCategoryID: categoryID)
                },
                onMoveToZone: { zone in
                    moveEntryIDs(dragEntryIDs, toZone: zone)
                },
                isMoveDestinationDisabled: { categoryID in
                    isMoveDestinationDisabled(targetEntryIDs: dragEntryIDs, categoryID: categoryID)
                },
                dragPayload: CardListEntryDragToken.token(for: dragEntryIDs),
                dragItemCount: dragEntryIDs.count,
                isDragEnabled: !isSelectingListEntries
            )
        }
    }

    @ViewBuilder
    func listEntryTextRowContent(_ entry: CardListEntryRecord) -> some View {
        let dragEntryIDs = bulkTargetEntryIDs(for: entry)
        CardListTextRowView(
            entry: entry,
            card: entry.card,
            categories: model.selectedListCategories,
            palette: palette,
            onOpen: {
                if let card = entry.card {
                    model.selectCard(card, fromListEntryID: entry.id)
                }
            },
            onIncrementQuantity: { incrementEntries(triggeredBy: entry) },
            onRemove: { decreaseEntries(triggeredBy: entry) },
            onRemoveCompletely: { removeEntries(triggeredBy: entry) },
            onEditQuantity: { beginQuantityEdit(triggeredBy: entry) },
            isSelectionEnabled: true,
            isSelectedInSelection: listEntrySelection.selectedIDs.contains(entry.id),
            isActiveDetail: isDetailActive(for: entry, card: entry.card),
            selectionAccessibilityIdentifier: "select-list-entry-\(entry.id)",
            showsSelectionIndicator: isSelectingListEntries,
            usesSelectionModeGestures: isSelectingListEntries,
            onSelectionInteraction: { interaction in
                applyListEntrySelectionInteraction(id: entry.id, interaction: interaction, card: entry.card)
            },
            onMoveToCategory: { categoryID in
                moveEntryIDs(dragEntryIDs, toCategoryID: categoryID)
            },
            onMoveToZone: { zone in
                moveEntryIDs(dragEntryIDs, toZone: zone)
            },
            isMoveDestinationDisabled: { categoryID in
                isMoveDestinationDisabled(targetEntryIDs: dragEntryIDs, categoryID: categoryID)
            },
            dragPayload: CardListEntryDragToken.token(for: dragEntryIDs),
            dragItemCount: dragEntryIDs.count,
            isDragEnabled: !isSelectingListEntries
        )
    }

    func updateRaisedArtworkEntry(entryID: CardListEntryRecord.ID, isOverflowing: Bool) {
        if isOverflowing {
            raisedArtworkEntryID = entryID
        } else if raisedArtworkEntryID == entryID {
            raisedArtworkEntryID = nil
        }
    }

    func updateLandscapeArtworkEntry(
        entryID: CardListEntryRecord.ID,
        usesLandscapeLayout: Bool
    ) {
        if usesLandscapeLayout {
            landscapeArtworkEntryIDs.insert(entryID)
        } else {
            landscapeArtworkEntryIDs.remove(entryID)
        }
    }

    func keepLandscapeArtworkEntriesVisible() {
        landscapeArtworkEntryIDs.formIntersection(Set(renderedListEntryIDs))
    }

    func isDetailActive(for entry: CardListEntryRecord, card: CardRecord?) -> Bool {
        if model.selectedCardListEntryID == entry.id {
            return true
        }
        return model.selectedCardListEntryID == nil && model.selectedCard?.id == card?.id
    }
}

private struct CardListEntryFrameReportingModifier: ViewModifier {
    var isEnabled: Bool
    var entryID: CardListEntryRecord.ID
    var coordinateSpaceName: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CardListEntryFramePreferenceKey.self,
                            value: [
                                entryID: proxy.frame(in: .named(coordinateSpaceName))
                            ]
                        )
                    }
                }
        } else {
            content
        }
    }
}
