import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardCollectionDetailView {
    func beginListEntrySelection() {
        isSelectingListEntries = true
        if isReorderingCategories {
            isReorderingCategories = false
        }
        syncListEntrySelectionVisibleIDs()
    }

    func finishListEntrySelection() {
        endListEntrySelectionMode()
        clearListEntrySelection()
        cancelPendingListEntryOpen()
    }

    func endListEntrySelectionMode() {
        isSelectingListEntries = false
        finishSelectionDrag()
        entrySelectionFrames = [:]
    }

    func clearListEntrySelection() {
        cancelPendingListEntryOpen()
        guard !listEntrySelection.isEmpty else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            listEntrySelection.clear()
        }
    }

    func applyListEntrySelectionInteraction(
        id: CardCollectionEntryRecord.ID,
        interaction: CardGridSelectionInteraction,
        card: CardRecord? = nil
    ) {
        cancelPendingListEntryOpen()
        if interaction == .range {
            syncListEntrySelectionVisibleIDs()
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            listEntrySelection.select(id, interaction: interaction)
        }

        if isReorderingCategories {
            isReorderingCategories = false
        }

        if !isSelectingListEntries, interaction == .replace, let card {
            scheduleListEntryOpen(card, entryID: id)
        }
    }

    func scheduleListEntryOpen(_ card: CardRecord, entryID: CardCollectionEntryRecord.ID) {
        pendingListEntryOpenTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.listEntryOpenDelayNanoseconds)
            guard !Task.isCancelled,
                  listEntrySelection.selectedIDs == Set([entryID]),
                  !isSelectingListEntries
            else {
                return
            }

            model.selectCard(card, fromListEntryID: entryID)
        }
    }

    func cancelPendingListEntryOpen() {
        pendingListEntryOpenTask?.cancel()
        pendingListEntryOpenTask = nil
    }

    func syncListEntrySelectionVisibleIDs(
        _ visibleIDs: [CardCollectionEntryRecord.ID]? = nil
    ) {
        listEntrySelection.setVisibleIDs(visibleIDs ?? renderedListEntryIDs)
    }

    func updateSelectionDrag(_ value: DragGesture.Value) {
        if selectionDragStart == nil {
            selectionDragStart = value.startLocation
        }
        selectionDragLocation = value.location

        guard let currentSelectionDragRect else {
            return
        }

        let intersectingIDs = entrySelectionFrames.compactMap { entryID, frame in
            currentSelectionDragRect.intersects(frame.insetBy(dx: -2, dy: -2)) ? entryID : nil
        }
        listEntrySelection.selectedIDs.formUnion(intersectingIDs)
    }

    func updateEntrySelectionFrames(_ frames: [CardCollectionEntryRecord.ID: CGRect]) {
        guard isSelectingListEntries else {
            if !entrySelectionFrames.isEmpty {
                entrySelectionFrames = [:]
            }
            return
        }

        if entrySelectionFrames != frames {
            entrySelectionFrames = frames
        }
    }

    func finishSelectionDrag() {
        selectionDragStart = nil
        selectionDragLocation = nil
    }

    func moveEntries(
        triggeredBy entry: CardCollectionEntryRecord,
        toCategoryID categoryID: CardCollectionCategoryRecord.ID?
    ) {
        model.moveCardCollectionEntries(ids: bulkTargetEntryIDs(for: entry), toCategoryID: categoryID)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func moveEntries(
        triggeredBy entry: CardCollectionEntryRecord,
        toZone zone: CardCollectionZone
    ) {
        model.moveCardCollectionEntries(ids: bulkTargetEntryIDs(for: entry), toZone: zone)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func moveEntryIDs(
        _ ids: [CardCollectionEntryRecord.ID],
        toCategoryID categoryID: CardCollectionCategoryRecord.ID?
    ) {
        model.moveCardCollectionEntries(ids: ids, toCategoryID: categoryID)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func moveEntryIDs(
        _ ids: [CardCollectionEntryRecord.ID],
        toZone zone: CardCollectionZone
    ) {
        model.moveCardCollectionEntries(ids: ids, toZone: zone)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    /// Creates a new category in the current list and files the given entries
    /// into it, powering the on-card "New Category…" action.
    func createCategory(
        named name: String,
        movingEntryIDs ids: [CardCollectionEntryRecord.ID]
    ) {
        guard let category = model.createCardCollectionCategory(named: name) else {
            return
        }
        moveEntryIDs(ids, toCategoryID: category.id)
    }

    func moveEntryIDs(
        _ ids: [CardCollectionEntryRecord.ID],
        toZone zone: CardCollectionZone,
        categoryID: CardCollectionCategoryRecord.ID?
    ) {
        if let categoryID {
            model.moveCardCollectionEntries(ids: ids, toCategoryID: categoryID)
        } else {
            model.moveCardCollectionEntries(ids: ids, toZone: zone)
        }
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func incrementEntries(triggeredBy entry: CardCollectionEntryRecord) {
        model.incrementCardCollectionEntryQuantities(ids: bulkTargetEntryIDs(for: entry))
        pruneSelectedListEntryIDs()
    }

    func decreaseEntries(triggeredBy entry: CardCollectionEntryRecord) {
        model.removeCardCollectionEntries(ids: bulkTargetEntryIDs(for: entry))
        pruneSelectedListEntryIDs()
    }

    func removeEntries(triggeredBy entry: CardCollectionEntryRecord) {
        model.removeCardCollectionEntriesCompletely(ids: bulkTargetEntryIDs(for: entry))
        pruneSelectedListEntryIDs()
    }

    func beginQuantityEdit(triggeredBy entry: CardCollectionEntryRecord) {
        quantityEditEntry = entry
        quantityDraft = "\(entry.quantity)"
    }

    func submitQuantityEdit() {
        guard let quantityEditEntry,
              let quantity = Int(quantityDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
              quantity > 0
        else {
            return
        }

        model.setCardCollectionEntryQuantities(ids: bulkTargetEntryIDs(for: quantityEditEntry), quantity: quantity)
        self.quantityEditEntry = nil
        quantityDraft = ""
        pruneSelectedListEntryIDs()
    }

    func isMoveDestinationDisabled(
        triggeredBy entry: CardCollectionEntryRecord,
        categoryID: CardCollectionCategoryRecord.ID?
    ) -> Bool {
        let targetIDs = Set(bulkTargetEntryIDs(for: entry))
        let targetEntries = model.selectedCollectionEntries.filter { targetIDs.contains($0.id) }
        return !targetEntries.isEmpty && targetEntries.allSatisfy { $0.categoryID == categoryID }
    }

    func isMoveDestinationDisabled(
        targetEntryIDs: [CardCollectionEntryRecord.ID],
        categoryID: CardCollectionCategoryRecord.ID?
    ) -> Bool {
        let targetIDs = Set(targetEntryIDs)
        let targetEntries = model.selectedCollectionEntries.filter { targetIDs.contains($0.id) }
        return !targetEntries.isEmpty && targetEntries.allSatisfy { $0.categoryID == categoryID }
    }

    func bulkTargetEntryIDs(for entry: CardCollectionEntryRecord) -> [CardCollectionEntryRecord.ID] {
        let orderedEntryIDs = model.selectedCollectionEntries.map(\.id)
        let currentEntryIDs = Set(orderedEntryIDs)
        let currentSelectedIDs = listEntrySelection.selectedIDs.intersection(currentEntryIDs)

        if currentSelectedIDs.contains(entry.id) {
            return orderedEntryIDs.filter { currentSelectedIDs.contains($0) }
        }

        return [entry.id]
    }

    func bulkTargetCardIDs(for entry: CardCollectionEntryRecord) -> [CardRecord.ID] {
        let targetEntryIDs = Set(bulkTargetEntryIDs(for: entry))
        return model.selectedCollectionEntries
            .filter { targetEntryIDs.contains($0.id) }
            .map(\.cardID)
    }

    func dragPayload(triggeredBy entry: CardCollectionEntryRecord) -> String {
        CardCollectionEntryDragToken.token(for: bulkTargetEntryIDs(for: entry))
    }

    func pruneSelectedListEntryIDs() {
        syncListEntrySelectionVisibleIDs()
        let currentEntryIDs = Set(model.selectedCollectionEntries.map(\.id))
        entrySelectionFrames = entrySelectionFrames.filter { currentEntryIDs.contains($0.key) }
    }

}

struct CardCollectionEntryFramePreferenceKey: PreferenceKey {
    static let defaultValue: [CardCollectionEntryRecord.ID: CGRect] = [:]

    static func reduce(
        value: inout [CardCollectionEntryRecord.ID: CGRect],
        nextValue: () -> [CardCollectionEntryRecord.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}
