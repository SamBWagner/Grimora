import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardCollectionDetailView {
    var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    /// The Scanned special list hides category/zone affordances on its cards.
    var isScannedCollection: Bool {
        model.selectedCollection.map { model.isScannedList($0) } ?? false
    }

    func makeListDetailSnapshot() -> CardCollectionDetailSnapshot {
        let totalCount = model.selectedCollectionEntryTotal
        let collapsed = collapsedListCategoryIDs
        let list = model.selectedCollection
        let showsGhosts = list?.showsMultiCategoryCards ?? false
        // A drag needs somewhere to land: while one is in flight over the collection, every
        // shadowed category comes back as a drop target.
        let revealsShadowed = dragReveal.isRevealing

        // Active collection search: regroup the (small) search-result set in-body — the cached
        // sections describe the full list, not the filtered matches.
        if isListSearchActive {
            let visibleEntries = model.searchedSelectedListEntries ?? model.selectedCollectionEntries
            let sections = CardCollectionEntrySectionBuilder.sections(
                entries: visibleEntries,
                categories: model.selectedCollectionCategories,
                ruleset: list?.ruleset ?? .none,
                displaySortMode: list?.displaySortMode,
                displaySortDirection: list?.displaySortDirection ?? .ascending
            )
            return CardCollectionDetailSnapshot(
                visibleEntries: visibleEntries,
                builtSections: sections,
                collapsedSectionIDs: collapsed,
                isSearchActive: true,
                totalEntryCount: totalCount,
                showsMultiCategoryCards: showsGhosts,
                revealsShadowedCategories: revealsShadowed
            )
        }

        // Scanned defaults to most-recently-scanned first. Entries load oldest-first (position
        // order); reverse and regroup in-body only while no explicit sort is set, so a sort the
        // user picks still wins and the cached (oldest-first) sections aren't used here.
        if let list, model.isScannedList(list), list.displaySortMode == nil {
            var visibleEntries = model.selectedCollectionEntries
            visibleEntries.reverse()
            let sections = CardCollectionEntrySectionBuilder.sections(
                entries: visibleEntries,
                categories: model.selectedCollectionCategories,
                ruleset: list.ruleset,
                displaySortMode: nil,
                displaySortDirection: list.displaySortDirection
            )
            return CardCollectionDetailSnapshot(
                visibleEntries: visibleEntries,
                builtSections: sections,
                collapsedSectionIDs: collapsed,
                isSearchActive: false,
                totalEntryCount: totalCount,
                showsMultiCategoryCards: showsGhosts,
                revealsShadowedCategories: revealsShadowed
            )
        }

        // Common path: reuse the sections the loader grouped+sorted off the main thread.
        return CardCollectionDetailSnapshot(
            visibleEntries: model.selectedCollectionEntries,
            builtSections: model.selectedCollectionSections,
            collapsedSectionIDs: collapsed,
            isSearchActive: false,
            totalEntryCount: totalCount,
            showsMultiCategoryCards: showsGhosts,
            revealsShadowedCategories: revealsShadowed
        )
    }

    var selectedCollectionEntryCountText: String {
        let count = listEntrySelection.selectedIDs.count
        return "\(count.formatted()) selected"
    }

    var isListSearchActive: Bool {
        !GrimoraSearchHistoryStore.normalizedQuery(model.selectedCollectionSearchText).isEmpty
    }

    var listSearchUnsupportedMessage: String? {
        guard isListSearchActive else {
            return nil
        }

        return model.selectedCollectionSearchUnsupportedMessage
    }

    /// True when the collection view is hiding at least one category. A category's rename and
    /// delete controls live in its section header, so while one is hidden the Reorder Categories
    /// view — which lists every category — has to stay reachable, even for a lone category that
    /// has nothing to reorder against.
    ///
    /// A search hides non-matching sections too, but reordering is disabled while searching, so
    /// don't let that count.
    func hasShadowedCategories(_ snapshot: CardCollectionDetailSnapshot) -> Bool {
        guard !isListSearchActive else {
            return false
        }
        return snapshot.sections.filter(\.isCategory).count < model.selectedCollectionCategories.count
    }

    func isSectionCollapsed(_ section: CardCollectionEntrySection) -> Bool {
        collapsedListCategoryIDs.contains(section.id)
    }

    func toggleCollapsedSection(_ section: CardCollectionEntrySection) {
        if collapsedListCategoryIDs.contains(section.id) {
            collapsedListCategoryIDs.remove(section.id)
        } else {
            collapsedListCategoryIDs.insert(section.id)
        }
    }

    func collapseAllSections(_ snapshot: CardCollectionDetailSnapshot) {
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
        _ entry: CardCollectionEntryRecord,
        displayedEntries: [CardCollectionEntryRecord]
    ) -> some View {
        listEntryContent(entry, displayedEntries: displayedEntries)
            .modifier(
                CardCollectionEntryFrameReportingModifier(
                    isEnabled: isSelectingListEntries,
                    entryID: entry.id,
                    coordinateSpaceName: Self.entrySelectionCoordinateSpace
                )
            )
            .zIndex(raisedArtworkEntryID == entry.id ? 100 : 0)
    }

    @ViewBuilder
    func listEntryTextRowView(_ entry: CardCollectionEntryRecord) -> some View {
        listEntryTextRowContent(entry)
            .modifier(
                CardCollectionEntryFrameReportingModifier(
                    isEnabled: isSelectingListEntries,
                    entryID: entry.id,
                    coordinateSpaceName: Self.entrySelectionCoordinateSpace
                )
            )
    }

    /// The name of the category an entry actually lives in, for a ghost's "Filed under" caption.
    func primaryCategoryName(for entry: CardCollectionEntryRecord) -> String? {
        guard let categoryID = entry.categoryID else {
            return nil
        }
        return model.selectedCollectionCategories.first { $0.id == categoryID }?.name
    }

    @ViewBuilder
    func ghostEntryView(
        _ entry: CardCollectionEntryRecord,
        in section: CardCollectionEntrySection
    ) -> some View {
        if let card = entry.card, let category = section.category {
            CardCollectionGhostGridItemView(
                entry: entry,
                card: card,
                category: category,
                primaryCategoryName: primaryCategoryName(for: entry),
                onOpen: { model.selectCard(card, fromListEntryID: entry.id) }
            )
        }
    }

    @ViewBuilder
    func ghostEntryTextRowView(
        _ entry: CardCollectionEntryRecord,
        in section: CardCollectionEntrySection
    ) -> some View {
        if let category = section.category {
            CardCollectionGhostTextRowView(
                entry: entry,
                card: entry.card,
                category: category,
                primaryCategoryName: primaryCategoryName(for: entry),
                palette: palette,
                onOpen: {
                    if let card = entry.card {
                        model.selectCard(card, fromListEntryID: entry.id)
                    }
                }
            )
        }
    }

    @ViewBuilder
    func listEntryContent(
        _ entry: CardCollectionEntryRecord,
        displayedEntries: [CardCollectionEntryRecord]
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
                    categories: model.selectedCollectionCategories,
                    hidesCategoryAndZone: isScannedCollection,
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
                    onCreateCategory: { name in
                        createCategory(named: name, movingEntryIDs: dragEntryIDs)
                    },
                    onMoveToZone: { zone in
                        moveEntryIDs(dragEntryIDs, toZone: zone)
                    },
                    isMoveDestinationDisabled: { categoryID in
                        isMoveDestinationDisabled(targetEntryIDs: dragEntryIDs, categoryID: categoryID)
                    },
                    dragPayload: CardCollectionEntryDragToken.token(for: dragEntryIDs),
                    dragItemCount: dragEntryIDs.count,
                    isDragEnabled: !isSelectingListEntries,
                    foilTreatment: card.foilTreatment(for: entry.selectedFinish ?? card.defaultFinish),
                    onFoilHoverChange: { hovering in
                        model.setFoilHoverEntry(entry.id, isHovering: hovering)
                    },
                    onArtworkOverflowChange: { isOverflowing in
                        updateRaisedArtworkEntry(entryID: entry.id, isOverflowing: isOverflowing)
                    }
                )
            }
            .modifier(
                CardCollectionVisibleImageCachingModifier(
                    entryID: entry.id,
                    card: card,
                    quality: imageQuality,
                    displayedEntries: displayedEntries
                )
            )
        } else {
            let dragEntryIDs = bulkTargetEntryIDs(for: entry)
            MissingCardCollectionEntryView(
                entry: entry,
                categories: model.selectedCollectionCategories,
                hidesCategoryAndZone: isScannedCollection,
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
                onCreateCategory: { name in
                    createCategory(named: name, movingEntryIDs: dragEntryIDs)
                },
                onMoveToZone: { zone in
                    moveEntryIDs(dragEntryIDs, toZone: zone)
                },
                isMoveDestinationDisabled: { categoryID in
                    isMoveDestinationDisabled(targetEntryIDs: dragEntryIDs, categoryID: categoryID)
                },
                dragPayload: CardCollectionEntryDragToken.token(for: dragEntryIDs),
                dragItemCount: dragEntryIDs.count,
                isDragEnabled: !isSelectingListEntries
            )
        }
    }

    @ViewBuilder
    func listEntryTextRowContent(_ entry: CardCollectionEntryRecord) -> some View {
        let dragEntryIDs = bulkTargetEntryIDs(for: entry)
        CardCollectionTextRowView(
            entry: entry,
            card: entry.card,
            categories: model.selectedCollectionCategories,
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
            onCreateCategory: { name in
                createCategory(named: name, movingEntryIDs: dragEntryIDs)
            },
            onMoveToZone: { zone in
                moveEntryIDs(dragEntryIDs, toZone: zone)
            },
            isMoveDestinationDisabled: { categoryID in
                isMoveDestinationDisabled(targetEntryIDs: dragEntryIDs, categoryID: categoryID)
            },
            dragPayload: CardCollectionEntryDragToken.token(for: dragEntryIDs),
            dragItemCount: dragEntryIDs.count,
            isDragEnabled: !isSelectingListEntries
        )
    }

    func updateRaisedArtworkEntry(entryID: CardCollectionEntryRecord.ID, isOverflowing: Bool) {
        if isOverflowing {
            raisedArtworkEntryID = entryID
        } else if raisedArtworkEntryID == entryID {
            raisedArtworkEntryID = nil
        }
    }

    func isDetailActive(for entry: CardCollectionEntryRecord, card: CardRecord?) -> Bool {
        if model.selectedCardCollectionEntryID == entry.id {
            return true
        }
        return model.selectedCardCollectionEntryID == nil && model.selectedCard?.id == card?.id
    }
}

private struct CardCollectionEntryFrameReportingModifier: ViewModifier {
    var isEnabled: Bool
    var entryID: CardCollectionEntryRecord.ID
    var coordinateSpaceName: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CardCollectionEntryFramePreferenceKey.self,
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
