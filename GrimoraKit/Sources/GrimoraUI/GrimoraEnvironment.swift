import Foundation
import GrimoraCore
#if os(macOS) && canImport(Security)
  import Security
#endif

public struct GrimoraEnvironment: Sendable {
  public var database: CardDatabase
  public var updateService: LibraryUpdateService
  public var importer: LibraryImporter
  public var imageCache: CardImageCache
  public var imageStore: ImageStore
  public var archidektDeckClient: ArchidektDeckClient
  public var plainTextSearchTranspiler: any PlainTextSearchTranspiling
  public var imageDownloadConfiguration: GrimoraImageDownloadConfiguration
  public var searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration
  public var temporaryDirectory: URL
  public var valueHistoryBackgroundDirectory: URL
  public var autoUpdateChecksEnabled: Bool
  public var searchHistoryStore: GrimoraSearchHistoryStore
  public var plainTextSearchHistoryStore: GrimoraSearchHistoryStore
  public var hiddenSearchTermsStore: HiddenSearchTermsStore
  public var cloudSyncCoordinator: CloudSyncCoordinator
  public var canOfferInitialCloudSync: Bool
  public var currencyExchangeRateClient: any CurrencyExchangeRateClient
  public var managedCatalogMigrationService: ManagedCatalogMigrationService?
  public var initialManagedCatalogMigrationStatus: ManagedCatalogMigrationStatus?

  public init(
    database: CardDatabase,
    updateService: LibraryUpdateService,
    importer: LibraryImporter,
    imageCache: CardImageCache,
    imageStore: ImageStore,
    archidektDeckClient: ArchidektDeckClient = ArchidektDeckClient(network: BlockingNetworkClient()),
    plainTextSearchTranspiler: any PlainTextSearchTranspiling =
      UnavailablePlainTextSearchTranspiler(message: "Plain-text search is unavailable."),
    imageDownloadConfiguration: GrimoraImageDownloadConfiguration =
      GrimoraImageDownloadConfiguration(),
    searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration =
      GrimoraSearchPerformanceConfiguration(),
    temporaryDirectory: URL,
    valueHistoryBackgroundDirectory: URL? = nil,
    autoUpdateChecksEnabled: Bool,
    searchHistoryStore: GrimoraSearchHistoryStore = GrimoraSearchHistoryStore(),
    plainTextSearchHistoryStore: GrimoraSearchHistoryStore =
      GrimoraSearchHistoryStore(key: GrimoraSearchPreferences.plainTextSearchHistoryKey),
    hiddenSearchTermsStore: HiddenSearchTermsStore = HiddenSearchTermsStore(),
    cloudSyncCoordinator: CloudSyncCoordinator? = nil,
    canOfferInitialCloudSync: Bool = true,
    currencyExchangeRateClient: (any CurrencyExchangeRateClient)? = nil,
    managedCatalogMigrationService: ManagedCatalogMigrationService? = nil,
    initialManagedCatalogMigrationStatus: ManagedCatalogMigrationStatus? = nil
  ) {
    self.database = database
    self.updateService = updateService
    self.importer = importer
    self.imageCache = imageCache
    self.imageStore = imageStore
    self.archidektDeckClient = archidektDeckClient
    self.plainTextSearchTranspiler = plainTextSearchTranspiler
    self.imageDownloadConfiguration = imageDownloadConfiguration
    self.searchPerformanceConfiguration = searchPerformanceConfiguration
    self.temporaryDirectory = temporaryDirectory
    self.valueHistoryBackgroundDirectory = valueHistoryBackgroundDirectory
      ?? temporaryDirectory.appendingPathComponent("ValueHistory", isDirectory: true)
    self.autoUpdateChecksEnabled = autoUpdateChecksEnabled
    self.searchHistoryStore = searchHistoryStore
    self.plainTextSearchHistoryStore = plainTextSearchHistoryStore
    self.hiddenSearchTermsStore = hiddenSearchTermsStore
    self.cloudSyncCoordinator = cloudSyncCoordinator ?? .disabled(database: database)
    self.canOfferInitialCloudSync = canOfferInitialCloudSync
    self.currencyExchangeRateClient = currencyExchangeRateClient
      ?? CachedCurrencyExchangeRateClient(
        liveClient: FrankfurterCurrencyExchangeRateClient(network: BlockingNetworkClient())
      )
    self.managedCatalogMigrationService = managedCatalogMigrationService
    self.initialManagedCatalogMigrationStatus = initialManagedCatalogMigrationStatus
  }

  public static func live(
    fileManager: FileManager = .default,
    processInfo: ProcessInfo = .processInfo
  ) throws -> GrimoraEnvironment {
    let supportDirectory = try Self.applicationSupportDirectory(fileManager: fileManager)
    let testDatabaseURL = processInfo.environment["GRIMORA_TEST_DATABASE_PATH"]
      .map(URL.init(fileURLWithPath:))
    let testDatabaseAlreadyExists = testDatabaseURL.map {
      fileManager.fileExists(atPath: $0.path)
    } ?? false
    let userDatabaseURL = testDatabaseURL
      ?? supportDirectory.appendingPathComponent("Database-v2/User.sqlite")
    if processInfo.environment["GRIMORA_TEST_RESET_DATABASE"] == "1" {
      for url in [
        userDatabaseURL,
        URL(fileURLWithPath: userDatabaseURL.path + "-shm"),
        URL(fileURLWithPath: userDatabaseURL.path + "-wal"),
      ] where fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
    }
    let imageDirectory =
      processInfo.environment["GRIMORA_TEST_IMAGE_DIR"]
      .map(URL.init(fileURLWithPath:))
      ?? supportDirectory.appendingPathComponent("Images", isDirectory: true)

    let temporaryDirectory = fileManager.temporaryDirectory
      .appendingPathComponent("Grimora", isDirectory: true)
    let valueHistoryBackgroundDirectory = supportDirectory
      .appendingPathComponent("ValueHistory", isDirectory: true)

    try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: valueHistoryBackgroundDirectory, withIntermediateDirectories: true)

    let network: NetworkClient =
      processInfo.environment["GRIMORA_DISABLE_NETWORK"] == "1"
      ? BlockingNetworkClient()
      : URLSessionNetworkClient()
    let catalogAPIURL =
      testDatabaseURL == nil
      ? URL(
        string: processInfo.environment["GRIMORA_CATALOG_API_URL"]
          ?? "https://grimora-data-api.fly.dev/v1/catalog"
      )
      : nil
    let bulkClient = BulkDataClient(network: network, catalogAPIURL: catalogAPIURL)

    let database: CardDatabase
    let databaseAlreadyExists: Bool
    let managedCatalogMigrationService: ManagedCatalogMigrationService?
    let initialManagedCatalogMigrationStatus: ManagedCatalogMigrationStatus?
    if testDatabaseURL != nil {
      database = try CardDatabase(storage: .file(userDatabaseURL))
      databaseAlreadyExists = testDatabaseAlreadyExists
      managedCatalogMigrationService = nil
      initialManagedCatalogMigrationStatus = nil
    } else {
      let bootstrap = try ManagedCatalogMigrationService.bootstrap(
        supportDirectory: supportDirectory,
        bulkDataClient: bulkClient,
        fileManager: fileManager
      )
      database = bootstrap.database
      databaseAlreadyExists = bootstrap.databaseAlreadyExists
      managedCatalogMigrationService = bootstrap.migrationService
      initialManagedCatalogMigrationStatus = bootstrap.initialMigrationStatus
    }
    try seedTestFixtureCardsIfNeeded(database: database, processInfo: processInfo)

    let imageStore = ImageStore(rootDirectory: imageDirectory)
    let imageResolver = DownloadingImageResolver(store: imageStore, network: network)
    let searchHistoryUserDefaults =
      processInfo.environment["GRIMORA_TEST_USER_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
      ?? .standard
    seedTestValuePreferencesIfNeeded(processInfo: processInfo, userDefaults: .standard)
    let searchHistoryStore = GrimoraSearchHistoryStore(userDefaults: searchHistoryUserDefaults)
    let plainTextSearchHistoryStore = GrimoraSearchHistoryStore(
      userDefaults: searchHistoryUserDefaults,
      key: GrimoraSearchPreferences.plainTextSearchHistoryKey
    )
    let hiddenSearchTermsStore = HiddenSearchTermsStore(userDefaults: searchHistoryUserDefaults)
    if let testSearchHistory = processInfo.environment["GRIMORA_TEST_SEARCH_HISTORY"] {
      searchHistoryStore.save(testSearchHistory.components(separatedBy: "\n"))
    }
    if let testPlainTextSearchHistory = processInfo.environment["GRIMORA_TEST_PLAIN_TEXT_SEARCH_HISTORY"] {
      plainTextSearchHistoryStore.save(testPlainTextSearchHistory.components(separatedBy: "\n"))
    }
    let importer = LibraryImporter(database: database, imageResolver: imageResolver)
    let imageCache = CardImageCache(database: database, imageResolver: imageResolver)
    let priceHistoryClient =
      testDatabaseURL == nil ? nil : MTGJSONPriceHistoryClient(network: network)
    let priceHistoryImporter =
      testDatabaseURL == nil ? nil : MTGJSONPriceHistoryImporter(database: database)
    let currencyExchangeRateClient = CachedCurrencyExchangeRateClient(
      liveClient: FrankfurterCurrencyExchangeRateClient(network: network),
      userDefaults: .standard
    )
    let updateService = LibraryUpdateService(
      database: database,
      bulkDataClient: bulkClient,
      priceHistoryClient: priceHistoryClient,
      priceHistoryImporter: priceHistoryImporter,
      minimumAutomaticCheckInterval: 24 * 60 * 60
    )
    let cloudSyncCoordinator =
      Self.cloudSyncIsDisabled(processInfo: processInfo)
      ? .disabled(database: database)
      : Self.liveCloudSyncCoordinator(database: database, processInfo: processInfo)

    return GrimoraEnvironment(
      database: database,
      updateService: updateService,
      importer: importer,
      imageCache: imageCache,
      imageStore: imageStore,
      archidektDeckClient: ArchidektDeckClient(network: network),
      plainTextSearchTranspiler: PlainTextSearchTranspilerFactory.live(processInfo: processInfo),
      imageDownloadConfiguration: .liveDefault,
      searchPerformanceConfiguration: .liveDefault(
        textDebounceNanoseconds: processInfo.environment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"]
          .flatMap(UInt64.init) ?? 120_000_000
      ),
      temporaryDirectory: temporaryDirectory,
      valueHistoryBackgroundDirectory: valueHistoryBackgroundDirectory,
      autoUpdateChecksEnabled: processInfo.environment["GRIMORA_DISABLE_AUTO_UPDATE"] != "1",
      searchHistoryStore: searchHistoryStore,
      plainTextSearchHistoryStore: plainTextSearchHistoryStore,
      hiddenSearchTermsStore: hiddenSearchTermsStore,
      cloudSyncCoordinator: cloudSyncCoordinator,
      canOfferInitialCloudSync: !databaseAlreadyExists,
      currencyExchangeRateClient: currencyExchangeRateClient,
      managedCatalogMigrationService: managedCatalogMigrationService,
      initialManagedCatalogMigrationStatus: initialManagedCatalogMigrationStatus
    )
  }

  private static func seedTestFixtureCardsIfNeeded(
    database: CardDatabase,
    processInfo: ProcessInfo
  ) throws {
    guard let fixtureJSON = processInfo.environment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] else {
      return
    }

    let cards = try JSONDecoder().decode([CardRecord].self, from: Data(fixtureJSON.utf8))
    try database.replaceAllCards(cards)
    try database.saveMetadataValue(
      "2026-04-25T09:09:59.477+00:00",
      forKey: MetadataKey.defaultCardsUpdatedAt.rawValue
    )
    try database.saveMetadataValue(
      CardDatabase.currentSearchSchemaVersion,
      forKey: MetadataKey.searchSchemaVersion.rawValue
    )
    try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)

    guard let listName = processInfo.environment["GRIMORA_TEST_CATEGORIZED_LIST_NAME"],
      let rawCategoryNames = processInfo.environment["GRIMORA_TEST_CATEGORY_NAMES"]
    else {
      return
    }

    let categoryNames = rawCategoryNames
      .split(separator: "\n")
      .map(String.init)
    guard !categoryNames.isEmpty else {
      return
    }

    let list = try database.createCardList(named: listName)
    let categories = try categoryNames.map {
      try database.createCardListCategory(inList: list.id, named: $0)
    }
    for (index, card) in cards.enumerated() {
      try database.appendCard(
        card.id,
        toList: list.id,
        categoryID: categories[index % categories.count].id
      )
    }
  }

  private static func seedTestValuePreferencesIfNeeded(
    processInfo: ProcessInfo,
    userDefaults: UserDefaults
  ) {
    if processInfo.environment["GRIMORA_TEST_RESET_VALUE_DEFAULTS"] == "1" {
      userDefaults.removeObject(forKey: GrimoraValuePreferences.displayCurrencyKey)
    }

    guard let rawRate = processInfo.environment["GRIMORA_TEST_USD_TO_AUD_RATE"],
      let rate = Double(rawRate)
    else {
      return
    }

    CachedCurrencyExchangeRateClient.save(
      CurrencyExchangeRate(
        baseCurrency: .usd,
        quoteCurrency: .aud,
        rate: rate,
        date: processInfo.environment["GRIMORA_TEST_USD_TO_AUD_RATE_DATE"] ?? "2026-05-19",
        providerName: processInfo.environment["GRIMORA_TEST_USD_TO_AUD_RATE_PROVIDER"] ?? "Frankfurter"
      ),
      userDefaults: userDefaults
    )
  }

  private static func liveCloudSyncCoordinator(
    database: CardDatabase,
    processInfo: ProcessInfo
  ) -> CloudSyncCoordinator {
    if let relayURL = processInfo.environment["GRIMORA_TEST_CLOUD_SYNC_RELAY_URL"]
      .flatMap(URL.init(string:))
    {
      return CloudSyncCoordinator(
        database: database,
        transport: RelayCloudSyncTransport(baseURL: relayURL)
      )
    }

    #if canImport(CloudKit)
      guard hasCloudKitContainerEntitlement() else {
        return .disabled(database: database)
      }

      if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
        let stateSerialization = try? database.cloudSyncEngineStateSerialization()
        let transport = CloudKitSyncTransport(
          stateSerialization: stateSerialization,
          stateSerializationHandler: { [database] data in
            try? database.saveCloudSyncEngineStateSerialization(data)
          },
          systemFieldsProvider: { [database] recordType, recordID in
            try? database.cloudSyncRecordSystemFields(
              recordType: recordType,
              recordID: recordID
            )
          },
          systemFieldsHandler: { [database] data, recordType, recordID in
            try? database.saveCloudSyncRecordSystemFields(
              data,
              recordType: recordType,
              recordID: recordID
            )
          }
        )
        return CloudSyncCoordinator(database: database, transport: transport)
      }
    #endif
    return .disabled(database: database)
  }

  private static func cloudSyncIsDisabled(processInfo: ProcessInfo) -> Bool {
    processInfo.environment["GRIMORA_DISABLE_CLOUD_SYNC"] == "1"
      || processInfo.environment["GRIMORA_DISABLE_NETWORK"] == "1"
  }

  private static func hasCloudKitContainerEntitlement() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #elseif os(macOS) && canImport(Security)
      let entitlementKey = "com.apple.developer.icloud-container-identifiers" as CFString
      guard let task = SecTaskCreateFromSelf(nil),
        let entitlement = SecTaskCopyValueForEntitlement(task, entitlementKey, nil)
      else {
        return false
      }

      if let identifiers = entitlement as? [String] {
        return identifiers.contains(GrimoraCloudSyncConstants.containerIdentifier)
      }

      if let identifier = entitlement as? String {
        return identifier == GrimoraCloudSyncConstants.containerIdentifier
      }
      return false
    #else
      return true
    #endif
  }

  private static func applicationSupportDirectory(fileManager: FileManager) throws -> URL {
    let base = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return base.appendingPathComponent("Grimora", isDirectory: true)
  }
}

public struct GrimoraImageDownloadConfiguration: Sendable {
  public var visibleConcurrency: Int
  public var detailConcurrency: Int
  public var visibleRetryAttemptCount: Int
  public var visibleAttemptTimeoutNanoseconds: UInt64
  public var visibleRetryDelayNanoseconds: [UInt64]
  public var decodedPreviewCacheCountLimit: Int
  public var decodedPreviewCacheCostLimitBytes: Int
  public var previewDecodeConcurrency: Int
  public var historyWarmQueryLimit: Int
  public var historyWarmResultLimit: Int
  public var historyWarmDelayNanoseconds: UInt64
  public var visiblePendingQueueLimit: Int
  public var visibleRetainedWindowCount: Int

  public init(
    visibleConcurrency: Int = 8,
    detailConcurrency: Int = 2,
    visibleRetryAttemptCount: Int = 3,
    visibleAttemptTimeoutNanoseconds: UInt64 = 15_000_000_000,
    visibleRetryDelayNanoseconds: [UInt64] = [1_000_000_000, 4_000_000_000],
    decodedPreviewCacheCountLimit: Int = 2_048,
    decodedPreviewCacheCostLimitBytes: Int = 512 * 1_024 * 1_024,
    previewDecodeConcurrency: Int = 2,
    historyWarmQueryLimit: Int = 5,
    historyWarmResultLimit: Int = 96,
    historyWarmDelayNanoseconds: UInt64 = 5_000_000_000,
    visiblePendingQueueLimit: Int = 240,
    visibleRetainedWindowCount: Int = 4
  ) {
    self.visibleConcurrency = max(1, visibleConcurrency)
    self.detailConcurrency = max(1, detailConcurrency)
    self.visibleRetryAttemptCount = max(1, visibleRetryAttemptCount)
    self.visibleAttemptTimeoutNanoseconds = visibleAttemptTimeoutNanoseconds
    self.visibleRetryDelayNanoseconds = visibleRetryDelayNanoseconds
    self.decodedPreviewCacheCountLimit = max(1, decodedPreviewCacheCountLimit)
    self.decodedPreviewCacheCostLimitBytes = max(1, decodedPreviewCacheCostLimitBytes)
    self.previewDecodeConcurrency = max(1, previewDecodeConcurrency)
    self.historyWarmQueryLimit = max(0, historyWarmQueryLimit)
    self.historyWarmResultLimit = max(0, historyWarmResultLimit)
    self.historyWarmDelayNanoseconds = historyWarmDelayNanoseconds
    self.visiblePendingQueueLimit = max(1, visiblePendingQueueLimit)
    self.visibleRetainedWindowCount = max(1, visibleRetainedWindowCount)
  }

  public static var liveDefault: GrimoraImageDownloadConfiguration {
    #if os(iOS) || os(visionOS)
      GrimoraImageDownloadConfiguration(visibleConcurrency: 3, detailConcurrency: 2)
    #else
      GrimoraImageDownloadConfiguration()
    #endif
  }
}

public struct GrimoraSearchPerformanceConfiguration: Equatable, Sendable {
  public var pageSize: Int
  public var textDebounceNanoseconds: UInt64
  public var prefetchesNextPage: Bool
  public var loadMoreThreshold: Int
  public var imageLookaheadCount: Int
  public var firstPageCacheCapacity: Int
  public var pageCacheCapacity: Int

  public init(
    pageSize: Int = 250,
    textDebounceNanoseconds: UInt64 = 120_000_000,
    prefetchesNextPage: Bool = true,
    loadMoreThreshold: Int = 72,
    imageLookaheadCount: Int = 36,
    firstPageCacheCapacity: Int = 10,
    pageCacheCapacity: Int = 12
  ) {
    self.pageSize = max(1, pageSize)
    self.textDebounceNanoseconds = textDebounceNanoseconds
    self.prefetchesNextPage = prefetchesNextPage
    self.loadMoreThreshold = max(1, loadMoreThreshold)
    self.imageLookaheadCount = max(0, imageLookaheadCount)
    self.firstPageCacheCapacity = max(0, firstPageCacheCapacity)
    self.pageCacheCapacity = max(0, pageCacheCapacity)
  }

  public static let immediate = GrimoraSearchPerformanceConfiguration(
    textDebounceNanoseconds: 0
  )

  public static func liveDefault(textDebounceNanoseconds: UInt64 = 120_000_000) -> Self {
    #if os(iOS) || os(visionOS)
      Self(
        textDebounceNanoseconds: textDebounceNanoseconds,
        loadMoreThreshold: 48,
        imageLookaheadCount: 12
      )
    #else
      Self(textDebounceNanoseconds: textDebounceNanoseconds)
    #endif
  }
}
