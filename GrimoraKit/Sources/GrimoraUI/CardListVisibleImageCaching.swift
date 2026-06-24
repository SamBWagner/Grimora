import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardListVisibleImageCachingModifier: ViewModifier {
    @Environment(GrimoraAppModel.self) private var model

    var entryID: CardListEntryRecord.ID
    var card: CardRecord
    var quality: CardImageQuality
    var displayedEntries: [CardListEntryRecord]

    func body(content: Content) -> some View {
        content
            .task(id: CardListImageCacheTaskID(entryID: entryID, card: card, quality: quality)) {
                guard await VisibleImageCacheTaskDeferral.waitBeforeStarting() else {
                    return
                }
                await model.cacheVisibleListEntryImages(
                    around: entryID,
                    displayedEntries: displayedEntries,
                    quality: quality
                )
            }
    }
}

private struct CardListImageCacheTaskID: Equatable {
    var entryID: String
    var cardID: String
    var quality: CardImageQuality

    init(entryID: CardListEntryRecord.ID, card: CardRecord, quality: CardImageQuality) {
        self.entryID = entryID
        cardID = card.id
        self.quality = quality
    }
}
