import Foundation
import GrimoraCore
import Observation

struct VisibleImageRequestKey: Hashable, Sendable {
  var cardID: CardRecord.ID
  var quality: CardImageQuality
}

enum VisibleImageRequestPhase: Equatable, Sendable {
  case queued
  case inFlight
  case retrying
  case failed
}

struct VisibleImageRequestState: Equatable, Sendable {
  var phase: VisibleImageRequestPhase
  var attempt: Int
}

@Observable
@MainActor
public final class GrimoraAppModel {
  public var searchText: String = ""
  public internal(set) var submittedSearchText: String = ""

  public var sortMode: SortMode = .name {
    didSet {
      if !isUpdatingCurrentSort {
        reloadSearch()
      }
    }
  }

  public var sortDirection: SearchSortDirection = .ascending {
    didSet {
      if !isUpdatingCurrentSort {
        reloadSearch()
      }
    }
  }

  public var printingDisplayMode: PrintingDisplayMode = .preferred {
    didSet { reloadSearch() }
  }

  public internal(set) var cards: [CardRecord] = []
  public internal(set) var searchResultTotal = 0
  public internal(set) var selectedCardPrintings: [CardRecord] = []
  public internal(set) var selectedCardValueGuide: CardValueGuide?
  public internal(set) var valueHistoryBackgroundActivity: ValueHistoryBackgroundActivity?
  public internal(set) var valueExchangeRate: CurrencyExchangeRate?
  public var selectedCard: CardRecord? {
    didSet {
      if !isUpdatingSelectedCardSource {
        selectedCardCollectionEntryID = nil
      }
      guard selectedCard?.id != oldValue?.id else {
        return
      }
      selectedCardValueGuide = nil
      if let selectedCard, selectedCardPrintings.contains(where: { $0.id == selectedCard.id }) {
        return
      }
      selectedCardPrintings = selectedCard.map { [$0] } ?? []
    }
  }
  public internal(set) var unsupportedSearchMessage: String?
  public internal(set) var statusMessage: String = ""
  /// A duplicate add that the Commander singleton guard refused, held so the UI can offer an
  /// "Add Anyway" confirmation. Set by the add methods; cleared when the user confirms or cancels.
  public internal(set) var pendingDuplicateAdd: PendingDuplicateAdd?
  /// A one-time offer to auto-organize a freshly-opened, uncategorized Commander deck by card
  /// type. Set when such a deck loads; cleared when the user accepts or dismisses (either way
  /// the deck is remembered so the offer never reappears).
  public internal(set) var pendingCommanderAutoCategorize: PendingCommanderAutoCategorize?
  public internal(set) var libraryActivity: GrimoraLibraryActivity?
  /// Bumped whenever something (e.g. the Settings "Replay Tutorial" button) asks
  /// to replay onboarding; `GrimoraRootView` observes it and restarts the tour.
  /// Routed through the model because the macOS Settings scene can only reach
  /// `GrimoraAppModel`, not the root view's private onboarding object.
  public internal(set) var onboardingReplayRequestID = 0
  public internal(set) var updateManifest: BulkDataManifest?
  public internal(set) var isWorking = false
  public internal(set) var canLoadMoreCards = false
  public internal(set) var isLoadingMoreCards = false
  public internal(set) var isSearchingCards = false
  public internal(set) var isCreatingListFromSearch = false
  public internal(set) var libraryState: LibraryReadinessState = .missing
  public internal(set) var defaultSearchConfiguration =
    GrimoraDefaultSearchConfiguration()
  public internal(set) var searchHistory: [String] = []
  public internal(set) var hiddenSearchTerms: [SearchRefinement] = []
  public internal(set) var cardCollections: [CardCollectionRecord] = []
  public internal(set) var cardCollectionOverviewItems: [CardCollectionOverviewItem] = []
  /// Card IDs currently in the Favourites list, refreshed whenever the lists reload.
  /// Backs the star toggle surfaced on search result cards.
  public internal(set) var favouriteCardIDs: Set<CardRecord.ID> = []
  public internal(set) var sidebarSelection: GrimoraSidebarSelection = .search
  public internal(set) var selectedCollectionID: CardCollectionRecord.ID?
  public internal(set) var selectedCollectionCategories: [CardCollectionCategoryRecord] = []
  public internal(set) var selectedCollectionEntries: [CardCollectionEntryRecord] = []
  /// The selected collection's entries grouped into display sections, built off the main
  /// thread by the list loader so the detail view doesn't regroup+sort on every body pass.
  /// Reflects the full list; the detail view rebuilds in-body only for the small
  /// collection-search result set and the Scanned newest-first reversal.
  var selectedCollectionSections: [CardCollectionEntrySection] = []
  public internal(set) var selectedCollectionSearchText = ""
  public internal(set) var searchedSelectedListEntries: [CardCollectionEntryRecord]?
  public internal(set) var selectedCollectionSearchUnsupportedMessage: String?
  public internal(set) var dashboardSearchText = ""
  public internal(set) var dashboardListMatchIDs: Set<CardCollectionRecord.ID>?
  public internal(set) var dashboardListMatches: [CardCollectionRecord.ID: CrossListSearchMatch] = [:]
  public internal(set) var dashboardSearchUnsupportedMessage: String?
  public internal(set) var selectedCollectionRulesetWarnings: [CardCollectionRulesetWarning] = []
  /// Where the selected collection's detail state is in its load lifecycle. The detail
  /// view renders a skeleton while this is `.loading(selectedCollectionID)` so navigation
  /// swaps instantly and the DB read happens off the main thread.
  public internal(set) var listLoadPhase: ListLoadPhase = .idle
  public internal(set) var selectedCardCollectionEntryID: CardCollectionEntryRecord.ID?
  /// The finish the user has chosen per printing during the *current* detail session when
  /// there is no backing collection entry (e.g. browsing from search). Per printing, so each
  /// version remembers its own finish while swiping; cleared when a different card is opened or
  /// the detail view is closed. Only non-default finishes are stored. Collection entries persist
  /// their finish via `CardCollectionEntryRecord.selectedFinish`.
  internal var sessionSelectedFinish: [CardRecord.ID: CardValueFinish] = [:]
  /// The collection entry currently under the pointer on macOS, tracked so the "F" hover-to-foil
  /// shortcut and the "Toggle Foil" command know which owned card to flip. Set by collection grid
  /// tiles on hover-in; cleared on hover-out. `nil` when the pointer isn't over an owned card.
  public internal(set) var hoveredFoilEntryID: CardCollectionEntryRecord.ID?
  /// A brief, auto-dismissing notice for the foil shortcut (e.g. "No foil available" when a card
  /// can't be foil). Rendered as a transient toast on macOS and cleared by the UI.
  public internal(set) var foilCommandNotice: GrimoraFoilCommandNotice?
  public internal(set) var canUndoListAction = false
  public internal(set) var cloudSyncMode: GrimoraCloudSyncMode = .undecided
  public internal(set) var cloudSyncStatus: CloudSyncStatus = .disabled
  public internal(set) var cloudSyncRecoverySnapshots: [CloudSyncRecoverySnapshot] = []
  public internal(set) var cloudSyncPendingChangeCount = 0
  public internal(set) var cloudSyncLastDownloadAt: Date?
  public internal(set) var cloudSyncLastUploadAt: Date?
  /// Drives the manual-sync progress affordance (e.g. the macOS toolbar spinner). Set for the
  /// full duration of a user-triggered `syncWithCloudNow()` so the UI reflects the in-flight
  /// push + fetch even though the status machine may briefly settle on `.ready` between steps.
  public internal(set) var isPerformingCloudSync = false
  /// A non-blocking notice shown when an incoming iCloud change overwrote local data,
  /// offering a one-tap Undo. Set to `nil` once dismissed or acted on.
  public internal(set) var cloudSyncMergeNotice: CloudSyncMergeNotice?
  public internal(set) var managedCatalogMigrationStatus:
    ManagedCatalogMigrationStatus?

  public var hasLibrary: Bool {
    libraryState == .ready
  }

  public var selectedCollection: CardCollectionRecord? {
    guard let selectedCollectionID else {
      return nil
    }

    return cardCollections.first { $0.id == selectedCollectionID }
  }

  /// Total cards in the selected list, derived from the freshly-loaded entries rather than
  /// the denormalized `CardCollectionRecord.entryCount`. The cached count can lag behind the
  /// entries table (e.g. after an out-of-band cloud-sync apply), so the detail header reads
  /// this to stay consistent with the cards actually on screen.
  public var selectedCollectionEntryTotal: Int {
    selectedCollectionEntries.reduce(0) { $0 + $1.quantity }
  }

  public var favouritesList: CardCollectionRecord? {
    cardCollections.first { isProtectedFavouritesList($0) }
  }

  /// The built-in "system" lists, in their pinned-to-top order: Favourites, then
  /// Scanned (when it exists). These lead the sidebar as a headerless group and
  /// are excluded from the pinned/unpinned user sections below.
  public var systemCardCollections: [CardCollectionRecord] {
    [favouritesList, scannedList].compactMap { $0 }
  }

  public var pinnedCardCollections: [CardCollectionRecord] {
    sortedCardCollections(cardCollections.filter { $0.isPinned && !isSystemList($0) })
  }

  public var unpinnedCardCollections: [CardCollectionRecord] {
    sortedCardCollections(cardCollections.filter { !$0.isPinned && !isSystemList($0) })
  }

  func sortedCardCollections(_ lists: [CardCollectionRecord]) -> [CardCollectionRecord] {
    lists.sorted { lhs, rhs in
      if lhs.position != rhs.position {
        return lhs.position < rhs.position
      }
      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
      }
      return lhs.id < rhs.id
    }
  }

  public var isDefaultSearchActive: Bool {
    submittedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && defaultSearchConfiguration.isEnabled
  }

  public var activeDefaultSearchText: String? {
    guard isDefaultSearchActive else {
      return nil
    }

    return defaultSearchConfiguration.normalizedText
  }

  public var alwaysIncludedSearchText: String {
    defaultSearchConfiguration.normalizedAlwaysIncludedText
  }

  public var activeDefaultSearchSortDescription: String {
    GrimoraSearchPreferences.sortDescription(
      sortMode: isDefaultSearchActive ? sortMode : defaultSearchConfiguration.sortMode,
      sortDirection: isDefaultSearchActive ? sortDirection : defaultSearchConfiguration.sortDirection
    )
  }

  public var canCreateListFromCurrentSearch: Bool {
    hasLibrary
      && unsupportedSearchMessage == nil
      && searchResultTotal > 0
      && !isSearchingCards
      && !isLoadingMoreCards
      && !isCreatingListFromSearch
  }

  public var canClearSearch: Bool {
    !searchText.isEmpty || !submittedSearchText.isEmpty
  }

  public var hasUnsubmittedSearchText: Bool {
    GrimoraSearchHistoryStore.normalizedQuery(searchText)
      != GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText)
  }

  public var visibleSearchHistory: [String] {
    searchHistory
  }

  public var hasLocalCardData: Bool {
    (try? database.cardCount()) ?? 0 > 0
  }

  public var usesManagedCatalog: Bool {
    database.usesExternalCatalog || managedCatalogMigrationService != nil
  }

  let database: CardDatabase
  let updateService: LibraryUpdateService
  let importer: LibraryImporter
  let imageCache: CardImageCache
  let imageStore: ImageStore
  let archidektDeckClient: ArchidektDeckClient
  let imageDownloadCoordinator: CardImageDownloadCoordinator
  let previewImageWarmer: PreviewImageWarmer
  let temporaryDirectory: URL
  let valueHistoryBackgroundDirectory: URL
  let autoUpdateChecksEnabled: Bool
  let searchHistoryStore: GrimoraSearchHistoryStore
  let hiddenSearchTermsStore: HiddenSearchTermsStore
  let imageDownloadConfiguration: GrimoraImageDownloadConfiguration
  let searchPerformance: GrimoraSearchPerformanceConfiguration
  let cloudSyncCoordinator: CloudSyncCoordinator
  let canOfferInitialCloudSync: Bool
  let currencyExchangeRateClient: any CurrencyExchangeRateClient
  let managedCatalogMigrationService: ManagedCatalogMigrationService?
  let cloudSyncDeviceID: String
  let cloudSyncDeviceName: String
  var cloudSyncSearchSettingsUpdatedAt: Date
  var searchTask: Task<Void, Never>?
  var searchDebounceTask: Task<Void, Never>?
  var listSearchTask: Task<Void, Never>?
  var nextPagePrefetchTask: Task<Void, Never>?
  var searchHistoryRecordTask: Task<Void, Never>?
  var cloudSyncTask: Task<Void, Never>?
  var cloudSyncMonitorTask: Task<Void, Never>?
  var cloudSyncPushTask: Task<Void, Never>?
  var didApplyCloudSyncTestActions = false
  /// Tracks whether the first launch sync (initial download / combine) has finished, so
  /// the "Updated from your other device" notice only appears for later incoming changes.
  var hasCompletedInitialCloudSync = false
  var valueHistoryRefreshTask: Task<Void, Never>?
  var valueHistoryBackgroundTask: Task<Void, Never>?
  var libraryActivityDismissTask: Task<Void, Never>?
  var libraryActivityHeartbeatTask: Task<Void, Never>?
  var managedCatalogMigrationTask: Task<Void, Never>?
  var searchGeneration: UInt64 = 0
  var currentSearchCacheKey: SearchResultCacheKey?
  var isUpdatingCurrentSort = false
  var isUpdatingSelectedCardSource = false
  var isApplyingCloudSyncState = false
  var searchResultCache: SearchResultCache
  var searchPageCache: SearchPageCache
  var searchVisibleImageWindowTracker = SearchVisibleImageWindowTracker()
  var listVisibleImageWindowTracker = SearchVisibleImageWindowTracker()
  var visibleImageRequestStates: [VisibleImageRequestKey: VisibleImageRequestState] = [:]
  let visiblePreviewLoadingStore = VisiblePreviewLoadingStore()
  var searchVisibleImageRequestKeys: Set<VisibleImageRequestKey> = []
  var listVisibleImageRequestKeys: Set<VisibleImageRequestKey> = []
  var searchVisibleImageRequestWindows: [Set<VisibleImageRequestKey>] = []
  var listVisibleImageRequestWindows: [Set<VisibleImageRequestKey>] = []
  var visibleImageRequestSource: VisibleImageRequestSource?
  var visibleImageDownloadGeneration = 0
  var visibleImageRetryTasks: [VisibleImageRequestKey: Task<Void, Never>] = [:]
  var searchHistoryImageWarmTask: Task<Void, Never>?
  var listUndoStack: [CardCollectionUndoState] = []
  /// Generation token + in-flight task for asynchronous selected-list loads. Mirrors the
  /// search path's `searchGeneration`/`searchTask`: every load bumps the generation and
  /// cancels the prior task so a stale background load can never publish over a newer one.
  var listLoadGeneration: UInt64 = 0
  var listLoadTask: Task<Void, Never>?

  public init(
    environment: GrimoraEnvironment,
    initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration =
      GrimoraDefaultSearchConfiguration(),
    initialCloudSyncMode: GrimoraCloudSyncMode = .undecided,
    cloudSyncDeviceID: String? = nil,
    cloudSyncDeviceName: String = "Grimora Device",
    initialCloudSyncSearchSettingsUpdatedAt: Date? = nil
  ) {
    self.database = environment.database
    self.updateService = environment.updateService
    self.importer = environment.importer
    self.imageCache = environment.imageCache
    self.imageStore = environment.imageStore
    self.archidektDeckClient = environment.archidektDeckClient
    self.imageDownloadCoordinator = CardImageDownloadCoordinator(
      imageCache: environment.imageCache,
      visibleLimit: environment.imageDownloadConfiguration.visibleConcurrency,
      detailLimit: environment.imageDownloadConfiguration.detailConcurrency,
      visibleAttemptTimeoutNanoseconds:
        environment.imageDownloadConfiguration.visibleAttemptTimeoutNanoseconds,
      visiblePendingLimit: environment.imageDownloadConfiguration.visiblePendingQueueLimit
    )
    self.previewImageWarmer = PreviewImageWarmer(
      historyWarmDelayNanoseconds:
        environment.imageDownloadConfiguration.historyWarmDelayNanoseconds
    )
    self.temporaryDirectory = environment.temporaryDirectory
    self.valueHistoryBackgroundDirectory = environment.valueHistoryBackgroundDirectory
    self.autoUpdateChecksEnabled = environment.autoUpdateChecksEnabled
    self.searchHistoryStore = environment.searchHistoryStore
    self.hiddenSearchTermsStore = environment.hiddenSearchTermsStore
    self.imageDownloadConfiguration = environment.imageDownloadConfiguration
    self.searchPerformance = environment.searchPerformanceConfiguration
    self.cloudSyncCoordinator = environment.cloudSyncCoordinator
    self.canOfferInitialCloudSync = environment.canOfferInitialCloudSync
    self.currencyExchangeRateClient = environment.currencyExchangeRateClient
    self.managedCatalogMigrationService = environment.managedCatalogMigrationService
    self.managedCatalogMigrationStatus = environment.initialManagedCatalogMigrationStatus
    self.cloudSyncDeviceID = cloudSyncDeviceID ?? GrimoraCloudSyncPreferences.deviceID()
    self.cloudSyncDeviceName = cloudSyncDeviceName
    self.cloudSyncSearchSettingsUpdatedAt =
      initialCloudSyncSearchSettingsUpdatedAt ?? GrimoraCloudSyncPreferences.searchSettingsUpdatedAt()
    self.cloudSyncMode = initialCloudSyncMode
    self.cloudSyncStatus = initialCloudSyncMode == .enabled ? .preparing : .disabled
    self.searchResultCache = SearchResultCache(
      capacity: environment.searchPerformanceConfiguration.firstPageCacheCapacity
    )
    self.searchPageCache = SearchPageCache(
      capacity: environment.searchPerformanceConfiguration.pageCacheCapacity
    )
    LocalCardImageLoader.shared.configure(
      countLimit: environment.imageDownloadConfiguration.decodedPreviewCacheCountLimit,
      totalCostLimit: environment.imageDownloadConfiguration.decodedPreviewCacheCostLimitBytes,
      preloadConcurrency: environment.imageDownloadConfiguration.previewDecodeConcurrency
    )

    let normalizedDefaultSearchConfiguration =
      Self.normalizedDefaultSearchConfiguration(initialDefaultSearchConfiguration)
    defaultSearchConfiguration = normalizedDefaultSearchConfiguration
    if normalizedDefaultSearchConfiguration.isEnabled {
      sortMode = normalizedDefaultSearchConfiguration.sortMode
      sortDirection = normalizedDefaultSearchConfiguration.sortDirection
    }

    searchHistory = environment.searchHistoryStore.load()
    hiddenSearchTerms = environment.hiddenSearchTermsStore.load()
    reloadCardCollections()
    reloadCloudSyncRecoverySnapshots()
    reloadCloudSyncDiagnostics()
    refreshLibraryState()

    if hasLibrary {
      reloadSearch()
      scheduleSearchHistoryPreviewWarm()
      startValueHistoryBackgroundImportIfNeeded()
    }

    let managedCatalogMigrationPreviouslyFailed: Bool
    if case .failed? = managedCatalogMigrationStatus {
      managedCatalogMigrationPreviouslyFailed = true
    } else {
      managedCatalogMigrationPreviouslyFailed = false
    }

    if managedCatalogMigrationService != nil {
      if !managedCatalogMigrationPreviouslyFailed {
        Task {
          await self.stageManagedCatalogMigration(manual: false)
        }
      }
    } else if autoUpdateChecksEnabled {
      Task {
        await self.checkForUpdates(manual: false)
        if self.usesManagedCatalog,
          self.hasLocalCardData,
          self.updateManifest != nil
        {
          await self.importAvailableUpdate(automatic: true)
        }
      }
    }

    if initialCloudSyncMode == .enabled {
      Task { await startCloudSync() }
    }
  }

  public static func configuredForCurrentPreferences(
    environment: GrimoraEnvironment
  ) -> GrimoraAppModel {
    GrimoraAppModel(
      environment: environment,
      initialDefaultSearchConfiguration: GrimoraSearchPreferences.configuration(),
      initialCloudSyncMode: GrimoraCloudSyncPreferences.resolvedMode(),
      cloudSyncDeviceName: GrimoraDeviceLabel.current
    )
  }
}
