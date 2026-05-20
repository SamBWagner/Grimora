import Foundation

public struct ImportSummary: Equatable, Sendable {
    public var importedCards: Int
    public var failedImageURLs: [URL]
    public var priceHistoryStatus: PriceHistoryImportStatus

    public init(
        importedCards: Int,
        failedImageURLs: [URL],
        priceHistoryStatus: PriceHistoryImportStatus = .notConfigured
    ) {
        self.importedCards = importedCards
        self.failedImageURLs = failedImageURLs
        self.priceHistoryStatus = priceHistoryStatus
    }
}

public enum PriceHistoryImportStatus: Equatable, Sendable {
    case notConfigured
    case skipped
    case imported(MTGJSONPriceImportSummary)
    case failed
}

public enum PriceHistoryDownloadFile: Equatable, Sendable {
    case cardIdentifiers
    case currentPrices
    case prices
    case fullHistoryPrices
}

public enum ImageImportPolicy: Equatable, Sendable {
    case downloadBeforeDatabaseWrite
    case downloadBeforeDatabaseWriteStrict
    case downloadDisplayImagesBeforeDatabaseWriteStrict
    case downloadAfterDatabaseWrite
    case reuseExistingImagesWithoutDownloading
    case skipImageDownloads
}

public enum LibraryImportError: Error, Equatable, Sendable {
    case imageDownloadsFailed([URL])
}

public enum ImportProgress: Equatable, Sendable {
    case downloadingBulkData
    case downloadingBulkDataProgress(completedBytes: Int64, totalBytes: Int64?)
    case decodingCardData
    case storingSearchIndex(cardCount: Int)
    case cardDataReady(cardCount: Int)
    case downloadingPriceHistoryData
    case downloadingPriceHistoryDataProgress(
        file: PriceHistoryDownloadFile,
        completedBytes: Int64,
        totalBytes: Int64?
    )
    case buildingPriceIDMap
    case buildingPriceIDMapProgress(scannedBytes: Int64, totalBytes: Int64?, mappedCards: Int)
    case importingPriceHistory
    case importingPriceHistoryProgress(scannedBytes: Int64, totalBytes: Int64?, importedPricePoints: Int)
    case priceHistoryReady(pricePointCount: Int)
    case downloadingImages(completedCards: Int, totalCards: Int, failedImageCount: Int)
}

public final class LibraryImporter: Sendable {
    private let database: CardDatabase
    private let imageResolver: ImageResolving
    private let decoder: JSONDecoder

    public init(
        database: CardDatabase,
        imageResolver: ImageResolving,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.database = database
        self.imageResolver = imageResolver
        self.decoder = decoder
    }

    public func importDefaultCards(
        from url: URL,
        manifest: BulkDataManifest?,
        imagePolicy: ImageImportPolicy = .reuseExistingImagesWithoutDownloading,
        preservesCardValueHistory: Bool = false,
        progress: (@Sendable (ImportProgress) async -> Void)? = nil
    ) async throws -> ImportSummary {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try await importDefaultCards(
            from: data,
            manifest: manifest,
            imagePolicy: imagePolicy,
            preservesCardValueHistory: preservesCardValueHistory,
            progress: progress
        )
    }

    public func importDefaultCards(
        from data: Data,
        manifest: BulkDataManifest?,
        imagePolicy: ImageImportPolicy = .reuseExistingImagesWithoutDownloading,
        preservesCardValueHistory: Bool = false,
        progress: (@Sendable (ImportProgress) async -> Void)? = nil
    ) async throws -> ImportSummary {
        await progress?(.decodingCardData)
        let cards = try decoder.decode([ScryfallCardDTO].self, from: data)

        switch imagePolicy {
        case .downloadBeforeDatabaseWrite:
            let result = await recordsByResolvingImages(
                for: cards,
                qualities: Set(CardImageQuality.allCases),
                progress: progress
            )
            try await store(
                result.records,
                manifest: manifest,
                imageCacheComplete: result.failedImageURLs.isEmpty,
                preservesCardValueHistory: preservesCardValueHistory,
                progress: progress
            )
            return ImportSummary(importedCards: result.records.count, failedImageURLs: result.failedImageURLs)

        case .downloadBeforeDatabaseWriteStrict:
            let result = await recordsByResolvingImages(
                for: cards,
                qualities: Set(CardImageQuality.allCases),
                progress: progress
            )
            guard result.failedImageURLs.isEmpty else {
                throw LibraryImportError.imageDownloadsFailed(result.failedImageURLs)
            }
            try await store(
                result.records,
                manifest: manifest,
                imageCacheComplete: true,
                preservesCardValueHistory: preservesCardValueHistory,
                progress: progress
            )
            return ImportSummary(importedCards: result.records.count, failedImageURLs: result.failedImageURLs)

        case .downloadDisplayImagesBeforeDatabaseWriteStrict:
            let result = await recordsByResolvingPreferredDisplayImages(
                for: cards,
                progress: progress
            )
            guard result.failedImageURLs.isEmpty else {
                throw LibraryImportError.imageDownloadsFailed(result.failedImageURLs)
            }
            try await store(
                result.records,
                manifest: manifest,
                imageCacheComplete: true,
                preservesCardValueHistory: preservesCardValueHistory,
                progress: progress
            )
            return ImportSummary(importedCards: result.records.count, failedImageURLs: result.failedImageURLs)

        case .downloadAfterDatabaseWrite:
            let records = recordsWithPlannedLocalImages(from: cards)
            try await store(
                records,
                manifest: manifest,
                imageCacheComplete: false,
                preservesCardValueHistory: preservesCardValueHistory,
                progress: progress
            )
            let failedImageURLs = await resolveImagesAfterInitialImport(for: cards, totalCards: records.count, progress: progress)
            if failedImageURLs.isEmpty {
                try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
            }
            return ImportSummary(importedCards: records.count, failedImageURLs: failedImageURLs)

        case .reuseExistingImagesWithoutDownloading:
            let records = recordsWithExistingLocalImages(from: cards)
            try await store(
                records,
                manifest: manifest,
                imageCacheComplete: false,
                preservesCardValueHistory: preservesCardValueHistory,
                progress: progress
            )
            return ImportSummary(importedCards: records.count, failedImageURLs: [])

        case .skipImageDownloads:
            let records = recordsWithoutLocalImages(from: cards)
            try await store(
                records,
                manifest: manifest,
                imageCacheComplete: false,
                preservesCardValueHistory: preservesCardValueHistory,
                progress: progress
            )
            return ImportSummary(importedCards: records.count, failedImageURLs: [])
        }
    }

    private func recordsWithoutLocalImages(from cards: [ScryfallCardDTO]) -> [CardRecord] {
        cards.map { card in
            ScryfallCardNormalizer.normalize(card, topLevelImages: LocalImagePair(), faceImages: [:])
        }
    }

    private func recordsWithPlannedLocalImages(from cards: [ScryfallCardDTO]) -> [CardRecord] {
        cards.map { card in
            let topLevel = imageResolver.localPaths(
                for: ScryfallCardNormalizer.imageURLs(for: card.imageURIs),
                cardID: card.id,
                faceIndex: nil
            )

            var faceImages: [Int: LocalImagePair] = [:]
            for (index, face) in (card.cardFaces ?? []).enumerated() {
                faceImages[index] = imageResolver.localPaths(
                    for: ScryfallCardNormalizer.imageURLs(for: face.imageURIs),
                    cardID: card.id,
                    faceIndex: index
                )
            }

            return ScryfallCardNormalizer.normalize(
                card,
                topLevelImages: topLevel,
                faceImages: faceImages
            )
        }
    }

    private func recordsWithExistingLocalImages(from cards: [ScryfallCardDTO]) -> [CardRecord] {
        cards.map { card in
            let topLevel = existingPaths(
                in: imageResolver.localPaths(
                    for: ScryfallCardNormalizer.imageURLs(for: card.imageURIs),
                    cardID: card.id,
                    faceIndex: nil
                )
            )

            var faceImages: [Int: LocalImagePair] = [:]
            for (index, face) in (card.cardFaces ?? []).enumerated() {
                faceImages[index] = existingPaths(
                    in: imageResolver.localPaths(
                        for: ScryfallCardNormalizer.imageURLs(for: face.imageURIs),
                        cardID: card.id,
                        faceIndex: index
                    )
                )
            }

            return ScryfallCardNormalizer.normalize(
                card,
                topLevelImages: topLevel,
                faceImages: faceImages
            )
        }
    }

    private func existingPaths(in paths: LocalImagePair, fileManager: FileManager = .default) -> LocalImagePair {
        LocalImagePair(
            smallPath: existingPath(paths.smallPath, fileManager: fileManager),
            normalPath: existingPath(paths.normalPath, fileManager: fileManager),
            largePath: existingPath(paths.largePath, fileManager: fileManager),
            artCropPath: existingPath(paths.artCropPath, fileManager: fileManager)
        )
    }

    private func existingPath(_ path: String?, fileManager: FileManager) -> String? {
        guard let path, fileManager.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    private func recordsByResolvingImages(
        for cards: [ScryfallCardDTO],
        qualities: Set<CardImageQuality>,
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async -> (records: [CardRecord], failedImageURLs: [URL]) {
        var records: [CardRecord] = []
        records.reserveCapacity(cards.count)

        var failedImageURLs: [URL] = []

        for (index, card) in cards.enumerated() {
            let result = await resolveImages(for: card, qualities: qualities)
            failedImageURLs.append(contentsOf: result.failedImageURLs)
            records.append(result.record)

            if shouldReportImageProgress(completedCards: index + 1, totalCards: cards.count) {
                await progress?(.downloadingImages(
                    completedCards: index + 1,
                    totalCards: cards.count,
                    failedImageCount: failedImageURLs.count
                ))
            }
        }

        return (records, failedImageURLs)
    }

    private func recordsByResolvingPreferredDisplayImages(
        for cards: [ScryfallCardDTO],
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async -> (records: [CardRecord], failedImageURLs: [URL]) {
        var records = recordsWithoutLocalImages(from: cards)
        let preferredIndexes = preferredDisplayImageIndexes(in: records)
        var failedImageURLs: [URL] = []

        for (progressIndex, recordIndex) in preferredIndexes.enumerated() {
            let result = await resolveImages(for: records[recordIndex], qualities: [.small])
            failedImageURLs.append(contentsOf: result.failedImageURLs)
            records[recordIndex] = result.record

            if shouldReportImageProgress(completedCards: progressIndex + 1, totalCards: preferredIndexes.count) {
                await progress?(.downloadingImages(
                    completedCards: progressIndex + 1,
                    totalCards: preferredIndexes.count,
                    failedImageCount: failedImageURLs.count
                ))
            }
        }

        return (records, failedImageURLs)
    }

    private func resolveImagesAfterInitialImport(
        for cards: [ScryfallCardDTO],
        totalCards: Int,
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async -> [URL] {
        var failedImageURLs: [URL] = []

        for (index, card) in cards.enumerated() {
            let result = await resolveImages(for: card, qualities: Set(CardImageQuality.allCases))
            failedImageURLs.append(contentsOf: result.failedImageURLs)
            try? database.updateImagePaths(for: result.record)

            if shouldReportImageProgress(completedCards: index + 1, totalCards: totalCards) {
                await progress?(.downloadingImages(
                    completedCards: index + 1,
                    totalCards: totalCards,
                    failedImageCount: failedImageURLs.count
                ))
            }
        }

        return failedImageURLs
    }

    private func resolveImages(
        for record: CardRecord,
        qualities: Set<CardImageQuality>
    ) async -> (record: CardRecord, failedImageURLs: [URL]) {
        var updated = record
        let topLevel = await imageResolver.resolve(
            record.remoteImageURLs,
            cardID: record.id,
            faceIndex: nil,
            qualities: qualities
        )
        var failedImageURLs = topLevel.failedURLs
        _ = updated.applyLocalImagePaths(topLevel.paths)

        for index in updated.faces.indices {
            let result = await imageResolver.resolve(
                updated.faces[index].remoteImageURLs,
                cardID: updated.id,
                faceIndex: updated.faces[index].faceIndex,
                qualities: qualities
            )
            _ = updated.faces[index].applyLocalImagePaths(result.paths)
            failedImageURLs.append(contentsOf: result.failedURLs)
        }

        return (updated, failedImageURLs)
    }

    private func resolveImages(
        for card: ScryfallCardDTO,
        qualities: Set<CardImageQuality>
    ) async -> (record: CardRecord, failedImageURLs: [URL]) {
        let topLevel = await imageResolver.resolve(
            ScryfallCardNormalizer.imageURLs(for: card.imageURIs),
            cardID: card.id,
            faceIndex: nil,
            qualities: qualities
        )

        var faceImages: [Int: LocalImagePair] = [:]
        var failedImageURLs = topLevel.failedURLs

        for (index, face) in (card.cardFaces ?? []).enumerated() {
            let result = await imageResolver.resolve(
                ScryfallCardNormalizer.imageURLs(for: face.imageURIs),
                cardID: card.id,
                faceIndex: index,
                qualities: qualities
            )
            faceImages[index] = result.paths
            failedImageURLs.append(contentsOf: result.failedURLs)
        }

        let record = ScryfallCardNormalizer.normalize(
            card,
            topLevelImages: topLevel.paths,
            faceImages: faceImages
        )

        return (record, failedImageURLs)
    }

    private func store(
        _ records: [CardRecord],
        manifest: BulkDataManifest?,
        imageCacheComplete: Bool,
        preservesCardValueHistory: Bool,
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async throws {
        await progress?(.storingSearchIndex(cardCount: records.count))
        try database.replaceAllCards(records, preservesCardValueHistory: preservesCardValueHistory)

        if let manifest {
            try database.saveMetadataValue(manifest.updatedAt, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
            try database.saveMetadataValue(manifest.downloadURI.absoluteString, forKey: MetadataKey.defaultCardsDownloadURI.rawValue)
            try database.saveMetadataValue(manifest.name, forKey: MetadataKey.defaultCardsName.rawValue)
            try database.saveMetadataValue("\(manifest.size)", forKey: MetadataKey.defaultCardsSize.rawValue)
        }
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue(imageCacheComplete ? "true" : "false", forKey: MetadataKey.requiredImagesCached.rawValue)

        await progress?(.cardDataReady(cardCount: records.count))
    }

    private func shouldReportImageProgress(completedCards: Int, totalCards: Int) -> Bool {
        completedCards == 1 || completedCards == totalCards || completedCards.isMultiple(of: 250)
    }

    private func preferredDisplayImageIndexes(in records: [CardRecord]) -> [Int] {
        var bestIndexByKey: [String: Int] = [:]

        for (index, record) in records.enumerated() {
            let key = record.displayNameKey.isEmpty ? record.name.normalizedCardNameKey : record.displayNameKey
            guard let currentIndex = bestIndexByKey[key] else {
                bestIndexByKey[key] = index
                continue
            }

            if isPreferredDisplayRepresentative(record, over: records[currentIndex]) {
                bestIndexByKey[key] = index
            }
        }

        return bestIndexByKey.values.sorted {
            let lhs = records[$0]
            let rhs = records[$1]
            let lhsKey = lhs.displayNameKey.isEmpty ? lhs.name.normalizedCardNameKey : lhs.displayNameKey
            let rhsKey = rhs.displayNameKey.isEmpty ? rhs.name.normalizedCardNameKey : rhs.displayNameKey
            if lhsKey != rhsKey {
                return lhsKey < rhsKey
            }
            return lhs.id < rhs.id
        }
    }

    private func isPreferredDisplayRepresentative(_ lhs: CardRecord, over rhs: CardRecord) -> Bool {
        let comparisons: [(CardRecord) -> Int] = [
            { $0.language == "en" ? 0 : 1 },
            { $0.isRealCard ? 0 : 1 },
            { $0.isBasePrinting ? 0 : 1 },
            { $0.hasRemoteSmallImage ? 0 : 1 }
        ]

        for comparison in comparisons {
            let lhsRank = comparison(lhs)
            let rhsRank = comparison(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
        }

        switch (lhs.releasedAt, rhs.releasedAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.setCode != rhs.setCode {
            return lhs.setCode < rhs.setCode
        }

        switch (lhs.collectorNumberNumber, rhs.collectorNumberNumber) {
        case let (lhsNumber?, rhsNumber?) where lhsNumber != rhsNumber:
            return lhsNumber < rhsNumber
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.collectorNumber != rhs.collectorNumber {
            return lhs.collectorNumber < rhs.collectorNumber
        }

        return lhs.id < rhs.id
    }
}

public enum MetadataKey: String, Sendable {
    case defaultCardsUpdatedAt
    case defaultCardsDownloadURI
    case defaultCardsName
    case defaultCardsSize
    case searchSchemaVersion
    case requiredImagesCached
    case lastUpdateCheck
    case mtgjsonCurrentPricesDate
    case mtgjsonCurrentPricesVersion
    case mtgjsonCurrentPricesCardDatabaseIdentity
    case mtgjsonPriceHistoryDate
    case mtgjsonPriceHistoryVersion
    case mtgjsonPriceHistoryCardDatabaseIdentity
}

private extension String {
    var normalizedCardNameKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }
}
