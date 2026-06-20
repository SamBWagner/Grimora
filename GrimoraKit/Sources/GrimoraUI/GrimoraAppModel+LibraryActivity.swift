import Foundation
import GrimoraCore

enum LibraryActivityStepID {
  static let checkCardData = "check-card-data"
  static let downloadCardData = "download-card-data"
  static let readCardData = "read-card-data"
  static let buildCardLibrary = "build-card-library"
  static let deleteCachedImages = "delete-cached-images"
  static let finalizeCardLibrary = "finalize-card-library"
  static let checkPriceHistory = "check-price-history"
  static let downloadPriceIdentifiers = "download-price-identifiers"
  static let downloadPrices = "download-prices"
  static let indexPriceHistory = "index-price-history"
  static let downloadImages = "download-images"
}

enum LibraryActivityHeartbeatStage {
  case checkCardData
  case downloadCardData
  case readCardData
  case buildCardLibrary
  case deleteCachedImages
  case finalizeCardLibrary

  var stepID: String {
    switch self {
    case .checkCardData:
      LibraryActivityStepID.checkCardData
    case .downloadCardData:
      LibraryActivityStepID.downloadCardData
    case .readCardData:
      LibraryActivityStepID.readCardData
    case .buildCardLibrary:
      LibraryActivityStepID.buildCardLibrary
    case .deleteCachedImages:
      LibraryActivityStepID.deleteCachedImages
    case .finalizeCardLibrary:
      LibraryActivityStepID.finalizeCardLibrary
    }
  }

  var title: String {
    switch self {
    case .checkCardData:
      "Check card database"
    case .downloadCardData:
      "Download card data"
    case .readCardData:
      "Read card data"
    case .buildCardLibrary:
      "Build local library"
    case .deleteCachedImages:
      "Delete cached images"
    case .finalizeCardLibrary:
      "Finalize library"
    }
  }

  func message(elapsedSeconds: Int, currentDetail: String? = nil) -> String {
    let elapsed = GrimoraAppModel.elapsedTimeDescription(elapsedSeconds)
    let detail = currentDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch self {
    case .checkCardData:
      return elapsedSeconds > 0
        ? "Checking Scryfall bulk data... still working after \(elapsed)."
        : "Checking Scryfall bulk data..."
    case .downloadCardData:
      return elapsedSeconds > 0
        ? "Downloading card data... still working after \(elapsed)."
        : "Downloading card data..."
    case .readCardData:
      return elapsedSeconds > 0
        ? "Reading Scryfall card data... still working after \(elapsed)."
        : "Reading Scryfall card data..."
    case .buildCardLibrary:
      if let detail, !detail.isEmpty {
        return elapsedSeconds > 0
          ? "\(detail)... still working after \(elapsed)."
          : "\(detail)..."
      }
      return elapsedSeconds > 0
        ? "Writing offline search index... still working after \(elapsed)."
        : "Writing offline search index..."
    case .deleteCachedImages:
      if let detail, !detail.isEmpty {
        return elapsedSeconds > 0
          ? "\(detail)... still working after \(elapsed)."
          : "\(detail)..."
      }
      return elapsedSeconds > 0
        ? "Deleting cached card images... still working after \(elapsed)."
        : "Deleting cached card images..."
    case .finalizeCardLibrary:
      return elapsedSeconds > 0
        ? "Finalizing offline library... still working after \(elapsed)."
        : "Finalizing offline library..."
    }
  }

  func detail(elapsedSeconds: Int, currentDetail: String? = nil) -> String {
    let elapsed = GrimoraAppModel.elapsedTimeDescription(elapsedSeconds)
    let detail = currentDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch self {
    case .checkCardData:
      return "Checking card database, \(elapsed)"
    case .downloadCardData:
      return "Starting download, \(elapsed)"
    case .readCardData:
      return "Reading card data, \(elapsed)"
    case .buildCardLibrary:
      if let detail, !detail.isEmpty {
        return detail
      }
      return "Writing card records, \(elapsed)"
    case .deleteCachedImages:
      if let detail, !detail.isEmpty {
        return detail
      }
      return "Deleting image cache, \(elapsed)"
    case .finalizeCardLibrary:
      return "Preparing offline search, \(elapsed)"
    }
  }

  var defaultProgress: Double? {
    switch self {
    case .checkCardData:
      0.15
    case .downloadCardData:
      0.02
    case .readCardData:
      nil
    case .buildCardLibrary:
      0
    case .deleteCachedImages:
      nil
    case .finalizeCardLibrary:
      nil
    }
  }
}

extension GrimoraAppModel {
  @discardableResult
  func beginLibraryActivity(
    operation: GrimoraLibraryActivityOperation,
    title: String,
    message: String
  ) -> UUID {
    libraryActivityDismissTask?.cancel()
    libraryActivityDismissTask = nil
    stopLibraryActivityHeartbeat()

    let id = UUID()
    libraryActivity = GrimoraLibraryActivity(
      id: id,
      operation: operation,
      title: title,
      message: message,
      state: .running,
      steps: Self.initialLibraryActivitySteps(for: operation)
    )
    return id
  }

  func updateLibraryActivity(
    id: UUID? = nil,
    message: String,
    updateSteps: ((inout [GrimoraLibraryActivityStep]) -> Void)? = nil
  ) {
    guard var activity = libraryActivity else {
      return
    }
    if let id, activity.id != id {
      return
    }

    activity.message = message
    activity.state = .running
    updateSteps?(&activity.steps)
    libraryActivity = activity
  }

  func finishLibraryActivity(
    id: UUID? = nil,
    message: String,
    state: GrimoraLibraryActivityState
  ) {
    guard var activity = libraryActivity else {
      return
    }
    if let id, activity.id != id {
      return
    }

    activity.message = message
    activity.state = state
    activity.steps = Self.finishedLibraryActivitySteps(activity.steps, state: state)
    stopLibraryActivityHeartbeat()
    libraryActivity = activity
    if state == .succeeded {
      scheduleLibraryActivityDismissal(for: activity.id)
    } else {
      libraryActivityDismissTask?.cancel()
      libraryActivityDismissTask = nil
    }
  }

  func dismissLibraryActivity(id: UUID? = nil) {
    if let id, libraryActivity?.id != id {
      return
    }

    libraryActivityDismissTask?.cancel()
    libraryActivityDismissTask = nil
    stopLibraryActivityHeartbeat()
    libraryActivity = nil
  }

  func startLibraryActivityHeartbeat(stage: LibraryActivityHeartbeatStage) {
    libraryActivityHeartbeatTask?.cancel()
    let startedAt = Date()
    libraryActivityHeartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: Self.libraryActivityHeartbeatIntervalNanoseconds)
        guard !Task.isCancelled else {
          return
        }

        let elapsedSeconds = Int(Date().timeIntervalSince(startedAt).rounded(.down))
        await MainActor.run {
          self?.publishLibraryActivityHeartbeat(stage: stage, elapsedSeconds: elapsedSeconds)
        }
      }
    }
    publishLibraryActivityHeartbeat(stage: stage, elapsedSeconds: 0)
  }

  func stopLibraryActivityHeartbeat() {
    libraryActivityHeartbeatTask?.cancel()
    libraryActivityHeartbeatTask = nil
  }

  private func publishLibraryActivityHeartbeat(
    stage: LibraryActivityHeartbeatStage,
    elapsedSeconds: Int
  ) {
    guard libraryActivityHeartbeatTask != nil,
      let activity = libraryActivity,
      activity.state == .running
    else {
      return
    }

    let currentStep = activity.steps.first(where: { $0.id == stage.stepID })
    let message = stage.message(elapsedSeconds: elapsedSeconds, currentDetail: currentStep?.detail)
    statusMessage = message
    updateLibraryActivity(message: message) { steps in
      let currentProgress = steps.first(where: { $0.id == stage.stepID })?.progress
      let currentDetail = steps.first(where: { $0.id == stage.stepID })?.detail
      Self.updateStep(
        stage.stepID,
        title: stage.title,
        detail: stage.detail(elapsedSeconds: elapsedSeconds, currentDetail: currentDetail),
        progress: currentProgress ?? stage.defaultProgress,
        state: .running,
        in: &steps
      )
    }
  }

  func finishLibraryActivityForPriceHistory(_ status: PriceHistoryImportStatus) {
    let state: GrimoraLibraryActivityState =
      switch status {
      case .failed, .notConfigured:
        .failed
      case .deferred, .skipped, .imported:
        .succeeded
      }
    finishLibraryActivity(
      message: priceHistoryStatusMessage(for: status),
      state: state
    )
  }

  func finishLibraryActivityForImportSummary(
    _ summary: ImportSummary,
    message: String
  ) {
    finishLibraryActivity(
      message: message,
      state: libraryActivityState(for: summary.priceHistoryStatus)
    )
  }

  func libraryActivityState(for status: PriceHistoryImportStatus) -> GrimoraLibraryActivityState {
    switch status {
    case .failed:
      .failed
    case .notConfigured, .deferred, .skipped, .imported:
      .succeeded
    }
  }

  private func scheduleLibraryActivityDismissal(for id: UUID) {
    libraryActivityDismissTask?.cancel()
    libraryActivityDismissTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: Self.libraryActivityCompletionDelayNanoseconds)
      guard !Task.isCancelled else {
        return
      }

      await MainActor.run {
        guard self?.libraryActivity?.id == id else {
          return
        }

        self?.libraryActivity = nil
        self?.libraryActivityDismissTask = nil
      }
    }
  }

  static let libraryActivityCompletionDelayNanoseconds: UInt64 = 2_500_000_000
  static let libraryActivityHeartbeatIntervalNanoseconds: UInt64 = 2_000_000_000

  nonisolated fileprivate static func elapsedTimeDescription(_ seconds: Int) -> String {
    guard seconds >= 60 else {
      return "\(max(seconds, 0))s"
    }

    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
  }
}

extension GrimoraAppModel {
  static func initialLibraryActivitySteps(
    for operation: GrimoraLibraryActivityOperation
  ) -> [GrimoraLibraryActivityStep] {
    switch operation {
    case .setupLibrary:
      [
        step(id: LibraryActivityStepID.checkCardData, title: "Check card database", progress: 0.15, state: .running),
        step(id: LibraryActivityStepID.downloadCardData, title: "Download card data"),
        step(id: LibraryActivityStepID.readCardData, title: "Read card data"),
        step(id: LibraryActivityStepID.buildCardLibrary, title: "Build local library"),
        step(id: LibraryActivityStepID.finalizeCardLibrary, title: "Finalize library"),
      ]
    case .deleteAndRefreshDatabase:
      [
        step(id: LibraryActivityStepID.downloadCardData, title: "Download card data"),
        step(id: LibraryActivityStepID.readCardData, title: "Read card data"),
        step(id: LibraryActivityStepID.buildCardLibrary, title: "Build local library"),
        step(id: LibraryActivityStepID.deleteCachedImages, title: "Delete cached images"),
        step(id: LibraryActivityStepID.finalizeCardLibrary, title: "Finalize library"),
      ]
    case .importCardDatabase, .refreshCardDatabase, .updateSyncedDatabase:
      [
        step(id: LibraryActivityStepID.downloadCardData, title: "Download card data"),
        step(id: LibraryActivityStepID.readCardData, title: "Read card data"),
        step(id: LibraryActivityStepID.buildCardLibrary, title: "Build local library"),
        step(id: LibraryActivityStepID.finalizeCardLibrary, title: "Finalize library"),
      ]
    case .refreshCardValues:
      priceHistorySteps(checkIsRunning: true)
    }
  }

  static func finishedLibraryActivitySteps(
    _ steps: [GrimoraLibraryActivityStep],
    state: GrimoraLibraryActivityState
  ) -> [GrimoraLibraryActivityStep] {
    steps.map { step in
      var updated = step
      switch state {
      case .succeeded:
        updated.progress = 1
        updated.state = .succeeded
      case .failed:
        if step.state == .running {
          updated.state = .failed
        }
      case .running:
        break
      }
      return updated
    }
  }

  static func applyImportProgress(
    _ progress: ImportProgress,
    manifest: BulkDataManifest?,
    operation: GrimoraLibraryActivityOperation? = nil,
    to steps: inout [GrimoraLibraryActivityStep]
  ) {
    switch progress {
    case .downloadingBulkData:
      finishStep(LibraryActivityStepID.checkCardData, in: &steps)
      updateStep(
        LibraryActivityStepID.downloadCardData,
        title: "Download card data",
        detail: manifest.map { Self.byteCountFormatter.string(fromByteCount: Int64($0.size)) },
        progress: 0.02,
        state: .running,
        in: &steps
      )
    case .downloadingBulkDataProgress(let completedBytes, let totalBytes):
      finishStep(LibraryActivityStepID.checkCardData, in: &steps)
      updateStep(
        LibraryActivityStepID.downloadCardData,
        title: "Download card data",
        detail: byteProgressDetail(completedBytes: completedBytes, totalBytes: totalBytes),
        progress: byteProgressFraction(completedBytes: completedBytes, totalBytes: totalBytes) ?? 0.02,
        state: .running,
        in: &steps
      )
    case .decodingCardData:
      finishStep(LibraryActivityStepID.checkCardData, in: &steps)
      finishStep(LibraryActivityStepID.downloadCardData, in: &steps)
      updateStep(
        LibraryActivityStepID.readCardData,
        title: "Read card data",
        detail: "Reading card data, this can take a few minutes",
        progress: nil,
        state: .running,
        in: &steps
      )
    case .storingSearchIndex(let cardCount):
      finishStep(LibraryActivityStepID.readCardData, in: &steps)
      finishStep(LibraryActivityStepID.downloadCardData, in: &steps)
      updateStep(
        LibraryActivityStepID.buildCardLibrary,
        title: "Build local library",
        detail: "Starting \(Self.integerFormatter.string(from: NSNumber(value: cardCount)) ?? "\(cardCount)") cards",
        progress: 0,
        state: .running,
        in: &steps
      )
    case .storingSearchIndexProgress(let writeProgress):
      finishStep(LibraryActivityStepID.readCardData, in: &steps)
      finishStep(LibraryActivityStepID.downloadCardData, in: &steps)
      updateStep(
        LibraryActivityStepID.buildCardLibrary,
        title: "Build local library",
        detail: cardDatabaseBuildDetail(for: writeProgress),
        progress: cardDatabaseBuildProgress(for: writeProgress),
        state: .running,
        in: &steps
      )
    case .cardDataReady:
      finishStep(LibraryActivityStepID.buildCardLibrary, in: &steps)
    case .downloadingPriceHistoryData:
      ensurePriceHistorySteps(in: &steps)
      finishStep(LibraryActivityStepID.checkPriceHistory, in: &steps)
      updateStep(
        LibraryActivityStepID.downloadPriceIdentifiers,
        title: "Download card identifiers",
        progress: 0.02,
        state: .running,
        in: &steps
      )
    case .downloadingPriceHistoryDataProgress(let file, let completedBytes, let totalBytes):
      ensurePriceHistorySteps(in: &steps)
      finishStep(LibraryActivityStepID.checkPriceHistory, in: &steps)
      let stepID: String
      let title: String
      switch file {
      case .cardIdentifiers:
        stepID = LibraryActivityStepID.downloadPriceIdentifiers
        title = "Download card identifiers"
      case .currentPrices, .prices, .fullHistoryPrices:
        finishStep(LibraryActivityStepID.downloadPriceIdentifiers, in: &steps)
        stepID = LibraryActivityStepID.downloadPrices
        title = file == .currentPrices ? "Download current prices" : "Download price history"
      }
      updateStep(
        stepID,
        title: title,
        detail: byteProgressDetail(completedBytes: completedBytes, totalBytes: totalBytes),
        progress: byteProgressFraction(completedBytes: completedBytes, totalBytes: totalBytes) ?? 0.02,
        state: .running,
        in: &steps
      )
    case .buildingPriceIDMap:
      ensurePriceHistorySteps(in: &steps)
      finishStep(LibraryActivityStepID.downloadPriceIdentifiers, in: &steps)
      finishStep(LibraryActivityStepID.downloadPrices, in: &steps)
      updateStep(
        LibraryActivityStepID.indexPriceHistory,
        title: "Index current values",
        detail: "Mapping cards",
        progress: nil,
        state: .running,
        in: &steps
      )
    case .buildingPriceIDMapProgress(let scannedBytes, let totalBytes, let mappedCards):
      ensurePriceHistorySteps(in: &steps)
      finishStep(LibraryActivityStepID.downloadPriceIdentifiers, in: &steps)
      finishStep(LibraryActivityStepID.downloadPrices, in: &steps)
      updateStep(
        LibraryActivityStepID.indexPriceHistory,
        title: "Index current values",
        detail: mappedCards > 0
          ? "\(Self.integerFormatter.string(from: NSNumber(value: mappedCards)) ?? "\(mappedCards)") mapped"
          : byteProgressDetail(completedBytes: scannedBytes, totalBytes: totalBytes),
        progress: byteProgressFraction(completedBytes: scannedBytes, totalBytes: totalBytes),
        state: .running,
        in: &steps
      )
    case .importingPriceHistory:
      ensurePriceHistorySteps(in: &steps)
      updateStep(
        LibraryActivityStepID.indexPriceHistory,
        title: "Index current values",
        detail: "Importing prices",
        progress: nil,
        state: .running,
        in: &steps
      )
    case .importingPriceHistoryProgress(let scannedBytes, let totalBytes, let importedPricePoints):
      ensurePriceHistorySteps(in: &steps)
      updateStep(
        LibraryActivityStepID.indexPriceHistory,
        title: "Index current values",
        detail: importedPricePoints > 0
          ? "\(Self.integerFormatter.string(from: NSNumber(value: importedPricePoints)) ?? "\(importedPricePoints)") prices"
          : byteProgressDetail(completedBytes: scannedBytes, totalBytes: totalBytes),
        progress: byteProgressFraction(completedBytes: scannedBytes, totalBytes: totalBytes),
        state: .running,
        in: &steps
      )
    case .priceHistoryReady(let pricePointCount):
      ensurePriceHistorySteps(in: &steps)
      updateStep(
        LibraryActivityStepID.indexPriceHistory,
        title: "Index current values",
        detail: "\(Self.integerFormatter.string(from: NSNumber(value: pricePointCount)) ?? "\(pricePointCount)") prices",
        progress: 1,
        state: .succeeded,
        in: &steps
      )
    case .downloadingImages(let completedCards, let totalCards, let failedImageCount):
      let detail =
        failedImageCount == 0
        ? "\(completedCards) of \(totalCards)"
        : "\(completedCards) of \(totalCards), \(failedImageCount) failed"
      updateStep(
        LibraryActivityStepID.downloadImages,
        title: "Download card images",
        detail: detail,
        progress: totalCards > 0 ? Double(completedCards) / Double(totalCards) : 0,
        state: completedCards >= totalCards ? .succeeded : .running,
        in: &steps
      )
    }
  }

  static func priceHistorySteps(checkIsRunning: Bool = false) -> [GrimoraLibraryActivityStep] {
    [
      step(
        id: LibraryActivityStepID.checkPriceHistory,
        title: "Check value history",
        progress: checkIsRunning ? 0.15 : 0,
        state: checkIsRunning ? .running : .pending
      ),
      step(id: LibraryActivityStepID.downloadPriceIdentifiers, title: "Download card identifiers"),
      step(id: LibraryActivityStepID.downloadPrices, title: "Download current prices"),
      step(id: LibraryActivityStepID.indexPriceHistory, title: "Index current values"),
    ]
  }

  static func ensurePriceHistorySteps(in steps: inout [GrimoraLibraryActivityStep]) {
    let missingSteps = priceHistorySteps().filter { priceStep in
      !steps.contains(where: { $0.id == priceStep.id })
    }
    guard !missingSteps.isEmpty else {
      return
    }

    let insertionIndex =
      steps.firstIndex {
        $0.id == LibraryActivityStepID.deleteCachedImages
          || $0.id == LibraryActivityStepID.finalizeCardLibrary
      } ?? steps.endIndex
    steps.insert(contentsOf: missingSteps, at: insertionIndex)
  }

  static func step(
    id: String,
    title: String,
    detail: String? = nil,
    progress: Double? = 0,
    state: GrimoraLibraryActivityStepState = .pending
  ) -> GrimoraLibraryActivityStep {
    GrimoraLibraryActivityStep(
      id: id,
      title: title,
      detail: detail,
      progress: clampedProgress(progress),
      state: state
    )
  }

  static func updateStep(
    _ id: String,
    title: String,
    detail: String? = nil,
    progress: Double?,
    state: GrimoraLibraryActivityStepState,
    in steps: inout [GrimoraLibraryActivityStep]
  ) {
    let index = indexOfStep(id, title: title, in: &steps)
    steps[index].title = title
    steps[index].detail = detail
    steps[index].progress = clampedProgress(progress)
    steps[index].state = state
  }

  static func finishStep(_ id: String, in steps: inout [GrimoraLibraryActivityStep]) {
    guard let index = steps.firstIndex(where: { $0.id == id }) else {
      return
    }
    steps[index].progress = 1
    steps[index].state = .succeeded
  }

  static func indexOfStep(
    _ id: String,
    title: String,
    in steps: inout [GrimoraLibraryActivityStep]
  ) -> Int {
    if let index = steps.firstIndex(where: { $0.id == id }) {
      return index
    }

    steps.append(step(id: id, title: title))
    return steps.index(before: steps.endIndex)
  }

  static func byteProgressFraction(completedBytes: Int64, totalBytes: Int64?) -> Double? {
    guard let totalBytes, totalBytes > 0 else {
      return nil
    }
    return Double(completedBytes) / Double(totalBytes)
  }

  static func byteProgressDetail(completedBytes: Int64, totalBytes: Int64?) -> String? {
    let completed = Self.byteCountFormatter.string(fromByteCount: completedBytes)
    guard let totalBytes, totalBytes > 0 else {
      return completedBytes > 0 ? "\(completed) downloaded" : nil
    }
    let total = Self.byteCountFormatter.string(fromByteCount: totalBytes)
    return "\(completed) of \(total)"
  }

  static func cardDatabaseBuildDetail(for progress: CardDatabaseWriteProgress) -> String {
    switch progress.phase {
    case .preparingMetadata:
      let completed = integerFormatter.string(from: NSNumber(value: progress.completedUnitCount))
        ?? "\(progress.completedUnitCount)"
      let total = integerFormatter.string(from: NSNumber(value: progress.totalUnitCount ?? 0))
        ?? "\(progress.totalUnitCount ?? 0)"
      return "Preparing search fields \(completed) of \(total) cards"
    case .preservingValueHistory:
      return "Preserving existing value history"
    case .clearingValueHistoryCache:
      if let totalUnitCount = progress.totalUnitCount {
        let completed = integerFormatter.string(from: NSNumber(value: progress.completedUnitCount))
          ?? "\(progress.completedUnitCount)"
        let total = integerFormatter.string(from: NSNumber(value: totalUnitCount))
          ?? "\(totalUnitCount)"
        return "Clearing cached values \(completed) of \(total)"
      }
      return "Checking cached value rows"
    case .resettingCachedLibrary:
      return "Resetting cached library tables"
    case .resettingSearchIndex:
      return "Resetting offline search tables"
    case .clearingExistingLibrary:
      if let totalUnitCount = progress.totalUnitCount {
        let completed = integerFormatter.string(from: NSNumber(value: progress.completedUnitCount))
          ?? "\(progress.completedUnitCount)"
        let total = integerFormatter.string(from: NSNumber(value: totalUnitCount))
          ?? "\(totalUnitCount)"
        return "Clearing old card records \(completed) of \(total)"
      }
      return "Clearing old card records"
    case .writingCards:
      let written = integerFormatter.string(from: NSNumber(value: progress.writtenCards))
        ?? "\(progress.writtenCards)"
      let total = integerFormatter.string(from: NSNumber(value: progress.totalCards))
        ?? "\(progress.totalCards)"
      return "Writing \(written) of \(total) cards"
    case .restoringValueHistory:
      return "Restoring value history"
    }
  }

  static func cardDatabaseBuildProgress(for progress: CardDatabaseWriteProgress) -> Double? {
    switch progress.phase {
    case .preparingMetadata, .writingCards:
      return progress.progressFraction
    case .clearingValueHistoryCache:
      return progress.progressFraction
    case .resettingCachedLibrary:
      return progress.progressFraction
    case .clearingExistingLibrary:
      return progress.progressFraction
    case .preservingValueHistory, .resettingSearchIndex, .restoringValueHistory:
      return nil
    }
  }

  static func clampedProgress(_ progress: Double?) -> Double? {
    guard let progress else {
      return nil
    }
    return min(max(progress, 0), 1)
  }
}
