import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardListDetailView {
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
        id: CardListEntryRecord.ID,
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

    func scheduleListEntryOpen(_ card: CardRecord, entryID: CardListEntryRecord.ID) {
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
        _ visibleIDs: [CardListEntryRecord.ID]? = nil
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

    func updateEntrySelectionFrames(_ frames: [CardListEntryRecord.ID: CGRect]) {
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
        triggeredBy entry: CardListEntryRecord,
        toCategoryID categoryID: CardListCategoryRecord.ID?
    ) {
        model.moveCardListEntries(ids: bulkTargetEntryIDs(for: entry), toCategoryID: categoryID)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func moveEntries(
        triggeredBy entry: CardListEntryRecord,
        toZone zone: CardListZone
    ) {
        model.moveCardListEntries(ids: bulkTargetEntryIDs(for: entry), toZone: zone)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func moveEntryIDs(
        _ ids: [CardListEntryRecord.ID],
        toCategoryID categoryID: CardListCategoryRecord.ID?
    ) {
        model.moveCardListEntries(ids: ids, toCategoryID: categoryID)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func moveEntryIDs(
        _ ids: [CardListEntryRecord.ID],
        toZone zone: CardListZone
    ) {
        model.moveCardListEntries(ids: ids, toZone: zone)
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    /// Creates a new category in the current list and files the given entries
    /// into it, powering the on-card "New Category…" action.
    func createCategory(
        named name: String,
        movingEntryIDs ids: [CardListEntryRecord.ID]
    ) {
        guard let category = model.createCardListCategory(named: name) else {
            return
        }
        moveEntryIDs(ids, toCategoryID: category.id)
    }

    func moveEntryIDs(
        _ ids: [CardListEntryRecord.ID],
        toZone zone: CardListZone,
        categoryID: CardListCategoryRecord.ID?
    ) {
        if let categoryID {
            model.moveCardListEntries(ids: ids, toCategoryID: categoryID)
        } else {
            model.moveCardListEntries(ids: ids, toZone: zone)
        }
        pruneSelectedListEntryIDs()
        listMoveFeedbackTrigger += 1
    }

    func incrementEntries(triggeredBy entry: CardListEntryRecord) {
        model.incrementCardListEntryQuantities(ids: bulkTargetEntryIDs(for: entry))
        pruneSelectedListEntryIDs()
    }

    func decreaseEntries(triggeredBy entry: CardListEntryRecord) {
        model.removeCardListEntries(ids: bulkTargetEntryIDs(for: entry))
        pruneSelectedListEntryIDs()
    }

    func removeEntries(triggeredBy entry: CardListEntryRecord) {
        model.removeCardListEntriesCompletely(ids: bulkTargetEntryIDs(for: entry))
        pruneSelectedListEntryIDs()
    }

    func beginQuantityEdit(triggeredBy entry: CardListEntryRecord) {
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

        model.setCardListEntryQuantities(ids: bulkTargetEntryIDs(for: quantityEditEntry), quantity: quantity)
        self.quantityEditEntry = nil
        quantityDraft = ""
        pruneSelectedListEntryIDs()
    }

    func isMoveDestinationDisabled(
        triggeredBy entry: CardListEntryRecord,
        categoryID: CardListCategoryRecord.ID?
    ) -> Bool {
        let targetIDs = Set(bulkTargetEntryIDs(for: entry))
        let targetEntries = model.selectedListEntries.filter { targetIDs.contains($0.id) }
        return !targetEntries.isEmpty && targetEntries.allSatisfy { $0.categoryID == categoryID }
    }

    func isMoveDestinationDisabled(
        targetEntryIDs: [CardListEntryRecord.ID],
        categoryID: CardListCategoryRecord.ID?
    ) -> Bool {
        let targetIDs = Set(targetEntryIDs)
        let targetEntries = model.selectedListEntries.filter { targetIDs.contains($0.id) }
        return !targetEntries.isEmpty && targetEntries.allSatisfy { $0.categoryID == categoryID }
    }

    func bulkTargetEntryIDs(for entry: CardListEntryRecord) -> [CardListEntryRecord.ID] {
        let orderedEntryIDs = model.selectedListEntries.map(\.id)
        let currentEntryIDs = Set(orderedEntryIDs)
        let currentSelectedIDs = listEntrySelection.selectedIDs.intersection(currentEntryIDs)

        if currentSelectedIDs.contains(entry.id) {
            return orderedEntryIDs.filter { currentSelectedIDs.contains($0) }
        }

        return [entry.id]
    }

    func bulkTargetCardIDs(for entry: CardListEntryRecord) -> [CardRecord.ID] {
        let targetEntryIDs = Set(bulkTargetEntryIDs(for: entry))
        return model.selectedListEntries
            .filter { targetEntryIDs.contains($0.id) }
            .map(\.cardID)
    }

    func dragPayload(triggeredBy entry: CardListEntryRecord) -> String {
        CardListEntryDragToken.token(for: bulkTargetEntryIDs(for: entry))
    }

    func pruneSelectedListEntryIDs() {
        syncListEntrySelectionVisibleIDs()
        let currentEntryIDs = Set(model.selectedListEntries.map(\.id))
        entrySelectionFrames = entrySelectionFrames.filter { currentEntryIDs.contains($0.key) }
    }

}

struct CardListEntryFramePreferenceKey: PreferenceKey {
    static let defaultValue: [CardListEntryRecord.ID: CGRect] = [:]

    static func reduce(
        value: inout [CardListEntryRecord.ID: CGRect],
        nextValue: () -> [CardListEntryRecord.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}
