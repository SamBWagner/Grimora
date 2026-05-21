import Foundation
import GrimoraCore

private enum LibraryActivityStepID {
  static let checkCardData = "check-card-data"
  static let downloadCardData = "download-card-data"
  static let readCardData = "read-card-data"
  static let buildCardLibrary = "build-card-library"
  static let finalizeCardLibrary = "finalize-card-library"
  static let checkPriceHistory = "check-price-history"
  static let downloadPriceIdentifiers = "download-price-identifiers"
  static let downloadPrices = "download-prices"
  static let indexPriceHistory = "index-price-history"
  static let downloadImages = "download-images"
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
    libraryActivity = nil
  }

  func startCardDataReadHeartbeat() {
    cardDataReadHeartbeatTask?.cancel()
    let startedAt = Date()
    cardDataReadHeartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        guard !Task.isCancelled else {
          return
        }

        let elapsedSeconds = Int(Date().timeIntervalSince(startedAt).rounded(.down))
        await MainActor.run {
          self?.publishCardDataReadHeartbeat(elapsedSeconds: elapsedSeconds)
        }
      }
    }
  }

  func stopCardDataReadHeartbeat() {
    cardDataReadHeartbeatTask?.cancel()
    cardDataReadHeartbeatTask = nil
  }

  private func publishCardDataReadHeartbeat(elapsedSeconds: Int) {
    guard cardDataReadHeartbeatTask != nil,
      libraryActivity?.state == .running
    else {
      return
    }

    let message = "Reading Scryfall card data... still working after \(Self.elapsedTimeDescription(elapsedSeconds))."
    statusMessage = message
    updateLibraryActivity(message: message) { steps in
      Self.updateStep(
        LibraryActivityStepID.readCardData,
        title: "Read card data",
        detail: "Reading card data, \(Self.elapsedTimeDescription(elapsedSeconds))",
        progress: nil,
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

  private static func elapsedTimeDescription(_ seconds: Int) -> String {
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
    case .importCardDatabase, .refreshCardDatabase, .deleteAndRefreshDatabase, .updateSyncedDatabase:
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
        detail: "Writing \(Self.integerFormatter.string(from: NSNumber(value: cardCount)) ?? "\(cardCount)") cards",
        progress: nil,
        state: .running,
        in: &steps
      )
    case .cardDataReady:
      finishStep(LibraryActivityStepID.buildCardLibrary, in: &steps)
      updateStep(
        LibraryActivityStepID.finalizeCardLibrary,
        title: "Finalize library",
        detail: "Ready for offline search",
        progress: 1,
        state: .succeeded,
        in: &steps
      )
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
    for priceStep in priceHistorySteps() where !steps.contains(where: { $0.id == priceStep.id }) {
      steps.append(priceStep)
    }
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

  static func clampedProgress(_ progress: Double?) -> Double? {
    guard let progress else {
      return nil
    }
    return min(max(progress, 0), 1)
  }
}
