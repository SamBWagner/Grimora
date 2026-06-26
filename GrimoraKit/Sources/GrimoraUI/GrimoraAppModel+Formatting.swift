import Foundation
import GrimoraCore

extension GrimoraAppModel {
  func manifestForInitialSetup(from result: UpdateCheckResult) -> BulkDataManifest {
    switch result {
    case .skipped:
      preconditionFailure("Manual setup checks should not be skipped.")
    case .noLocalLibrary(let manifest), .upToDate(let manifest), .updateAvailable(let manifest):
      return manifest
    }
  }

  func handleImportProgress(_ progress: ImportProgress, manifest: BulkDataManifest) {
    syncLibraryActivityHeartbeat(for: progress)

    switch progress {
    case .downloadingBulkData:
      statusMessage =
        "Downloading \(manifest.name) (\(Self.byteCountFormatter.string(fromByteCount: Int64(manifest.size))))..."
    case .downloadingBulkDataProgress(let completedBytes, let totalBytes):
      statusMessage = downloadStatusMessage(
        label: manifest.name,
        completedBytes: completedBytes,
        totalBytes: totalBytes
      )
    case .decodingCardData:
      statusMessage = "Reading Scryfall card data... this can take a few minutes on first install."
    case .storingSearchIndex(let cardCount):
      statusMessage = "Writing offline search index for \(formatted(cardCount)) cards..."
    case .storingSearchIndexProgress(let writeProgress):
      statusMessage = cardDatabaseBuildStatusMessage(for: writeProgress)
    case .cardDataReady(let cardCount):
      updateManifest = nil
      statusMessage = "Finalizing offline library for \(formatted(cardCount)) cards..."
    case .downloadingPriceHistoryData:
      statusMessage = "Downloading MTGJSON current prices..."
    case .downloadingPriceHistoryDataProgress(let file, let completedBytes, let totalBytes):
      statusMessage = downloadStatusMessage(
        label: priceHistoryDownloadLabel(for: file),
        completedBytes: completedBytes,
        totalBytes: totalBytes
      )
    case .buildingPriceIDMap:
      statusMessage = "Mapping cards to current prices..."
    case .buildingPriceIDMapProgress(let scannedBytes, let totalBytes, let mappedCards):
      statusMessage = scanStatusMessage(
        label: "MTGJSON card identifiers",
        scannedBytes: scannedBytes,
        totalBytes: totalBytes,
        suffix: mappedCards > 0 ? "\(formatted(mappedCards)) mapped" : nil
      )
    case .importingPriceHistory:
      statusMessage = "Importing current TCGplayer prices..."
    case .importingPriceHistoryProgress(let scannedBytes, let totalBytes, let importedPricePoints):
      statusMessage = scanStatusMessage(
        label: "TCGplayer prices",
        scannedBytes: scannedBytes,
        totalBytes: totalBytes,
        suffix: importedPricePoints > 0 ? "\(formatted(importedPricePoints)) prices" : nil
      )
    case .priceHistoryReady(let pricePointCount):
      statusMessage = "Indexed \(formatted(pricePointCount)) TCGplayer price points."
    case .downloadingImages(let completedCards, let totalCards, let failedImageCount):
      statusMessage =
        failedImageCount == 0
        ? "Downloading images \(formatted(completedCards)) of \(formatted(totalCards))..."
        : "Downloading images \(formatted(completedCards)) of \(formatted(totalCards)). \(failedImageCount) failed so far."
    }
    updateLibraryActivity(message: statusMessage) { steps in
      Self.applyImportProgress(
        progress,
        manifest: manifest,
        operation: self.libraryActivity?.operation,
        to: &steps
      )
    }
  }

  func handlePriceHistoryProgress(_ progress: ImportProgress) {
    stopLibraryActivityHeartbeat()

    switch progress {
    case .downloadingPriceHistoryData:
      statusMessage = "Downloading MTGJSON current prices..."
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    case .downloadingPriceHistoryDataProgress(let file, let completedBytes, let totalBytes):
      statusMessage = downloadStatusMessage(
        label: priceHistoryDownloadLabel(for: file),
        completedBytes: completedBytes,
        totalBytes: totalBytes
      )
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    case .buildingPriceIDMap:
      statusMessage = "Mapping cards to current prices..."
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    case .buildingPriceIDMapProgress(let scannedBytes, let totalBytes, let mappedCards):
      statusMessage = scanStatusMessage(
        label: "MTGJSON card identifiers",
        scannedBytes: scannedBytes,
        totalBytes: totalBytes,
        suffix: mappedCards > 0 ? "\(formatted(mappedCards)) mapped" : nil
      )
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    case .importingPriceHistory:
      statusMessage = "Importing current TCGplayer prices..."
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    case .importingPriceHistoryProgress(let scannedBytes, let totalBytes, let importedPricePoints):
      statusMessage = scanStatusMessage(
        label: "TCGplayer prices",
        scannedBytes: scannedBytes,
        totalBytes: totalBytes,
        suffix: importedPricePoints > 0 ? "\(formatted(importedPricePoints)) prices" : nil
      )
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    case .priceHistoryReady(let pricePointCount):
      statusMessage = "Indexed \(formatted(pricePointCount)) TCGplayer price points."
      updateLibraryActivity(message: statusMessage) { steps in
        Self.applyImportProgress(progress, manifest: nil, to: &steps)
      }
    default:
      break
    }
  }

  func syncLibraryActivityHeartbeat(for progress: ImportProgress) {
    switch progress {
    case .downloadingBulkData:
      startLibraryActivityHeartbeat(stage: .downloadCardData)
    case .decodingCardData:
      startLibraryActivityHeartbeat(stage: .readCardData)
    case .storingSearchIndex:
      startLibraryActivityHeartbeat(stage: .buildCardLibrary)
    case .cardDataReady:
      break
    case .storingSearchIndexProgress:
      break
    default:
      stopLibraryActivityHeartbeat()
    }
  }

  func priceHistoryStatusMessage(for status: PriceHistoryImportStatus) -> String {
    switch status {
    case .notConfigured:
      "Value history updates are unavailable."
    case .deferred:
      "Values are updating in the background."
    case .skipped:
      "Value history is current."
    case .imported(let summary):
      "Indexed \(formatted(summary.importedPricePoints)) value points."
    case .failed:
      "Value history could not be updated; card search is ready."
    }
  }

  func formatted(_ value: Int) -> String {
    Self.integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  func downloadStatusMessage(label: String, completedBytes: Int64, totalBytes: Int64?) -> String {
    let completed = Self.byteCountFormatter.string(fromByteCount: completedBytes)
    guard let totalBytes, totalBytes > 0 else {
      return "Downloading \(label) (\(completed) downloaded)..."
    }

    let total = Self.byteCountFormatter.string(fromByteCount: totalBytes)
    return "Downloading \(label) (\(completed) of \(total))..."
  }

  func priceHistoryDownloadLabel(for file: PriceHistoryDownloadFile) -> String {
    switch file {
    case .cardIdentifiers:
      "MTGJSON card identifiers"
    case .currentPrices:
      "MTGJSON current prices"
    case .prices:
      "MTGJSON price history"
    case .fullHistoryPrices:
      "MTGJSON 90-day price history"
    }
  }

  func scanStatusMessage(label: String, scannedBytes: Int64, totalBytes: Int64?, suffix: String?) -> String {
    let completed = Self.byteCountFormatter.string(fromByteCount: scannedBytes)
    let base: String
    if let totalBytes, totalBytes > 0 {
      let total = Self.byteCountFormatter.string(fromByteCount: totalBytes)
      base = "Scanning \(label) (\(completed) of \(total))"
    } else {
      base = "Scanning \(label) (\(completed) scanned)"
    }

    guard let suffix else {
      return "\(base)..."
    }
    return "\(base); \(suffix)."
  }

  func cardDatabaseBuildStatusMessage(for progress: CardDatabaseWriteProgress) -> String {
    switch progress.phase {
    case .preparingMetadata:
      let completed = formatted(progress.completedUnitCount)
      let total = formatted(progress.totalUnitCount ?? 0)
      return "Preparing offline search fields for \(completed) of \(total) cards..."
    case .preservingValueHistory:
      return "Preserving existing value history before replacing cards..."
    case .clearingValueHistoryCache:
      if let totalUnitCount = progress.totalUnitCount {
        return
          "Clearing cached value rows \(formatted(progress.completedUnitCount)) of \(formatted(totalUnitCount))..."
      }
      return "Checking cached value rows before replacing cards..."
    case .resettingCachedLibrary:
      return "Resetting cached library tables..."
    case .resettingSearchIndex:
      return "Resetting offline search tables..."
    case .clearingExistingLibrary:
      if let totalUnitCount = progress.totalUnitCount {
        return
          "Clearing old card records \(formatted(progress.completedUnitCount)) of \(formatted(totalUnitCount))..."
      }
      return "Clearing old card records..."
    case .writingCards:
      return "Writing offline search index for \(formatted(progress.writtenCards)) of \(formatted(progress.totalCards)) cards..."
    case .restoringValueHistory:
      return "Restoring value history for refreshed cards..."
    }
  }

  func libraryMaintenanceFailureMessage(fallback: String, error: Error) -> String {
    guard let maintenanceError = error as? CardDatabaseMaintenanceError else {
      return fallback
    }

    switch maintenanceError {
    case .clearValueHistoryCacheStalled:
      return "Library refresh stopped because cached value rows did not delete anything. Existing lists were preserved."
    case .clearValueHistoryCacheTimedOut(_, _, let seconds):
      return "Library refresh stopped because cached value rows made no progress for \(seconds)s. Existing lists were preserved."
    case .clearExistingLibraryStalled:
      return "Library refresh stopped because clearing old card records did not delete anything. Existing lists were preserved."
    case .clearExistingLibraryTimedOut(_, _, let seconds):
      return "Library refresh stopped because clearing old card records made no progress for \(seconds)s. Existing lists were preserved."
    case .resetSearchIndexTimedOut(let seconds):
      return "Library refresh stopped because resetting offline search tables made no progress for \(seconds)s. Existing lists were preserved."
    }
  }

  func priceHistoryStatusSuffix(for status: PriceHistoryImportStatus) -> String {
    switch status {
    case .notConfigured:
      ""
    case .deferred:
      " Values update in background."
    case .skipped:
      " Value history is current."
    case .imported(let summary):
      " Indexed \(formatted(summary.importedPricePoints)) value points."
    case .failed:
      " Value history could not be updated; card search is ready."
    }
  }

  static let byteCountFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
  }()

  static let integerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  static let searchHistorySettleDelayNanoseconds: UInt64 = 450_000_000
  static let maximumListUndoDepth = 60

  static func normalizedImportListName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Imported Collection" : trimmed
  }

  static func normalizedDefaultSearchConfiguration(
    _ configuration: GrimoraDefaultSearchConfiguration
  ) -> GrimoraDefaultSearchConfiguration {
    GrimoraDefaultSearchConfiguration(
      text: configuration.normalizedText,
      alwaysIncludedText: configuration.normalizedAlwaysIncludedText,
      sortMode: configuration.sortMode,
      sortDirection: configuration.sortDirection
    )
  }

  static func normalizedCategoryKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }
}
