import Foundation
import GrimoraCore

extension GrimoraAppModel {
  public func toggleFilter(_ filter: FilterPreset) {
    if activeFilters.contains(filter) {
      activeFilters.remove(filter)
    } else {
      activeFilters.insert(filter)
    }
  }

  public func setSearchInputMode(_ mode: SearchInputMode) {
    searchInputMode = mode
  }

  public func togglePlainTextSearchMode() {
    setSearchInputMode(searchInputMode == .plainText ? .scryfall : .plainText)
  }

  public func setSearchDraft(_ text: String) {
    let normalized = GrimoraSearchHistoryStore.normalizedQuery(text)
    if normalized.isEmpty, canClearSearch {
      clearSearch()
      return
    }

    searchText = text
    submitScryfallDraftSearchIfNeeded(normalized)
  }

  private func submitScryfallDraftSearchIfNeeded(_ normalizedQuery: String) {
    guard searchInputMode == .scryfall, !normalizedQuery.isEmpty else {
      return
    }

    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil
    submittedSearchText = normalizedQuery
    reloadSearch(debounce: true)
  }

  public func clearSearch() {
    guard canClearSearch else {
      return
    }

    plainTextSearchTask?.cancel()
    isTranslatingSearch = false
    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil
    submittedSearchText = ""
    searchText = ""
    reloadSearch()
  }

  public func cancelSearchEditing() {
    let submitted = GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText)
    guard GrimoraSearchHistoryStore.normalizedQuery(searchText) != submitted else {
      return
    }
    searchText = submitted
    if searchInputMode == .plainText, submitted.isEmpty {
      generatedSearchQuery = nil
      plainTextSearchStatusMessage = nil
      plainTextSearchErrorMessage = nil
    }
  }

  public func clearSearchHistory() {
    searchHistoryRecordTask?.cancel()
    searchHistoryImageWarmTask?.cancel()
    if searchInputMode == .plainText {
      plainTextSearchHistory = []
      plainTextSearchHistoryStore.clear()
    } else {
      searchHistory = []
      searchHistoryStore.clear()
      Task { await previewImageWarmer.cancelHistory() }
    }
  }

  public func applySearchInputModePreference(_ mode: SearchInputMode) {
    setSearchInputMode(mode)
    if cloudSyncMode == .enabled {
      try? database.recordLocalSyncSnapshotChange(reason: "search-input-mode")
      pushCloudSyncChangesIfNeeded()
    }
  }

  public func applySearchPreferences(_ configuration: GrimoraDefaultSearchConfiguration) {
    let normalizedConfiguration = Self.normalizedDefaultSearchConfiguration(configuration)
    guard normalizedConfiguration != defaultSearchConfiguration else {
      return
    }

    let searchTextIsEmpty = submittedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    defaultSearchConfiguration = normalizedConfiguration
    if searchTextIsEmpty {
      if normalizedConfiguration.isEnabled {
        setCurrentSort(
          sortMode: normalizedConfiguration.sortMode,
          sortDirection: normalizedConfiguration.sortDirection
        )
      }
    }
    reloadSearch()
    if cloudSyncMode == .enabled {
      try? database.recordLocalSyncSnapshotChange(reason: "search-preferences")
      pushCloudSyncChangesIfNeeded()
    }
  }

  public func submitSearch() async {
    guard searchInputMode == .plainText else {
      let query = GrimoraSearchHistoryStore.normalizedQuery(searchText)
      submittedSearchText = query
      if searchText != query {
        searchText = query
      }
      generatedSearchQuery = nil
      plainTextSearchStatusMessage = nil
      plainTextSearchErrorMessage = nil
      reloadSearch()
      return
    }

    let prompt = GrimoraSearchHistoryStore.normalizedQuery(searchText)
    guard !prompt.isEmpty else {
      submittedSearchText = ""
      generatedSearchQuery = nil
      plainTextSearchStatusMessage = nil
      plainTextSearchErrorMessage = nil
      reloadSearch()
      return
    }

    guard plainTextSearchTranspiler.availability.isAvailable else {
      plainTextSearchErrorMessage =
        plainTextSearchTranspiler.availability.message ?? "Plain-text search is unavailable."
      return
    }

    submittedSearchText = prompt
    if searchText != prompt {
      searchText = prompt
    }
    searchGeneration += 1
    let generation = searchGeneration
    searchDebounceTask?.cancel()
    searchTask?.cancel()
    plainTextSearchTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchHistoryRecordTask?.cancel()
    currentSearchCacheKey = nil
    searchVisibleImageWindowTracker.reset()
    resetSearchVisibleImageRequests()
    canLoadMoreCards = false
    isLoadingMoreCards = false
    isSearchingCards = false
    isTranslatingSearch = true
    unsupportedSearchMessage = nil
    plainTextSearchStatusMessage = "Translating search"
    plainTextSearchErrorMessage = nil

    let transpiler = plainTextSearchTranspiler
    let task = Task { [weak self, prompt, generation, transpiler] in
      let result = await Task.detached(priority: .userInitiated) {
        await Self.validatedPlainTextSearch(prompt: prompt, transpiler: transpiler)
      }.value

      guard !Task.isCancelled else {
        return
      }

      self?.publishPlainTextSearchTranslation(result, prompt: prompt, generation: generation)
    }
    plainTextSearchTask = task
    await task.value
  }

  public func startInitialSetup() async {
    guard !isWorking, !hasLibrary else {
      return
    }

    isWorking = true
    libraryState = .initializing
    updateManifest = nil
    cards = []
    searchResultTotal = 0
    unsupportedSearchMessage = nil
    isTranslatingSearch = false
    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil
    searchDebounceTask?.cancel()
    plainTextSearchTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchHistoryRecordTask?.cancel()
    isTranslatingSearch = false
    searchResultCache.removeAll()
    searchPageCache.removeAll()
    currentSearchCacheKey = nil
    searchVisibleImageWindowTracker.reset()
    resetSearchVisibleImageRequests()
    statusMessage = "Checking Scryfall bulk data..."
    beginLibraryActivity(operation: .setupLibrary, title: "Setting Up Library", message: statusMessage)
    defer { isWorking = false }

    do {
      let manifest: BulkDataManifest
      if cloudSyncMode == .enabled,
        let requiredManifest = requiredCloudLibraryIdentity?.manifest
      {
        manifest = requiredManifest
      } else {
        let result = try await updateService.checkForUpdates(manual: true)
        manifest = manifestForInitialSetup(from: result)
      }
      let summary = try await updateService.downloadAndImport(
        manifest: manifest,
        temporaryDirectory: temporaryDirectory,
        importer: importer,
        imagePolicy: .reuseExistingImagesWithoutDownloading
      ) { [weak self] progress in
        await MainActor.run {
          self?.handleImportProgress(progress, manifest: manifest)
        }
      }
      updateManifest = nil
      refreshLibraryState()
      searchResultCache.removeAll()
      searchPageCache.removeAll()
      currentSearchCacheKey = nil
      searchVisibleImageWindowTracker.reset()
      resetSearchVisibleImageRequests()

      guard hasLibrary else {
        libraryState = .failed(
          "The card data imported, but the library could not be verified. Try again to finish setup."
        )
        statusMessage = "Setup could not verify the local card data."
        finishLibraryActivity(message: statusMessage, state: .failed)
        cards = []
        searchResultTotal = 0
        return
      }

      statusMessage =
        "Imported \(summary.importedCards) cards. Images load as you browse."
        + priceHistoryStatusSuffix(for: summary.priceHistoryStatus)
      finishLibraryActivityForImportSummary(summary, message: statusMessage)
      reloadCardLists()
      reloadSearch()
      startValueHistoryBackgroundImportIfNeeded()
      if cloudSyncMode == .enabled {
        await startCloudSync()
      }
    } catch {
      libraryState = .failed("Setup failed. Check your connection and disk space, then try again.")
      statusMessage = "Setup failed. Check your connection and disk space, then try again."
      finishLibraryActivity(message: statusMessage, state: .failed)
      cards = []
      searchResultTotal = 0
    }
  }

  public func checkForUpdates(manual: Bool = true) async {
    guard !isWorking else {
      return
    }

    isWorking = true
    if manual {
      statusMessage = "Checking Scryfall bulk data..."
    }
    defer { isWorking = false }

    do {
      let result = try await updateService.checkForUpdates(manual: manual)
      switch result {
      case .skipped:
        break
      case .noLocalLibrary(let manifest):
        updateManifest = manifest
        statusMessage = "Ready to import \(manifest.name) card data."
      case .upToDate:
        updateManifest = nil
        statusMessage = "Library is current."
      case .updateAvailable(let manifest):
        updateManifest = manifest
        statusMessage = "New Scryfall data is available."
      }
    } catch {
      statusMessage = "Update check failed. Check your connection and try again."
    }
  }

  public func importAvailableUpdate() async {
    guard let manifest = updateManifest, !isWorking else {
      return
    }

    isWorking = true
    searchDebounceTask?.cancel()
    plainTextSearchTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchHistoryRecordTask?.cancel()
    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil
    searchResultCache.removeAll()
    searchPageCache.removeAll()
    currentSearchCacheKey = nil
    searchVisibleImageWindowTracker.reset()
    resetSearchVisibleImageRequests()
    beginLibraryActivity(
      operation: .importCardDatabase,
      title: "Importing Card Database",
      message: "Preparing library import..."
    )
    defer { isWorking = false }

    do {
      let summary = try await updateService.downloadAndImport(
        manifest: manifest,
        temporaryDirectory: temporaryDirectory,
        importer: importer,
        imagePolicy: .reuseExistingImagesWithoutDownloading
      ) { [weak self] progress in
        await MainActor.run {
          self?.handleImportProgress(progress, manifest: manifest)
        }
      }
      updateManifest = nil
      statusMessage =
        "Imported \(summary.importedCards) cards. Images load as you browse."
        + priceHistoryStatusSuffix(for: summary.priceHistoryStatus)
      finishLibraryActivityForImportSummary(summary, message: statusMessage)
      refreshLibraryState()
      searchResultCache.removeAll()
      searchPageCache.removeAll()
      currentSearchCacheKey = nil
      searchVisibleImageWindowTracker.reset()
      resetSearchVisibleImageRequests()
      reloadCardLists()
      reloadSearch()
      pushCloudSyncChangesIfNeeded()
      startValueHistoryBackgroundImportIfNeeded()
    } catch {
      statusMessage = "Import failed. Check your connection and disk space, then try again."
      finishLibraryActivity(message: statusMessage, state: .failed)
    }
  }

  public func refreshCardDatabase() async {
    await importLatestCardDatabase(
      activityOperation: .refreshCardDatabase,
      activityTitle: "Refreshing Card Database",
      imagePolicy: .reuseExistingImagesWithoutDownloading,
      clearsImageCacheAfterImport: false,
      successMessage: { summary in
        "Refreshed \(self.formatted(summary.importedCards)) cards. Images load as you browse."
          + self.priceHistoryStatusSuffix(for: summary.priceHistoryStatus)
      },
      failureMessage: "Refresh failed. Check your connection and disk space, then try again."
    )
  }

  public func refreshCardValues() async {
    guard !isWorking else {
      return
    }

    guard hasLibrary else {
      statusMessage = "Set up the card database before refreshing values."
      return
    }

    isWorking = true
    statusMessage = "Checking MTGJSON value history..."
    beginLibraryActivity(operation: .refreshCardValues, title: "Refreshing Card Values", message: statusMessage)
    defer { isWorking = false }

    let status = await updateService.refreshPriceHistory(
      temporaryDirectory: temporaryDirectory
    ) { [weak self] progress in
      await MainActor.run {
        self?.handlePriceHistoryProgress(progress)
      }
    }

    statusMessage = priceHistoryStatusMessage(for: status)
    finishLibraryActivityForPriceHistory(status)
    if let selectedCard {
      await loadValueGuide(for: selectedCard)
    }
    startValueHistoryBackgroundImportIfNeeded()
  }

  public func deleteCachedImages() async {
    guard !isWorking else {
      return
    }

    isWorking = true
    prepareForLibraryMaintenance()
    statusMessage = "Deleting cached card images..."
    defer { isWorking = false }

    do {
      try imageStore.removeAllImages()
      try database.clearStoredImagePaths()
      LocalCardImageLoader.shared.clear()
      updateManifest = nil
      refreshLibraryState()
      reloadCardLists()
      if hasLibrary {
        reloadSearch()
      } else {
        cards = []
        searchResultTotal = 0
      }
      statusMessage = "Deleted cached card images. Images load again as you browse."
    } catch {
      statusMessage = "Could not delete cached images. Check disk permissions and try again."
    }
  }

  public func deleteAndRefreshCardDatabase() async {
    await importLatestCardDatabase(
      activityOperation: .deleteAndRefreshDatabase,
      activityTitle: "Deleting and Refreshing Database",
      imagePolicy: .skipImageDownloads,
      clearsImageCacheAfterImport: true,
      successMessage: { summary in
        "Deleted cached images and refreshed \(self.formatted(summary.importedCards)) cards. Images load as you browse."
          + self.priceHistoryStatusSuffix(for: summary.priceHistoryStatus)
      },
      failureMessage: "Delete and refresh failed. Existing lists were preserved."
    )
  }

  private func importLatestCardDatabase(
    activityOperation: GrimoraLibraryActivityOperation,
    activityTitle: String,
    imagePolicy: ImageImportPolicy,
    clearsImageCacheAfterImport: Bool,
    successMessage: (ImportSummary) -> String,
    failureMessage: String
  ) async {
    guard !isWorking else {
      return
    }

    isWorking = true
    prepareForLibraryMaintenance()
    statusMessage = "Checking Scryfall bulk data..."
    beginLibraryActivity(operation: activityOperation, title: activityTitle, message: statusMessage)
    defer { isWorking = false }

    do {
      let result = try await updateService.checkForUpdates(manual: true)
      let manifest = manifestForInitialSetup(from: result)
      let summary = try await updateService.downloadAndImport(
        manifest: manifest,
        temporaryDirectory: temporaryDirectory,
        importer: importer,
        imagePolicy: imagePolicy
      ) { [weak self] progress in
        await MainActor.run {
          self?.handleImportProgress(progress, manifest: manifest)
        }
      }

      if clearsImageCacheAfterImport {
        try imageStore.removeAllImages()
        LocalCardImageLoader.shared.clear()
      }

      updateManifest = nil
      refreshLibraryState()
      searchResultCache.removeAll()
      searchPageCache.removeAll()
      currentSearchCacheKey = nil
      searchVisibleImageWindowTracker.reset()
      resetSearchVisibleImageRequests()
      reloadCardLists()
      if hasLibrary {
        reloadSearch()
      } else {
        cards = []
        searchResultTotal = 0
      }
      statusMessage = successMessage(summary)
      finishLibraryActivityForImportSummary(summary, message: statusMessage)
      pushCloudSyncChangesIfNeeded()
      startValueHistoryBackgroundImportIfNeeded()
    } catch {
      refreshLibraryState()
      statusMessage = failureMessage
      finishLibraryActivity(message: statusMessage, state: .failed)
    }
  }

  func importSpecificCardDatabase(
    manifest: BulkDataManifest,
    activityOperation: GrimoraLibraryActivityOperation = .updateSyncedDatabase,
    activityTitle: String = "Updating Synced Database",
    imagePolicy: ImageImportPolicy = .reuseExistingImagesWithoutDownloading,
    successMessage: (ImportSummary) -> String,
    failureMessage: String
  ) async {
    guard !isWorking else {
      return
    }

    isWorking = true
    prepareForLibraryMaintenance()
    beginLibraryActivity(operation: activityOperation, title: activityTitle, message: "Preparing library import...")
    defer { isWorking = false }

    do {
      let summary = try await updateService.downloadAndImport(
        manifest: manifest,
        temporaryDirectory: temporaryDirectory,
        importer: importer,
        imagePolicy: imagePolicy
      ) { [weak self] progress in
        await MainActor.run {
          self?.handleImportProgress(progress, manifest: manifest)
        }
      }

      updateManifest = nil
      refreshLibraryState()
      searchResultCache.removeAll()
      searchPageCache.removeAll()
      currentSearchCacheKey = nil
      searchVisibleImageWindowTracker.reset()
      resetSearchVisibleImageRequests()
      reloadCardLists()
      if hasLibrary {
        reloadSearch()
      } else {
        cards = []
        searchResultTotal = 0
      }
      statusMessage = successMessage(summary)
      finishLibraryActivityForImportSummary(summary, message: statusMessage)
      pushCloudSyncChangesIfNeeded()
      startValueHistoryBackgroundImportIfNeeded()
    } catch {
      refreshLibraryState()
      statusMessage = failureMessage
      finishLibraryActivity(message: statusMessage, state: .failed)
    }
  }

  private func prepareForLibraryMaintenance() {
    searchDebounceTask?.cancel()
    searchTask?.cancel()
    plainTextSearchTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchHistoryRecordTask?.cancel()
    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil
    unsupportedSearchMessage = nil
    isSearchingCards = false
    isLoadingMoreCards = false
    isTranslatingSearch = false
    isCreatingListFromSearch = false
    canLoadMoreCards = false
    currentSearchCacheKey = nil
    searchResultCache.removeAll()
    searchPageCache.removeAll()
    searchVisibleImageWindowTracker.reset()
    listVisibleImageWindowTracker.reset()
    resetAllVisibleImageRequests()
    closeSelectedCard()
  }

  func startValueHistoryBackgroundImportIfNeeded() {
    guard valueHistoryBackgroundTask == nil else {
      return
    }

    let updateService = updateService
    let backgroundDirectory = valueHistoryBackgroundDirectory
    let temporaryDirectory = temporaryDirectory
    valueHistoryBackgroundTask = Task { [weak self, updateService, backgroundDirectory, temporaryDirectory] in
      let status = await updateService.runPendingValueHistoryBackgroundImport(
        backgroundDirectory: backgroundDirectory,
        temporaryDirectory: temporaryDirectory
      ) { [weak self] job in
        await MainActor.run {
          self?.publishValueHistoryBackgroundJob(job)
        }
      }

      await MainActor.run {
        guard let self else {
          return
        }
        self.valueHistoryBackgroundTask = nil
        if case .imported = status, let selectedCard = self.selectedCard {
          Task { [weak self, selectedCard] in
            await self?.loadValueGuide(for: selectedCard)
          }
        }
        if status == nil || status == .skipped {
          self.valueHistoryBackgroundActivity = nil
        }
      }
    }
  }

  func publishValueHistoryBackgroundJob(_ job: ValueHistoryBackgroundJob) {
    switch job.status {
    case .pending, .running:
      valueHistoryBackgroundActivity = ValueHistoryBackgroundActivity(
        state: .running,
        title: "90-day history updating",
        message: valueHistoryBackgroundMessage(for: job),
        progress: valueHistoryBackgroundProgress(for: job)
      )
    case .failed:
      valueHistoryBackgroundActivity = ValueHistoryBackgroundActivity(
        state: .failed,
        title: "90-day history update failed",
        message: "Current value remains available. Refresh card values to retry.",
        progress: nil
      )
    case .succeeded:
      valueHistoryBackgroundActivity = nil
    }
  }

  func valueHistoryBackgroundMessage(for job: ValueHistoryBackgroundJob) -> String {
    switch job.stage {
    case .pending:
      return "Preparing history import"
    case .downloadingPrices:
      return backgroundByteProgressLabel("Downloading full history", completed: job.downloadedBytes, total: job.totalDownloadBytes)
    case .decompressingPrices:
      return "Preparing price history"
    case .mappingCards:
      if job.importedPricePoints > 0 {
        return "Mapping cards (\(formatted(job.importedPricePoints)) matched)"
      }
      return backgroundByteProgressLabel("Mapping cards", completed: job.scannedBytes, total: job.totalScanBytes)
    case .importingHistory:
      if job.importedPricePoints > 0 {
        return "Importing prices (\(formatted(job.importedPricePoints)))"
      }
      return backgroundByteProgressLabel("Importing prices", completed: job.scannedBytes, total: job.totalScanBytes)
    case .committingHistory:
      return "Committing history"
    case .completed:
      return "History updated"
    case .failed:
      return "History update failed"
    }
  }

  func valueHistoryBackgroundProgress(for job: ValueHistoryBackgroundJob) -> Double? {
    switch job.stage {
    case .downloadingPrices:
      return Self.byteProgressFraction(completedBytes: job.downloadedBytes, totalBytes: job.totalDownloadBytes)
    case .mappingCards, .importingHistory:
      return Self.byteProgressFraction(completedBytes: job.scannedBytes, totalBytes: job.totalScanBytes)
    case .committingHistory:
      return 0.95
    case .completed:
      return 1
    case .pending, .decompressingPrices, .failed:
      return nil
    }
  }

  func backgroundByteProgressLabel(_ title: String, completed: Int64, total: Int64?) -> String {
    guard let total, total > 0 else {
      return title
    }
    return "\(title) (\(Self.byteCountFormatter.string(fromByteCount: completed)) of \(Self.byteCountFormatter.string(fromByteCount: total)))"
  }

  public func reloadSearch(debounce: Bool = false) {
    guard !hasPendingPlainTextPrompt else {
      cancelSearchWorkForPendingPlainTextPrompt()
      return
    }

    searchGeneration += 1
    let generation = searchGeneration
    searchDebounceTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchTask?.cancel()
    plainTextSearchTask?.cancel()
    isTranslatingSearch = false
    currentSearchCacheKey = nil
    searchVisibleImageWindowTracker.reset()
    resetSearchVisibleImageRequests()
    canLoadMoreCards = false

    guard debounce, searchPerformance.textDebounceNanoseconds > 0 else {
      runFirstSearchPage(generation: generation)
      return
    }

    isSearchingCards = false
    isLoadingMoreCards = false
    searchDebounceTask = Task { [weak self, generation] in
      try? await Task.sleep(nanoseconds: self?.searchPerformance.textDebounceNanoseconds ?? 0)
      guard !Task.isCancelled else {
        return
      }

      self?.runFirstSearchPage(generation: generation)
    }
  }

  public func loadMoreCardsIfNeeded(afterAppearing card: CardRecord) {
    guard let index = cards.firstIndex(where: { $0.id == card.id }) else {
      return
    }

    loadMoreCardsIfNeeded(afterAppearingCardAt: index)
  }

  public func loadMoreCardsIfNeeded(afterAppearingCardAt index: Int) {
    guard hasLibrary,
      canLoadMoreCards,
      !isSearchingCards,
      !isLoadingMoreCards,
      shouldLoadMoreCards(afterAppearingCardAt: index)
    else {
      return
    }

    loadSearchPage(offset: cards.count, generation: searchGeneration)
  }

  public func selectCard(_ card: CardRecord) {
    setSelectedCard(card, listEntryID: nil)
  }

  public func selectCard(
    _ card: CardRecord,
    fromListEntryID listEntryID: CardListEntryRecord.ID
  ) {
    setSelectedCard(card, listEntryID: listEntryID)
  }

  public func closeSelectedCard() {
    setSelectedCard(nil, listEntryID: nil)
  }

  public func selectPrinting(_ printing: CardRecord) {
    guard let selectedCardListEntryID else {
      setSelectedCard(printing, listEntryID: nil)
      return
    }

    do {
      let updatedEntry = try performListMutation {
        try database.replaceCardListEntryPrint(
          id: selectedCardListEntryID,
          withCardID: printing.id
        )
      }
      reloadCardLists(selecting: selectedListID)
      setSelectedCard(updatedEntry.card ?? printing, listEntryID: updatedEntry.id)
    } catch {
      statusMessage = "List update failed."
    }
  }
}
