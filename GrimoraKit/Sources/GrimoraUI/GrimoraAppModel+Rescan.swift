import Foundation
import GrimoraCore

extension GrimoraAppModel {
  /// Applies a Commander re-scan diff to a deck in a single atomic, undoable step.
  ///
  /// Additions are appended to the mainboard (`appendCard` merges into an existing
  /// entry when the printing is already there); removals reduce or delete the
  /// referenced mainboard entry. Wrapping everything in one `performListMutation`
  /// means a single Undo reverts the entire re-scan.
  public func applyCommanderRescan(
    listID: CardCollectionRecord.ID,
    diff: CommanderRescanDiff
  ) {
    guard !diff.isEmpty else { return }

    do {
      try performListMutation {
        // Read fresh quantities so removals reduce/delete from real current state.
        let currentEntries = try database.cardCollectionEntries(forListID: listID)
        let currentQuantities = Dictionary(
          uniqueKeysWithValues: currentEntries.map { ($0.id, $0.quantity) }
        )

        for change in diff.additions {
          try database.appendCard(
            change.cardID,
            toList: listID,
            zone: change.zone,
            quantity: change.delta
          )
        }

        for change in diff.removals {
          guard let entryID = change.entryID else { continue }
          let newQuantity = (currentQuantities[entryID] ?? 0) + change.delta // delta < 0
          if newQuantity > 0 {
            try database.setCardCollectionEntryQuantity(id: entryID, quantity: newQuantity)
          } else {
            try database.removeCardCollectionEntryCompletely(id: entryID)
          }
        }
      }

      reloadCardCollections(selecting: selectedCollectionID)
      let name = cardCollections.first { $0.id == listID }?.name ?? "deck"
      statusMessage = rescanStatusMessage(deckName: name, diff: diff)
    } catch {
      statusMessage = "Re-scan update failed."
    }
  }

  private func rescanStatusMessage(deckName: String, diff: CommanderRescanDiff) -> String {
    var parts: [String] = []
    if diff.addedCopies > 0 { parts.append("+\(formatted(diff.addedCopies))") }
    if diff.removedCopies > 0 { parts.append("−\(formatted(diff.removedCopies))") }
    return "Updated \(deckName): \(parts.joined(separator: ", "))."
  }
}
