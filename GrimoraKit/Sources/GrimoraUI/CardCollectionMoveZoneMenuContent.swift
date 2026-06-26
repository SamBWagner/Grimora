import GrimoraCore
import SwiftUI

/// The menu items for moving a list entry to a different zone.
struct CardCollectionMoveZoneMenuContent: View {
    @Environment(GrimoraAppModel.self) private var model

    var entry: CardCollectionEntryRecord
    var onMoveToZone: ((CardCollectionZone) -> Void)?
    var onMoved: () -> Void = {}

    var body: some View {
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
    }

    private var availableZones: [CardCollectionZone] {
        (model.selectedCollection?.ruleset ?? .none).allowedZones
    }

    private func move(to zone: CardCollectionZone) {
        if let onMoveToZone {
            onMoveToZone(zone)
        } else {
            model.moveCardCollectionEntry(id: entry.id, toZone: zone)
        }
        onMoved()
    }
}
