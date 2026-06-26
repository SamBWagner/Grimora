import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardCollectionVisibleImageCachingModifier: ViewModifier {
    @Environment(GrimoraAppModel.self) private var model

    var entryID: CardCollectionEntryRecord.ID
    var card: CardRecord
    var quality: CardImageQuality
    var displayedEntries: [CardCollectionEntryRecord]

    func body(content: Content) -> some View {
        content
            .task(id: CardCollectionImageCacheTaskID(entryID: entryID, card: card, quality: quality)) {
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

private struct CardCollectionImageCacheTaskID: Equatable {
    var entryID: String
    var cardID: String
    var quality: CardImageQuality

    init(entryID: CardCollectionEntryRecord.ID, card: CardRecord, quality: CardImageQuality) {
        self.entryID = entryID
        cardID = card.id
        self.quality = quality
    }
}
