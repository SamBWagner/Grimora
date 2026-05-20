import Foundation

enum CardGridSelectionInteraction: Equatable {
    case replace
    case toggle
    case range
}

struct CardGridSelectionState<ID: Hashable>: Equatable {
    var selectedIDs: Set<ID> = []
    var lastSelectedID: ID?
    var orderedVisibleIDs: [ID] = []

    var selectedOrderedIDs: [ID] {
        orderedVisibleIDs.filter { selectedIDs.contains($0) }
    }

    var isEmpty: Bool {
        selectedIDs.isEmpty
    }

    mutating func setVisibleIDs(_ ids: [ID]) {
        orderedVisibleIDs = ids
        pruneSelection()
    }

    mutating func select(_ id: ID, interaction: CardGridSelectionInteraction) {
        switch interaction {
        case .replace:
            selectedIDs = [id]
        case .toggle:
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        case .range:
            selectRange(endingAt: id)
        }

        lastSelectedID = selectedIDs.isEmpty ? nil : id
    }

    mutating func clear() {
        selectedIDs.removeAll()
        lastSelectedID = nil
    }

    private mutating func selectRange(endingAt endID: ID) {
        guard let lastSelectedID,
              let startIndex = orderedVisibleIDs.firstIndex(of: lastSelectedID),
              let endIndex = orderedVisibleIDs.firstIndex(of: endID)
        else {
            selectedIDs = [endID]
            return
        }

        let bounds = min(startIndex, endIndex)...max(startIndex, endIndex)
        selectedIDs.formUnion(orderedVisibleIDs[bounds])
    }

    private mutating func pruneSelection() {
        let visibleIDs = Set(orderedVisibleIDs)
        selectedIDs.formIntersection(visibleIDs)
        if let lastSelectedID, !visibleIDs.contains(lastSelectedID) {
            self.lastSelectedID = nil
        }
        if selectedIDs.isEmpty {
            lastSelectedID = nil
        }
    }
}
