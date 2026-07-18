import GrimoraCore
import SwiftUI

@MainActor
extension GrimoraAppModel {
    // MARK: - Loading

    /// Reloads the cached label definitions (array + id lookup) from the database. Called by
    /// `reloadCardCollections`; pip rendering and the pickers read the cache reactively.
    func refreshCardLabels() {
        let labels = (try? database.cardLabels()) ?? []
        cardLabels = labels
        labelsByID = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Queries

    /// Every global (instance-wide) label, in display order. Backs the Settings manager.
    public var globalLabels: [CardLabelRecord] {
        cardLabels.filter(\.isGlobal)
    }

    /// The labels usable inside a collection: global labels plus that list's own labels, in the
    /// cache's display order (globals first, then the list's, each by position).
    public func applicableLabels(forListID listID: CardCollectionRecord.ID) -> [CardLabelRecord] {
        cardLabels.filter { $0.listID == nil || $0.listID == listID }
    }

    /// The labels applicable to the currently-selected collection (empty when none is selected).
    public var selectedCollectionApplicableLabels: [CardLabelRecord] {
        guard let selectedCollectionID else { return [] }
        return applicableLabels(forListID: selectedCollectionID)
    }

    /// Resolves an entry's `labelIDs` into their definitions, ordered as pips should render: by the
    /// label's `position`, then name. Dangling ids (deleted labels not yet stripped) are skipped.
    public func labels(for entry: CardCollectionEntryRecord) -> [CardLabelRecord] {
        entry.labelIDs
            .compactMap { labelsByID[$0] }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func entryHasLabel(_ labelID: CardLabelRecord.ID, entry: CardCollectionEntryRecord) -> Bool {
        entry.labelIDs.contains(labelID)
    }

    /// The collection entry currently driving the detail pane, if the open card came from a list.
    /// Backs the detail-pane label section (labels are per-entry).
    public var detailEntry: CardCollectionEntryRecord? {
        guard let selectedCardCollectionEntryID else { return nil }
        return selectedCollectionEntries.first { $0.id == selectedCardCollectionEntryID }
    }

    // MARK: - Assignment

    /// Toggles a label on one or more collection entries (multi-select aware), as a single undoable
    /// mutation. Entries are resolved by card id against the selected collection, matching how the
    /// context menu's `targetCardIDs` identify their entries.
    public func toggleLabel(
        _ labelID: CardLabelRecord.ID,
        forEntryIDs entryIDs: [CardCollectionEntryRecord.ID]
    ) {
        guard !entryIDs.isEmpty else { return }
        do {
            try performListMutation {
                for entryID in entryIDs {
                    _ = try database.toggleCardCollectionEntryLabel(entryID: entryID, labelID: labelID)
                }
            }
            reloadCardCollections(selecting: selectedCollectionID)
        } catch {
            statusMessage = "Couldn’t update labels."
        }
    }

    /// Convenience for a single entry.
    public func toggleLabel(_ labelID: CardLabelRecord.ID, forEntryID entryID: CardCollectionEntryRecord.ID) {
        toggleLabel(labelID, forEntryIDs: [entryID])
    }

    /// Creates a list-local label on the entry's collection and applies it to that entry — the
    /// shared "New Label…" action across every card menu.
    public func addNewLabel(named name: String, color: LabelColor, toEntry entry: CardCollectionEntryRecord) {
        if let label = createLabel(named: name, color: color, listID: entry.listID) {
            toggleLabel(label.id, forEntryIDs: [entry.id])
        }
    }

    // MARK: - Definition CRUD

    @discardableResult
    public func createLabel(
        named name: String,
        color: LabelColor,
        listID: CardCollectionRecord.ID? = nil
    ) -> CardLabelRecord? {
        do {
            let label = try performListMutation {
                try database.createCardLabel(named: name, color: color, listID: listID)
            }
            refreshCardLabels()
            return label
        } catch {
            statusMessage = "Couldn’t create the label."
            return nil
        }
    }

    public func updateLabel(id: CardLabelRecord.ID, name: String? = nil, color: LabelColor? = nil) {
        do {
            _ = try performListMutation {
                try database.updateCardLabel(id: id, name: name, color: color)
            }
            refreshCardLabels()
        } catch {
            statusMessage = "Couldn’t update the label."
        }
    }

    /// Promotes a list-local label to global.
    public func exportLabelToGlobal(id: CardLabelRecord.ID) {
        do {
            _ = try performListMutation {
                try database.exportCardLabelToGlobal(id: id)
            }
            refreshCardLabels()
        } catch {
            statusMessage = "Couldn’t export the label."
        }
    }

    /// Deletes a label definition and strips it from every entry that carried it.
    public func deleteLabel(id: CardLabelRecord.ID) {
        do {
            try performListMutation {
                try database.deleteCardLabel(id: id)
            }
            // Entries changed (the label was stripped), so rebuild collections + the label cache.
            reloadCardCollections(selecting: selectedCollectionID)
        } catch {
            statusMessage = "Couldn’t delete the label."
        }
    }
}
