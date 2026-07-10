import GrimoraCore
import SwiftUI

/// A brief, auto-dismissing notice surfaced by the foil shortcut / command (e.g. when a card
/// offers no foil finish). Each instance carries a fresh `id` so re-showing the same message
/// restarts the toast's dismissal timer.
public struct GrimoraFoilCommandNotice: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// The outcome of attempting to toggle foil on a target.
public enum GrimoraFoilToggleResult: Equatable, Sendable {
    /// The finish changed, or was already locked-on for a foil-only card. `isFoil` is the new state.
    case toggled(isFoil: Bool)
    /// The card offers no foil finish at all.
    case unavailable
    /// There was nothing to act on.
    case noTarget
}

@MainActor
extension GrimoraAppModel {
    // MARK: Hover tracking

    /// Records (or clears) the collection entry under the pointer for the hover-to-foil shortcut.
    /// Clears only when the leaving entry is still the tracked one, so hopping between adjacent
    /// tiles — where the leave-old and enter-new events can arrive in either order — never wipes
    /// the newly hovered entry.
    public func setFoilHoverEntry(_ entryID: CardCollectionEntryRecord.ID, isHovering: Bool) {
        if isHovering {
            hoveredFoilEntryID = entryID
        } else if hoveredFoilEntryID == entryID {
            hoveredFoilEntryID = nil
        }
    }

    // MARK: Command surface

    /// Whether the "Toggle Foil" command has a target right now: a hovered collection card, or the
    /// card open in the detail pane. Drives the menu item's enabled state. (Search-result tiles
    /// never register as hover targets, so the command stays inert while browsing the catalog.)
    public var canToggleFoilForActiveTarget: Bool {
        hoveredFoilEntryID != nil || selectedCard != nil
    }

    /// Toggles foil on the active target — the hovered collection card if any, otherwise the
    /// detail-pane card — and surfaces the "No foil available" notice when the card can't be foil.
    /// Returns `true` when there was a target to act on, so a key handler knows to consume the key
    /// (and pass it through otherwise).
    @discardableResult
    public func performFoilToggleCommand() -> Bool {
        applyFoilToggle(activeFoilToggleResult())
    }

    /// Toggles foil on a specific collection entry (e.g. from its context menu), showing the notice
    /// when that card can't be foil. Returns `true` when the entry was a valid target.
    @discardableResult
    public func performFoilToggle(forCollectionEntryID entryID: CardCollectionEntryRecord.ID) -> Bool {
        applyFoilToggle(toggleFoil(forCollectionEntryID: entryID))
    }

    private func applyFoilToggle(_ result: GrimoraFoilToggleResult) -> Bool {
        switch result {
        case .noTarget:
            return false
        case .unavailable:
            showFoilNotice("No foil available")
            return true
        case .toggled:
            foilCommandNotice = nil
            return true
        }
    }

    private func activeFoilToggleResult() -> GrimoraFoilToggleResult {
        if let hoveredFoilEntryID {
            return toggleFoil(forCollectionEntryID: hoveredFoilEntryID)
        }
        if let selectedCard {
            return toggleFoilForDetailCard(selectedCard)
        }
        return .noTarget
    }

    // MARK: Toggling

    /// Flips the persisted finish on a collection entry between foil and its non-foil default,
    /// writing straight to that entry (it need not be the one open in the detail pane).
    @discardableResult
    func toggleFoil(forCollectionEntryID entryID: CardCollectionEntryRecord.ID) -> GrimoraFoilToggleResult {
        guard let entry = selectedCollectionEntries.first(where: { $0.id == entryID }),
              let card = entry.card else {
            return .noTarget
        }
        let current = entry.selectedFinish ?? card.defaultFinish
        switch foilToggleStep(for: card, current: current) {
        case .unavailable:
            return .unavailable
        case .noChange:
            return .toggled(isFoil: current == .foil)
        case .setFinish(let finish):
            do {
                _ = try performListMutation {
                    try database.setCardCollectionEntryFinish(id: entryID, finish: finish)
                }
                reloadCardCollections(selecting: selectedCollectionID)
            } catch {
                statusMessage = "Collection update failed."
                return .noTarget
            }
            return .toggled(isFoil: finish == .foil)
        }
    }

    /// Flips the finish on the detail-pane card, persisting to its collection entry when the card
    /// is an owned entry's pinned print (otherwise the transient session finish). Routes through
    /// `setFinish(_:for:)`, the same write path as the detail finish picker.
    @discardableResult
    func toggleFoilForDetailCard(_ card: CardRecord) -> GrimoraFoilToggleResult {
        let current = selectedFinish(for: card)
        switch foilToggleStep(for: card, current: current) {
        case .unavailable:
            return .unavailable
        case .noChange:
            return .toggled(isFoil: current == .foil)
        case .setFinish(let finish):
            setFinish(finish, for: card)
            return .toggled(isFoil: finish == .foil)
        }
    }

    private enum FoilToggleStep: Equatable {
        case setFinish(CardValueFinish)
        case unavailable
        case noChange
    }

    /// Decides the finish a foil-toggle should land on: foil when currently non-foil; back to
    /// normal when currently foil; nothing for a foil-only card (already locked foil); and
    /// `unavailable` for a card with no foil finish at all. Etched cards toggle *to* foil like any
    /// other non-foil finish — the detail picker remains the way to reach etched precisely.
    private func foilToggleStep(for card: CardRecord, current: CardValueFinish) -> FoilToggleStep {
        guard card.supportsFoil else {
            return .unavailable
        }
        if current == .foil {
            return card.supportsNonfoil ? .setFinish(.normal) : .noChange
        }
        return .setFinish(.foil)
    }

    // MARK: Notice

    func showFoilNotice(_ message: String) {
        foilCommandNotice = GrimoraFoilCommandNotice(message: message)
    }

    public func dismissFoilNotice() {
        foilCommandNotice = nil
    }
}
