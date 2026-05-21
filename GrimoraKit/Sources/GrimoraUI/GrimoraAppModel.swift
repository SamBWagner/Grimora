import Foundation
import GrimoraCore

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

@MainActor
public final class GrimoraAppModel: ObservableObject {
  @Published public var searchText: String = "" {
    didSet { handleSearchTextChange(oldValue: oldValue) }
  }
  @Published public internal(set) var submittedSearchText: String = ""

  @Published public var searchInputMode: SearchInputMode = .scryfall {
    didSet { handleSearchInputModeChange(from: oldValue) }
  }

  @Published public var sortMode: SortMode = .name {
    didSet {
      if !isUpdatingCurrentSort {
        reloadSearch()
      }
    }
  }

  @Published public var sortDirection: SearchSortDirection = .ascending {
    didSet {
      if !isUpdatingCurrentSort {
        reloadSearch()
      }
    }
  }

  @Published public var activeFilters: Set<FilterPreset> = [.realCards] {
    didSet { reloadSearch() }
  }

  @Published public var printingDisplayMode: PrintingDisplayMode = .preferred {
    didSet { reloadSearch() }
  }

  @Published public internal(set) var cards: [CardRecord] = []
  @Published public internal(set) var searchResultTotal = 0
  @Published public internal(set) var selectedCardPrintings: [CardRecord] = []
  @Published public internal(set) var selectedCardValueGuide: CardValueGuide?
  @Published public internal(set) var valueHistoryBackgroundActivity: ValueHistoryBackgroundActivity?
  @Published public internal(set) var valueExchangeRate: CurrencyExchangeRate?
  @Published public var selectedCard: CardRecord? {
    didSet {
      if !isUpdatingSelectedCardSource {
        selectedCardListEntryID = nil
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
  @Published public internal(set) var unsupportedSearchMessage: String?
  @Published public internal(set) var statusMessage: String = ""
  @Published public internal(set) var libraryActivity: GrimoraLibraryActivity?
  @Published public internal(set) var updateManifest: BulkDataManifest?
  @Published public internal(set) var isWorking = false
  @Published public internal(set) var canLoadMoreCards = false
  @Published public internal(set) var isLoadingMoreCards = false
  @Published public internal(set) var isSearchingCards = false
  @Published public internal(set) var isTranslatingSearch = false
  @Published public internal(set) var isCreatingListFromSearch = false
  @Published public internal(set) var libraryState: LibraryReadinessState = .missing
  @Published public internal(set) var defaultSearchConfiguration =
    GrimoraDefaultSearchConfiguration()
  @Published public internal(set) var searchHistory: [String] = []
  @Published public internal(set) var plainTextSearchHistory: [String] = []
  @Published public internal(set) var generatedSearchQuery: String?
  @Published public internal(set) var plainTextSearchStatusMessage: String?
  @Published public internal(set) var plainTextSearchErrorMessage: String?
  @Published public internal(set) var cardLists: [CardListRecord] = []
  @Published public internal(set) var cardListOverviewItems: [CardListOverviewItem] = []
  @Published public internal(set) var sidebarSelection: GrimoraSidebarSelection = .search
  @Published public internal(set) var selectedListID: CardListRecord.ID?
  @Published public internal(set) var selectedListCategories: [CardListCategoryRecord] = []
  @Published public internal(set) var selectedListEntries: [CardListEntryRecord] = []
  @Published public internal(set) var selectedListSearchText = ""
  @Published public internal(set) var searchedSelectedListEntries: [CardListEntryRecord]?
  @Published public internal(set) var selectedListSearchUnsupportedMessage: String?
  @Published public internal(set) var selectedListRulesetWarnings: [CardListRulesetWarning] = []
  @Published public internal(set) var selectedCardListEntryID: CardListEntryRecord.ID?
  @Published public internal(set) var canUndoListAction = false
  @Published public internal(set) var cloudSyncMode: GrimoraCloudSyncMode = .undecided
  @Published public internal(set) var cloudSyncStatus: CloudSyncStatus = .disabled

  public var hasLibrary: Bool {
    libraryState == .ready
  }

  public var selectedList: CardListRecord? {
    guard let selectedListID else {
      return nil
    }

    return cardLists.first { $0.id == selectedListID }
  }

  public var favouritesList: CardListRecord? {
    cardLists.first { isProtectedFavouritesList($0) }
  }

  public var pinnedCardLists: [CardListRecord] {
    sortedCardLists(cardLists.filter { $0.isPinned && !isProtectedFavouritesList($0) })
  }

  public var unpinnedCardLists: [CardListRecord] {
    sortedCardLists(cardLists.filter { !$0.isPinned && !isProtectedFavouritesList($0) })
  }

  func sortedCardLists(_ lists: [CardListRecord]) -> [CardListRecord] {
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
      && !isTranslatingSearch
      && !isLoadingMoreCards
      && !isCreatingListFromSearch
      && !hasPendingPlainTextPrompt
  }

  public var canClearSearch: Bool {
    !searchText.isEmpty || !submittedSearchText.isEmpty || generatedSearchQuery != nil
  }

  public var hasUnsubmittedSearchText: Bool {
    GrimoraSearchHistoryStore.normalizedQuery(searchText)
      != GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText)
  }

  public var visibleSearchHistory: [String] {
    searchInputMode == .plainText ? plainTextSearchHistory : searchHistory
  }

  public var plainTextSearchAvailability: PlainTextSearchTranspilerAvailability {
    plainTextSearchTranspiler.availability
  }

  public var isPlainTextSearchAvailable: Bool {
    plainTextSearchAvailability.isAvailable
  }

  public var plainTextSearchUnavailableMessage: String? {
    plainTextSearchAvailability.message
  }

  public var isPlainTextSearchModeActive: Bool {
    searchInputMode == .plainText
  }

  public var hasLocalCardData: Bool {
    (try? database.cardCount()) ?? 0 > 0
  }

  let database: CardDatabase
  let updateService: LibraryUpdateService
  let importer: LibraryImporter
  let imageCache: CardImageCache
  let imageStore: ImageStore
  let archidektDeckClient: ArchidektDeckClient
  let plainTextSearchTranspiler: any PlainTextSearchTranspiling
  let imageDownloadCoordinator: CardImageDownloadCoordinator
  let previewImageWarmer: PreviewImageWarmer
  let temporaryDirectory: URL
  let valueHistoryBackgroundDirectory: URL
  let autoUpdateChecksEnabled: Bool
  let searchHistoryStore: GrimoraSearchHistoryStore
  let plainTextSearchHistoryStore: GrimoraSearchHistoryStore
  let imageDownloadConfiguration: GrimoraImageDownloadConfiguration
  let searchPerformance: GrimoraSearchPerformanceConfiguration
  let cloudSyncCoordinator: CloudSyncCoordinator
  let canOfferInitialCloudSync: Bool
  let currencyExchangeRateClient: any CurrencyExchangeRateClient
  let cloudSyncDeviceID: String
  let cloudSyncDeviceName: String
  var searchTask: Task<Void, Never>?
  var searchDebounceTask: Task<Void, Never>?
  var plainTextSearchTask: Task<Void, Never>?
  var nextPagePrefetchTask: Task<Void, Never>?
  var searchHistoryRecordTask: Task<Void, Never>?
  var cloudSyncTask: Task<Void, Never>?
  var valueHistoryRefreshTask: Task<Void, Never>?
  var valueHistoryBackgroundTask: Task<Void, Never>?
  var libraryActivityDismissTask: Task<Void, Never>?
  var cardDataReadHeartbeatTask: Task<Void, Never>?
  var searchGeneration: UInt64 = 0
  var currentSearchCacheKey: SearchResultCacheKey?
  var isUpdatingCurrentSort = false
  var isUpdatingSearchInputMode = false
  var isUpdatingSelectedCardSource = false
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
  var listUndoStack: [CardListUndoState] = []

  public init(
    environment: GrimoraEnvironment,
    initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration =
      GrimoraDefaultSearchConfiguration(),
    initialSearchInputMode: SearchInputMode = GrimoraSearchPreferences.defaultSearchInputMode,
    initialCloudSyncMode: GrimoraCloudSyncMode = .undecided
  ) {
    self.database = environment.database
    self.updateService = environment.updateService
    self.importer = environment.importer
    self.imageCache = environment.imageCache
    self.imageStore = environment.imageStore
    self.archidektDeckClient = environment.archidektDeckClient
    self.plainTextSearchTranspiler = environment.plainTextSearchTranspiler
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
    self.plainTextSearchHistoryStore = environment.plainTextSearchHistoryStore
    self.imageDownloadConfiguration = environment.imageDownloadConfiguration
    self.searchPerformance = environment.searchPerformanceConfiguration
    self.cloudSyncCoordinator = environment.cloudSyncCoordinator
    self.canOfferInitialCloudSync = environment.canOfferInitialCloudSync
    self.currencyExchangeRateClient = environment.currencyExchangeRateClient
    self.cloudSyncDeviceID = GrimoraCloudSyncPreferences.deviceID()
    self.cloudSyncDeviceName = "Grimora Device"
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

    if initialSearchInputMode == .plainText, plainTextSearchTranspiler.availability.isAvailable {
      searchInputMode = .plainText
    } else if initialSearchInputMode == .plainText {
      plainTextSearchErrorMessage =
        plainTextSearchTranspiler.availability.message ?? "Plain-text search is unavailable."
    }

    searchHistory = environment.searchHistoryStore.load()
    plainTextSearchHistory = environment.plainTextSearchHistoryStore.load()
    reloadCardLists()
    refreshLibraryState()

    if hasLibrary {
      reloadSearch()
      scheduleSearchHistoryPreviewWarm()
      startValueHistoryBackgroundImportIfNeeded()
    }

    if autoUpdateChecksEnabled && !hasLocalCardData {
      Task { await checkForUpdates(manual: false) }
    }

    if initialCloudSyncMode == .enabled {
      Task { await startCloudSync() }
    }
  }
}
