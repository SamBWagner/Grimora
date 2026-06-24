import GrimoraCore
import SwiftUI

/// The menu items for moving a list entry to a different zone.
struct CardListMoveZoneMenuContent: View {
    @Environment(GrimoraAppModel.self) private var model

    var entry: CardListEntryRecord
    var onMoveToZone: ((CardListZone) -> Void)?
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

    private var availableZones: [CardListZone] {
        (model.selectedList?.ruleset ?? .none).allowedZones
    }

    private func move(to zone: CardListZone) {
        if let onMoveToZone {
            onMoveToZone(zone)
        } else {
            model.moveCardListEntry(id: entry.id, toZone: zone)
        }
        onMoved()
    }
}
