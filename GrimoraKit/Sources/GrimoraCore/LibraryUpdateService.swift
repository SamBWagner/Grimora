import Foundation

public enum UpdateCheckResult: Equatable, Sendable {
    case skipped(Date)
    case noLocalLibrary(BulkDataManifest)
    case upToDate(BulkDataManifest)
    case updateAvailable(BulkDataManifest)
}

public final class LibraryUpdateService: Sendable {
    private let database: CardDatabase
    private let bulkDataClient: BulkDataClient
    private let priceHistoryClient: MTGJSONPriceHistoryClient?
    private let priceHistoryImporter: MTGJSONPriceHistoryImporter?
    private let minimumAutomaticCheckInterval: TimeInterval

    public init(
        database: CardDatabase,
        bulkDataClient: BulkDataClient,
        priceHistoryClient: MTGJSONPriceHistoryClient? = nil,
        priceHistoryImporter: MTGJSONPriceHistoryImporter? = nil,
        minimumAutomaticCheckInterval: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.database = database
        self.bulkDataClient = bulkDataClient
        self.priceHistoryClient = priceHistoryClient
        self.priceHistoryImporter = priceHistoryImporter
        self.minimumAutomaticCheckInterval = minimumAutomaticCheckInterval
    }

    public func checkForUpdates(now: Date = Date(), manual: Bool) async throws -> UpdateCheckResult {
        if !manual,
           let lastCheck = try database.metadataValue(forKey: MetadataKey.lastUpdateCheck.rawValue).flatMap(Self.parseDate),
           now.timeIntervalSince(lastCheck) < minimumAutomaticCheckInterval {
            return .skipped(lastCheck)
        }

        let manifest = try await bulkDataClient.fetchDefaultCardsManifest()
        try database.saveMetadataValue(Self.formatDate(now), forKey: MetadataKey.lastUpdateCheck.rawValue)

        let cardCount = try database.cardCount()
        guard cardCount > 0 else {
            return .noLocalLibrary(manifest)
        }

        let localUpdatedAt = try database.metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        if localUpdatedAt == manifest.updatedAt {
            return .upToDate(manifest)
        }

        return .updateAvailable(manifest)
    }

    public func downloadAndImport(
        manifest: BulkDataManifest,
        temporaryDirectory: URL,
        importer: LibraryImporter,
        imagePolicy: ImageImportPolicy = .reuseExistingImagesWithoutDownloading,
        refreshesPriceHistory: Bool = true,
        preservesCardValueHistory: Bool? = nil,
        automatic: Bool = false,
        progress: (@Sendable (ImportProgress) async -> Void)? = nil
    ) async throws -> ImportSummary {
        if manifest.type == BulkDataManifest.grimoraCatalogType {
            return try await downloadAndInstallCatalog(
                manifest: manifest,
                temporaryDirectory: temporaryDirectory,
                automatic: automatic,
                progress: progress
            )
        }
        let destination = temporaryDirectory.appendingPathComponent("default-cards-\(manifest.updatedAt.fileSafeComponent).json")
        await progress?(.downloadingBulkData)
        let fallbackTotalBytes = manifest.size > 0 ? Int64(manifest.size) : nil
        try await bulkDataClient.downloadDefaultCards(manifest: manifest, to: destination) { downloadProgress in
            await progress?(
                .downloadingBulkDataProgress(
                    completedBytes: downloadProgress.completedBytes,
                    totalBytes: downloadProgress.totalBytes ?? fallbackTotalBytes
                )
            )
        }
        var summary = try await importer.importDefaultCards(
            from: destination,
            manifest: manifest,
            imagePolicy: imagePolicy,
            preservesCardValueHistory: preservesCardValueHistory ?? (priceHistoryClient != nil && priceHistoryImporter != nil),
            progress: progress
        )
        if refreshesPriceHistory {
            summary.priceHistoryStatus = await refreshPriceHistory(temporaryDirectory: temporaryDirectory, progress: progress)
        } else if priceHistoryClient != nil && priceHistoryImporter != nil {
            summary.priceHistoryStatus = .deferred
        }
        return summary
    }

    private func downloadAndInstallCatalog(
        manifest: BulkDataManifest,
        temporaryDirectory: URL,
        automatic: Bool,
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async throws -> ImportSummary {
        guard let catalog = manifest.catalog else {
            throw CatalogStorageError.invalidCatalog("Catalog manifest payload is missing")
        }

        // Prefer a small incremental delta patched onto the installed catalog; any failure (no chain,
        // missing base, multi-schema gap, digest mismatch, …) falls through to the full download.
        if let summary = try? await downloadAndInstallCatalogIncrementally(
            target: catalog,
            temporaryDirectory: temporaryDirectory,
            automatic: automatic,
            progress: progress
        ) {
            return summary
        }

        let compressedURL = temporaryDirectory
            .appendingPathComponent("catalog-\(catalog.version.fileSafeComponent).sqlite.gz")
        let stagedURL = temporaryDirectory
            .appendingPathComponent("catalog-\(catalog.version.fileSafeComponent).sqlite")
        defer {
            try? FileManager.default.removeItem(at: compressedURL)
            try? FileManager.default.removeItem(at: stagedURL)
        }

        await progress?(.downloadingBulkData)
        try await bulkDataClient.downloadDefaultCards(
            manifest: manifest,
            to: compressedURL,
            purpose: automatic ? .automaticCatalogDownload : .bulkDownload
        ) { downloadProgress in
            await progress?(
                .downloadingBulkDataProgress(
                    completedBytes: downloadProgress.completedBytes,
                    totalBytes: downloadProgress.totalBytes ?? catalog.artifact.compressedBytes
                )
            )
        }
        guard try FileSHA256.hash(url: compressedURL) == catalog.artifact.sha256 else {
            throw CatalogStorageError.invalidCatalog("Downloaded catalog SHA-256 does not match")
        }
        await progress?(.decodingCardData)
        try GzipArchive.decompressFile(at: compressedURL, to: stagedURL)
        guard try FileSHA256.hash(url: stagedURL) == catalog.artifact.uncompressedSHA256 else {
            throw CatalogStorageError.invalidCatalog("Expanded catalog SHA-256 does not match")
        }
        try database.installCatalog(from: stagedURL, expectedManifest: catalog)
        await progress?(.cardDataReady(cardCount: catalog.counts.cards))
        return ImportSummary(
            importedCards: catalog.counts.cards,
            failedImageURLs: [],
            priceHistoryStatus: .skipped
        )
    }

    /// Patches the installed catalog up to `target` using the delta chain, then swaps it in place via
    /// `installCatalog` — no restart, same as a full download but with a fraction of the bytes.
    /// Throws (→ caller falls back to a full download) on any mismatch, missing base, multi-build gap,
    /// or when the deltas would together rival the full artifact.
    private func downloadAndInstallCatalogIncrementally(
        target: CatalogManifest,
        temporaryDirectory: URL,
        automatic: Bool,
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async throws -> ImportSummary {
        guard let targetDigests = target.contentDigests,
            let attachedCatalogURL = database.attachedCatalogURL,
            let installedVersion = try database.metadataValue(
                forKey: MetadataKey.defaultCardsUpdatedAt.rawValue
            ),
            installedVersion != target.version
        else {
            throw CatalogStorageError.invalidCatalog("Incremental catalog update unavailable")
        }

        let chain = try await bulkDataClient.fetchCatalogChain()
        guard chain.current == target.version,
            let path = chain.deltaPath(from: installedVersion),
            !path.isEmpty,
            path.count <= CatalogDelta.maxChainSteps
        else {
            throw CatalogStorageError.invalidCatalog("No usable delta chain to the target")
        }
        let totalDeltaBytes = path.reduce(0) { $0 + $1.bytes }
        guard totalDeltaBytes < target.artifact.compressedBytes else {
            throw CatalogStorageError.invalidCatalog("Delta path rivals a full download")
        }

        let workingDirectory = temporaryDirectory.appendingPathComponent(
            "catalog-delta-\(target.version.fileSafeComponent)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        // Patch a copy of the currently-attached catalog, walking each consecutive delta.
        let workingCatalog = workingDirectory.appendingPathComponent("Catalog.sqlite")
        try FileManager.default.copyItem(at: attachedCatalogURL, to: workingCatalog)

        await progress?(.downloadingBulkData)
        var downloadedBytes: Int64 = 0
        for (index, delta) in path.enumerated() {
            let deltaGz = workingDirectory.appendingPathComponent("delta-\(index).sqlite.gz")
            let priorBytes = downloadedBytes
            try await bulkDataClient.downloadCatalogDelta(
                from: delta.url,
                to: deltaGz,
                purpose: automatic ? .automaticCatalogDownload : .bulkDownload
            ) { downloadProgress in
                await progress?(
                    .downloadingBulkDataProgress(
                        completedBytes: priorBytes + downloadProgress.completedBytes,
                        totalBytes: totalDeltaBytes
                    )
                )
            }
            guard try FileSHA256.hash(url: deltaGz) == delta.sha256 else {
                throw CatalogStorageError.invalidCatalog("Downloaded delta SHA-256 does not match")
            }
            downloadedBytes += delta.bytes

            let deltaSQLite = workingDirectory.appendingPathComponent("delta-\(index).sqlite")
            try GzipArchive.decompressFile(at: deltaGz, to: deltaSQLite)
            try CatalogDeltaApplier().apply(deltaURL: deltaSQLite, toWorkingCatalog: workingCatalog)
            try? FileManager.default.removeItem(at: deltaGz)
            try? FileManager.default.removeItem(at: deltaSQLite)
        }

        await progress?(.decodingCardData)
        // The chained-hash check: the patched catalog must be logically identical to a fresh build.
        let workingDigests = try CatalogContentDigest.compute(
            SQLiteDatabase(storage: .readOnlyFile(workingCatalog))
        )
        guard workingDigests == targetDigests else {
            throw CatalogStorageError.invalidCatalog("Patched catalog digests do not match target")
        }

        try database.installCatalog(from: workingCatalog, expectedManifest: target)
        await progress?(.cardDataReady(cardCount: target.counts.cards))
        return ImportSummary(
            importedCards: target.counts.cards,
            failedImageURLs: [],
            priceHistoryStatus: .skipped
        )
    }

    public func refreshPriceHistory(
        temporaryDirectory: URL,
        progress: (@Sendable (ImportProgress) async -> Void)? = nil
    ) async -> PriceHistoryImportStatus {
        let plan = await priceHistoryPlan()
        return await importPriceHistory(using: plan, temporaryDirectory: temporaryDirectory, progress: progress)
    }

    public func runPendingValueHistoryBackgroundImport(
        backgroundDirectory: URL,
        temporaryDirectory: URL,
        progress: (@Sendable (ValueHistoryBackgroundJob) async -> Void)? = nil
    ) async -> PriceHistoryImportStatus? {
        guard let priceHistoryClient, let priceHistoryImporter else {
            return nil
        }

        do {
            guard var job = try database.incompleteValueHistoryBackgroundJob() else {
                return nil
            }

            let currentIdentity = try database.valueHistoryCardDatabaseIdentity()
            if job.cardDatabaseIdentity != currentIdentity {
                try discardBackgroundFiles(for: job, in: backgroundDirectory)
                try database.discardValueHistoryBackgroundJob(id: job.id)
                let fresh = try database.prepareValueHistoryBackgroundJob(
                    meta: job.meta,
                    cardDatabaseIdentity: currentIdentity
                )
                job = fresh
                await progress?(fresh)
            }

            let status = try await runValueHistoryBackgroundImport(
                job: job,
                backgroundDirectory: backgroundDirectory,
                temporaryDirectory: temporaryDirectory,
                priceHistoryClient: priceHistoryClient,
                priceHistoryImporter: priceHistoryImporter,
                progress: progress
            )
            return status
        } catch {
            if let running = try? database.incompleteValueHistoryBackgroundJob() {
                try? discardBackgroundFiles(for: running, in: backgroundDirectory)
                try? database.discardValueHistoryStaging(jobID: running.id)
                if let failed = try? database.updateValueHistoryBackgroundJob(
                    id: running.id,
                    stage: .failed,
                    status: .failed,
                    lastError: String(describing: error)
                ) {
                    await progress?(failed)
                }
            }
            return .failed
        }
    }

    private func priceHistoryPlan() async -> PriceHistoryPlan {
        guard let priceHistoryClient, priceHistoryImporter != nil else {
            return .notConfigured
        }

        do {
            let meta = try await priceHistoryClient.fetchMeta()
            let cardDatabaseIdentity = try database.valueHistoryCardDatabaseIdentity()
            let localDate = try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
            let localVersion = try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
            let localIdentity = try database.metadataValue(
                forKey: MetadataKey.mtgjsonPriceHistoryCardDatabaseIdentity.rawValue
            )
            if localDate == meta.date,
               localVersion == meta.version,
               localIdentity == cardDatabaseIdentity,
               (try database.hasUsableValueSummaryCoverage()) {
                return .skipped
            }

            let currentDate = try database.metadataValue(forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue)
            let currentVersion = try database.metadataValue(forKey: MetadataKey.mtgjsonCurrentPricesVersion.rawValue)
            let currentIdentity = try database.metadataValue(
                forKey: MetadataKey.mtgjsonCurrentPricesCardDatabaseIdentity.rawValue
            )
            if currentDate == meta.date,
               currentVersion == meta.version,
               currentIdentity == cardDatabaseIdentity,
               (try database.hasUsableValueSummaryCoverage()),
               (try database.hasUsableValueMappingCoverage()) {
                _ = try database.prepareValueHistoryBackgroundJob(meta: meta, cardDatabaseIdentity: cardDatabaseIdentity)
                return .currentPricesReadyNeedsHistory(meta)
            }

            return .needsCurrentPriceImport(meta)
        } catch {
            return .failed
        }
    }

    private func importPriceHistory(
        using plan: PriceHistoryPlan,
        temporaryDirectory: URL,
        progress: (@Sendable (ImportProgress) async -> Void)?
    ) async -> PriceHistoryImportStatus {
        guard let priceHistoryClient, let priceHistoryImporter else {
            return .notConfigured
        }

        switch plan {
        case .notConfigured:
            return .notConfigured
        case .skipped:
            return .skipped
        case .failed:
            return .failed
        case .currentPricesReadyNeedsHistory(let meta):
            do {
                _ = try database.prepareValueHistoryBackgroundJob(
                    meta: meta,
                    cardDatabaseIdentity: try database.valueHistoryCardDatabaseIdentity()
                )
                return .skipped
            } catch {
                return .failed
            }
        case .needsCurrentPriceImport(let meta):
            do {
                await progress?(.downloadingPriceHistoryData)
                let printingsDestination = temporaryDirectory
                    .appendingPathComponent("mtgjson-all-printings-\(meta.date.fileSafeComponent).json.gz")
                let pricesTodayDestination = temporaryDirectory
                    .appendingPathComponent("mtgjson-all-prices-today-\(meta.date.fileSafeComponent).json.gz")
                try await priceHistoryClient.downloadAllPrintings(to: printingsDestination) { downloadProgress in
                    await progress?(
                        .downloadingPriceHistoryDataProgress(
                            file: .cardIdentifiers,
                            completedBytes: downloadProgress.completedBytes,
                            totalBytes: downloadProgress.totalBytes
                        )
                    )
                }
                try await priceHistoryClient.downloadAllPricesToday(to: pricesTodayDestination) { downloadProgress in
                    await progress?(
                        .downloadingPriceHistoryDataProgress(
                            file: .currentPrices,
                            completedBytes: downloadProgress.completedBytes,
                            totalBytes: downloadProgress.totalBytes
                        )
                    )
                }
                defer {
                    try? FileManager.default.removeItem(at: printingsDestination)
                    try? FileManager.default.removeItem(at: pricesTodayDestination)
                }

                let priceSummary = try await priceHistoryImporter.importCurrentPrices(
                    meta: meta,
                    allPrintingsGzipURL: printingsDestination,
                    allPricesTodayGzipURL: pricesTodayDestination,
                    temporaryDirectory: temporaryDirectory,
                    progress: progress
                )
                _ = try database.prepareValueHistoryBackgroundJob(
                    meta: meta,
                    cardDatabaseIdentity: try database.valueHistoryCardDatabaseIdentity()
                )
                await progress?(.priceHistoryReady(pricePointCount: priceSummary.importedPricePoints))
                return .imported(priceSummary)
            } catch {
                return .failed
            }
        }
    }

    private func runValueHistoryBackgroundImport(
        job: ValueHistoryBackgroundJob,
        backgroundDirectory: URL,
        temporaryDirectory: URL,
        priceHistoryClient: MTGJSONPriceHistoryClient,
        priceHistoryImporter: MTGJSONPriceHistoryImporter,
        progress: (@Sendable (ValueHistoryBackgroundJob) async -> Void)?
    ) async throws -> PriceHistoryImportStatus {
        try FileManager.default.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)
        var activeJob = try database.updateValueHistoryBackgroundJob(
            id: job.id,
            stage: .downloadingPrices,
            status: .running,
            downloadedBytes: 0,
            totalDownloadBytes: nil,
            scannedBytes: 0,
            totalScanBytes: nil,
            importedPricePoints: 0
        ) ?? job
        await progress?(activeJob)

        let pricesGzipURL = backgroundAllPricesURL(for: activeJob, in: backgroundDirectory)
        let partialPricesGzipURL = pricesGzipURL.deletingLastPathComponent()
            .appendingPathComponent("\(pricesGzipURL.lastPathComponent).partial")
        let jobID = activeJob.id
        if !FileManager.default.fileExists(atPath: pricesGzipURL.path) {
            try? FileManager.default.removeItem(at: partialPricesGzipURL)
            try await priceHistoryClient.downloadAllPrices(to: partialPricesGzipURL) { [database, jobID] downloadProgress in
                if let updated = try? database.updateValueHistoryBackgroundJob(
                    id: jobID,
                    stage: .downloadingPrices,
                    status: .running,
                    downloadedBytes: downloadProgress.completedBytes,
                    totalDownloadBytes: downloadProgress.totalBytes
                ) {
                    await progress?(updated)
                }
            }
            if FileManager.default.fileExists(atPath: pricesGzipURL.path) {
                try FileManager.default.removeItem(at: pricesGzipURL)
            }
            try FileManager.default.moveItem(at: partialPricesGzipURL, to: pricesGzipURL)
        }

        activeJob = try database.updateValueHistoryBackgroundJob(
            id: activeJob.id,
            stage: .decompressingPrices,
            status: .running
        ) ?? activeJob
        await progress?(activeJob)

        let pricesJSONURL = temporaryDirectory
            .appendingPathComponent("mtgjson-all-prices-background-\(activeJob.mtgjsonDate.fileSafeComponent).json")
        try MTGJSONGzip.decompressFile(at: pricesGzipURL, to: pricesJSONURL)
        defer {
            try? FileManager.default.removeItem(at: pricesJSONURL)
        }

        let mappingsByMTGJSONUUID = try database.valueMappingsByMTGJSONUUID()
        guard !mappingsByMTGJSONUUID.isEmpty else {
            throw MTGJSONPriceHistoryError.missingCurrentPriceMappings
        }

        let summary = try await priceHistoryImporter.importHistoryToStaging(
            meta: activeJob.meta,
            mappingsByMTGJSONUUID: mappingsByMTGJSONUUID,
            allPricesJSONURL: pricesJSONURL,
            jobID: jobID
        ) { [database, jobID] importProgress in
            switch importProgress {
            case .buildingPriceIDMap:
                if let updated = try? database.updateValueHistoryBackgroundJob(
                    id: jobID,
                    stage: .mappingCards,
                    status: .running,
                    scannedBytes: 0,
                    totalScanBytes: nil
                ) {
                    await progress?(updated)
                }
            case .buildingPriceIDMapProgress(let scannedBytes, let totalBytes, let mappedCards):
                if let updated = try? database.updateValueHistoryBackgroundJob(
                    id: jobID,
                    stage: .mappingCards,
                    status: .running,
                    scannedBytes: scannedBytes,
                    totalScanBytes: totalBytes,
                    importedPricePoints: mappedCards
                ) {
                    await progress?(updated)
                }
            case .importingPriceHistory:
                if let updated = try? database.updateValueHistoryBackgroundJob(
                    id: jobID,
                    stage: .importingHistory,
                    status: .running,
                    scannedBytes: 0,
                    totalScanBytes: nil
                ) {
                    await progress?(updated)
                }
            case .importingPriceHistoryProgress(let scannedBytes, let totalBytes, let importedPricePoints):
                if let updated = try? database.updateValueHistoryBackgroundJob(
                    id: jobID,
                    stage: .importingHistory,
                    status: .running,
                    scannedBytes: scannedBytes,
                    totalScanBytes: totalBytes,
                    importedPricePoints: importedPricePoints
                ) {
                    await progress?(updated)
                }
            default:
                break
            }
        }

        activeJob = try database.updateValueHistoryBackgroundJob(
            id: activeJob.id,
            stage: .committingHistory,
            status: .running,
            importedPricePoints: summary.importedPricePoints
        ) ?? activeJob
        await progress?(activeJob)

        let committedSummary = try database.commitStagedValueHistory(jobID: activeJob.id, meta: activeJob.meta)
        if let completed = try database.updateValueHistoryBackgroundJob(
            id: activeJob.id,
            stage: .completed,
            status: .succeeded,
            importedPricePoints: committedSummary.importedPricePoints
        ) {
            await progress?(completed)
        }
        try discardBackgroundFiles(for: activeJob, in: backgroundDirectory)
        return .imported(committedSummary)
    }

    private func backgroundAllPricesURL(for job: ValueHistoryBackgroundJob, in directory: URL) -> URL {
        directory.appendingPathComponent("mtgjson-all-prices-\(job.mtgjsonDate.fileSafeComponent).json.gz")
    }

    private func discardBackgroundFiles(for job: ValueHistoryBackgroundJob, in directory: URL) throws {
        let url = backgroundAllPricesURL(for: job, in: directory)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(
            at: url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).partial")
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        isoDateFormatter().date(from: value)
    }

    private static func formatDate(_ date: Date) -> String {
        isoDateFormatter().string(from: date)
    }

    private static func isoDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private enum PriceHistoryPlan {
    case notConfigured
    case skipped
    case currentPricesReadyNeedsHistory(MTGJSONPriceHistoryMeta)
    case needsCurrentPriceImport(MTGJSONPriceHistoryMeta)
    case failed
}

private extension String {
    var fileSafeComponent: String {
        map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { $0.append($1) }
    }
}
