import Foundation

public enum GrimoraCloudSyncConstants {
  public static let containerIdentifier = "iCloud.com.samwagner.Grimora"
  public static let currentSyncSchemaVersion = 4
}

public enum CloudSyncTransportEvent: Equatable, Sendable {
  case remoteChangesAvailable
  case accountChanged(CloudSyncAccountChange)
  case didDownload(Date)
  case didUpload(Date)
  case failed(String)
}

public enum CloudSyncStatus: Equatable, Sendable {
  case disabled
  case unavailable(String)
  case preparing
  case ready
  case appliedRemoteSnapshot(DeviceSyncSnapshot)
  case syncing
  case needsAppUpdate(requiredSyncSchemaVersion: Int)
  case accountChangeRequiresResolution(CloudSyncAccountChange)
  case failed(String)
}

public struct CloudSyncAccountChange: Equatable, Sendable {
  public var previousAccountIdentifier: String?
  public var currentAccountIdentifier: String?

  public init(
    previousAccountIdentifier: String?,
    currentAccountIdentifier: String?
  ) {
    self.previousAccountIdentifier = previousAccountIdentifier
    self.currentAccountIdentifier = currentAccountIdentifier
  }
}

public struct LibraryIdentity: Codable, Equatable, Sendable {
  public var defaultCardsUpdatedAt: String?
  public var defaultCardsDownloadURI: URL?
  public var defaultCardsName: String
  public var defaultCardsSize: Int
  public var searchSchemaVersion: String
  public var syncSchemaVersion: Int
  public var catalogSchemaVersion: Int?

  public init(
    defaultCardsUpdatedAt: String? = nil,
    defaultCardsDownloadURI: URL? = nil,
    defaultCardsName: String = "Default Cards",
    defaultCardsSize: Int = 0,
    searchSchemaVersion: String = CardDatabase.currentSearchSchemaVersion,
    syncSchemaVersion: Int = GrimoraCloudSyncConstants.currentSyncSchemaVersion,
    catalogSchemaVersion: Int? = nil
  ) {
    self.defaultCardsUpdatedAt = defaultCardsUpdatedAt
    self.defaultCardsDownloadURI = defaultCardsDownloadURI
    self.defaultCardsName = defaultCardsName
    self.defaultCardsSize = defaultCardsSize
    self.searchSchemaVersion = searchSchemaVersion
    self.syncSchemaVersion = syncSchemaVersion
    self.catalogSchemaVersion = catalogSchemaVersion
  }

  public var requiresNewerApp: Bool {
    syncSchemaVersion > GrimoraCloudSyncConstants.currentSyncSchemaVersion
  }

  public var hasRequiredCardManifest: Bool {
    defaultCardsUpdatedAt != nil && defaultCardsDownloadURI != nil
  }

  public func requirement(for localIdentity: LibraryIdentity) -> LibraryIdentityRequirement {
    if requiresNewerApp {
      return .needsAppUpdate(requiredSyncSchemaVersion: syncSchemaVersion)
    }
    return .satisfied
  }

  public var manifest: BulkDataManifest? {
    guard let updatedAt = defaultCardsUpdatedAt,
      let downloadURI = defaultCardsDownloadURI
    else {
      return nil
    }

    return BulkDataManifest(
      id: "cloud-required-default-cards",
      type: "default_cards",
      updatedAt: updatedAt,
      name: defaultCardsName,
      size: defaultCardsSize,
      downloadURI: downloadURI
    )
  }
}

public enum LibraryIdentityRequirement: Equatable, Sendable {
  case satisfied
  case needsAppUpdate(requiredSyncSchemaVersion: Int)
}

public struct SyncSearchSettings: Codable, Equatable, Sendable {
  public var defaultSearchText: String
  public var alwaysIncludedSearchText: String
  public var defaultSortModeRawValue: String
  public var defaultSortDirectionRawValue: String
  public var displayCurrencyRawValue: String
  public var searchHistory: [String]
  public var hiddenSearchTerms: [SearchRefinement]
  public var updatedAt: Date

  public init(
    defaultSearchText: String = "",
    alwaysIncludedSearchText: String = "",
    defaultSortModeRawValue: String = SortMode.releaseDate.rawValue,
    defaultSortDirectionRawValue: String = "ascending",
    displayCurrencyRawValue: String = "USD",
    searchHistory: [String] = [],
    hiddenSearchTerms: [SearchRefinement] = [],
    updatedAt: Date = Date()
  ) {
    self.defaultSearchText = defaultSearchText
    self.alwaysIncludedSearchText = alwaysIncludedSearchText
    self.defaultSortModeRawValue = defaultSortModeRawValue
    self.defaultSortDirectionRawValue = defaultSortDirectionRawValue
    self.displayCurrencyRawValue = displayCurrencyRawValue
    self.searchHistory = Self.normalizedHistory(searchHistory)
    self.hiddenSearchTerms = SearchRefinement.normalizedHiddenTerms(hiddenSearchTerms)
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case defaultSearchText
    case alwaysIncludedSearchText
    case defaultSortModeRawValue
    case defaultSortDirectionRawValue
    case displayCurrencyRawValue
    case searchHistory
    case hiddenSearchTerms
    case updatedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    defaultSearchText = try container.decodeIfPresent(String.self, forKey: .defaultSearchText) ?? ""
    alwaysIncludedSearchText =
      try container.decodeIfPresent(String.self, forKey: .alwaysIncludedSearchText) ?? ""
    defaultSortModeRawValue =
      try container.decodeIfPresent(String.self, forKey: .defaultSortModeRawValue)
      ?? SortMode.releaseDate.rawValue
    defaultSortDirectionRawValue =
      try container.decodeIfPresent(String.self, forKey: .defaultSortDirectionRawValue)
      ?? "ascending"
    displayCurrencyRawValue =
      try container.decodeIfPresent(String.self, forKey: .displayCurrencyRawValue)
      ?? "USD"
    searchHistory = Self.normalizedHistory(
      try container.decodeIfPresent([String].self, forKey: .searchHistory) ?? []
    )
    hiddenSearchTerms = SearchRefinement.normalizedHiddenTerms(
      try container.decodeIfPresent([SearchRefinement].self, forKey: .hiddenSearchTerms) ?? []
    )
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }

  public static func merged(_ settings: [SyncSearchSettings]) -> SyncSearchSettings {
    guard let newest = settings.max(by: { $0.updatedAt < $1.updatedAt }) else {
      return SyncSearchSettings(updatedAt: .distantPast)
    }

    var result = newest
    result.searchHistory = mergedHistory(settings.map { ($0.searchHistory, $0.updatedAt) })
    return result
  }

  private static func mergedHistory(_ candidates: [([String], Date)]) -> [String] {
    var history: [String] = []
    for candidate in candidates.sorted(by: { $0.1 > $1.1 }) {
      for query in candidate.0 {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !history.contains(normalized) else {
          continue
        }
        history.append(normalized)
        if history.count == 10 {
          return history
        }
      }
    }
    return history
  }

  private static func normalizedHistory(_ history: [String]) -> [String] {
    mergedHistory([(history, .distantPast)])
  }
}

public struct DeviceSyncSnapshot: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var deviceName: String
  public var capturedAt: Date
  public var libraryIdentity: LibraryIdentity
  public var searchSettings: SyncSearchSettings
  public var listSnapshot: CardCollectionLibrarySnapshot
  public var deletedLists: [SyncListDeletion]
  public var deletedEntities: [SyncTombstone]

  public init(
    id: String,
    deviceName: String,
    capturedAt: Date = Date(),
    libraryIdentity: LibraryIdentity,
    searchSettings: SyncSearchSettings,
    listSnapshot: CardCollectionLibrarySnapshot,
    deletedLists: [SyncListDeletion] = [],
    deletedEntities: [SyncTombstone] = []
  ) {
    self.id = id
    self.deviceName = deviceName
    self.capturedAt = capturedAt
    self.libraryIdentity = libraryIdentity
    self.searchSettings = searchSettings
    self.listSnapshot = listSnapshot
    self.deletedLists = deletedLists
    self.deletedEntities = deletedEntities
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case deviceName
    case capturedAt
    case libraryIdentity
    case searchSettings
    case listSnapshot
    case deletedLists
    case deletedEntities
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    deviceName = try container.decode(String.self, forKey: .deviceName)
    capturedAt = try container.decode(Date.self, forKey: .capturedAt)
    libraryIdentity = try container.decode(LibraryIdentity.self, forKey: .libraryIdentity)
    searchSettings = try container.decode(SyncSearchSettings.self, forKey: .searchSettings)
    listSnapshot = try container.decode(CardCollectionLibrarySnapshot.self, forKey: .listSnapshot)
    deletedLists = try container.decodeIfPresent([SyncListDeletion].self, forKey: .deletedLists) ?? []
    deletedEntities =
      try container.decodeIfPresent([SyncTombstone].self, forKey: .deletedEntities) ?? []
  }

  public var listCount: Int {
    listSnapshot.lists.count
  }

  public var entryCount: Int {
    listSnapshot.entries.reduce(0) { $0 + max(1, $1.quantity) }
  }

  public var isEffectivelyEmpty: Bool {
    hasNoUserListContent
      && searchSettings.defaultSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && searchSettings.alwaysIncludedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && searchSettings.searchHistory.isEmpty
      && searchSettings.hiddenSearchTerms.isEmpty
  }

  private var hasNoUserListContent: Bool {
    guard listSnapshot.categories.isEmpty, listSnapshot.entries.isEmpty else {
      return false
    }

    return listSnapshot.lists.isEmpty
      || listSnapshot.lists.allSatisfy { list in
        list.entryCount == 0 && Self.isSystemFavouritesListName(list.name)
      }
  }

  private static func isSystemFavouritesListName(_ name: String) -> Bool {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "favourites", "favorites":
      return true
    default:
      return false
    }
  }
}

public struct SyncListDeletion: Codable, Equatable, Identifiable, Sendable {
  public var id: CardCollectionRecord.ID
  public var deletedAt: Date

  public init(id: CardCollectionRecord.ID, deletedAt: Date) {
    self.id = id
    self.deletedAt = deletedAt
  }
}

public struct CloudSyncRecoverySnapshot: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var createdAt: Date
  public var reason: String
  public var libraryIdentity: LibraryIdentity
  public var listSnapshot: CardCollectionLibrarySnapshot
  public var deletedLists: [SyncListDeletion]

  public init(
    id: String = UUID().uuidString.lowercased(),
    createdAt: Date = Date(),
    reason: String,
    libraryIdentity: LibraryIdentity,
    listSnapshot: CardCollectionLibrarySnapshot,
    deletedLists: [SyncListDeletion]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.reason = reason
    self.libraryIdentity = libraryIdentity
    self.listSnapshot = listSnapshot
    self.deletedLists = deletedLists
  }
}

public enum CloudSyncRecoveryPolicy {
  public static let minimumRevisionCount = 20
  public static let retentionDuration: TimeInterval = 30 * 24 * 60 * 60

  public static func retained(
    _ snapshots: [CloudSyncRecoverySnapshot],
    now: Date = Date()
  ) -> [CloudSyncRecoverySnapshot] {
    var uniqueByID: [CloudSyncRecoverySnapshot.ID: CloudSyncRecoverySnapshot] = [:]
    for snapshot in snapshots {
      if let current = uniqueByID[snapshot.id], current.createdAt >= snapshot.createdAt {
        continue
      }
      uniqueByID[snapshot.id] = snapshot
    }

    let sorted = uniqueByID.values.sorted {
      if $0.createdAt != $1.createdAt {
        return $0.createdAt > $1.createdAt
      }
      return $0.id > $1.id
    }
    let cutoff = now.addingTimeInterval(-retentionDuration)
    return sorted.enumerated().compactMap { index, snapshot in
      index < minimumRevisionCount || snapshot.createdAt >= cutoff ? snapshot : nil
    }
  }
}

public enum CloudSyncSnapshotValidationError: Error, Equatable, Sendable {
  case duplicateListID(String)
  case duplicateCategoryID(String)
  case duplicateEntryID(String)
  case missingListForCategory(categoryID: String, listID: String)
  case missingListForEntry(entryID: String, listID: String)
  case missingCategoryForEntry(entryID: String, categoryID: String)
  case categoryListMismatch(entryID: String, categoryID: String)
}

extension DeviceSyncSnapshot {
  public func validateForApplication() throws {
    try listSnapshot.validateForApplication()
  }
}

extension CardCollectionLibrarySnapshot {
  public func validateForApplication() throws {
    var listIDs: Set<CardCollectionRecord.ID> = []
    for list in lists where !listIDs.insert(list.id).inserted {
      throw CloudSyncSnapshotValidationError.duplicateListID(list.id)
    }

    var categoriesByID: [CardCollectionCategoryRecord.ID: CardCollectionCategoryRecord] = [:]
    for category in categories {
      guard categoriesByID[category.id] == nil else {
        throw CloudSyncSnapshotValidationError.duplicateCategoryID(category.id)
      }
      guard listIDs.contains(category.listID) else {
        throw CloudSyncSnapshotValidationError.missingListForCategory(
          categoryID: category.id,
          listID: category.listID
        )
      }
      categoriesByID[category.id] = category
    }

    var entryIDs: Set<CardCollectionEntryRecord.ID> = []
    for entry in entries {
      guard entryIDs.insert(entry.id).inserted else {
        throw CloudSyncSnapshotValidationError.duplicateEntryID(entry.id)
      }
      guard listIDs.contains(entry.listID) else {
        throw CloudSyncSnapshotValidationError.missingListForEntry(
          entryID: entry.id,
          listID: entry.listID
        )
      }
      guard let categoryID = entry.categoryID else {
        continue
      }
      guard let category = categoriesByID[categoryID] else {
        throw CloudSyncSnapshotValidationError.missingCategoryForEntry(
          entryID: entry.id,
          categoryID: categoryID
        )
      }
      guard category.listID == entry.listID else {
        throw CloudSyncSnapshotValidationError.categoryListMismatch(
          entryID: entry.id,
          categoryID: categoryID
        )
      }
    }
  }
}

extension DeviceSyncSnapshot {
  public static func merged(
    snapshots: [DeviceSyncSnapshot],
    deviceID: String,
    deviceName: String,
    libraryIdentity: LibraryIdentity,
    capturedAt: Date = Date()
  ) -> DeviceSyncSnapshot {
    let candidates = snapshots.sorted { lhs, rhs in
      if lhs.capturedAt != rhs.capturedAt {
        return lhs.capturedAt < rhs.capturedAt
      }
      return lhs.id < rhs.id
    }

    var winningLists: [CardCollectionRecord.ID: (snapshot: DeviceSyncSnapshot, list: CardCollectionRecord)] = [:]
    var winningDeletions: [CardCollectionRecord.ID: (snapshot: DeviceSyncSnapshot, deletion: SyncListDeletion)] = [:]

    for snapshot in candidates {
      for list in snapshot.listSnapshot.lists {
        let candidate = (snapshot: snapshot, list: list)
        if let current = winningLists[list.id], !isNewer(candidate, than: current) {
          continue
        }
        winningLists[list.id] = candidate
      }

      for deletion in snapshot.deletedLists {
        let candidate = (snapshot: snapshot, deletion: deletion)
        if let current = winningDeletions[deletion.id], !isNewer(candidate, than: current) {
          continue
        }
        winningDeletions[deletion.id] = candidate
      }
    }

    var lists: [CardCollectionRecord] = []
    var categories: [CardCollectionCategoryRecord] = []
    var entries: [CardCollectionEntryRecord] = []
    var deletedLists: [SyncListDeletion] = []
    let allListIDs = Set(winningLists.keys).union(winningDeletions.keys)

    for listID in allListIDs.sorted() {
      let listCandidate = winningLists[listID]
      let deletionCandidate = winningDeletions[listID]

      if let deletionCandidate {
        guard let listCandidate else {
          deletedLists.append(deletionCandidate.deletion)
          continue
        }
        if isNewer(deletionCandidate, than: listCandidate) {
          deletedLists.append(deletionCandidate.deletion)
          continue
        }
      }

      guard let listCandidate else {
        continue
      }

      lists.append(listCandidate.list)
      categories.append(
        contentsOf: listCandidate.snapshot.listSnapshot.categories.filter { $0.listID == listID }
      )
      entries.append(
        contentsOf: listCandidate.snapshot.listSnapshot.entries
          .filter { $0.listID == listID }
          .map { entry in
            var entry = entry
            entry.card = nil
            return entry
          }
      )

      if let deletionCandidate {
        deletedLists.append(deletionCandidate.deletion)
      }
    }

    lists = normalizedListPositions(lists)
    let searchSettings = SyncSearchSettings.merged(candidates.map(\.searchSettings))
    var latestDeletedEntities: [String: SyncTombstone] = [:]
    for tombstone in candidates.flatMap(\.deletedEntities) {
      let key = "\(tombstone.entityType.rawValue):\(tombstone.recordID)"
      if let current = latestDeletedEntities[key], current.deletedAt >= tombstone.deletedAt {
        continue
      }
      latestDeletedEntities[key] = tombstone
    }

    return DeviceSyncSnapshot(
      id: deviceID,
      deviceName: deviceName,
      capturedAt: capturedAt,
      libraryIdentity: libraryIdentity,
      searchSettings: searchSettings,
      listSnapshot: CardCollectionLibrarySnapshot(
        lists: lists,
        categories: categories,
        entries: entries
      ),
      deletedLists: deletedLists.sorted {
        if $0.deletedAt != $1.deletedAt {
          return $0.deletedAt < $1.deletedAt
        }
        return $0.id < $1.id
      },
      deletedEntities: latestDeletedEntities.values.sorted {
        if $0.deletedAt != $1.deletedAt {
          return $0.deletedAt < $1.deletedAt
        }
        if $0.entityType != $1.entityType {
          return $0.entityType.rawValue < $1.entityType.rawValue
        }
        return $0.recordID < $1.recordID
      }
    )
  }

  private static func isNewer(
    _ candidate: (snapshot: DeviceSyncSnapshot, list: CardCollectionRecord),
    than current: (snapshot: DeviceSyncSnapshot, list: CardCollectionRecord)
  ) -> Bool {
    compare(
      timestamp: candidate.list.updatedAt,
      snapshot: candidate.snapshot,
      toTimestamp: current.list.updatedAt,
      snapshot: current.snapshot
    ) == .orderedDescending
  }

  private static func isNewer(
    _ candidate: (snapshot: DeviceSyncSnapshot, deletion: SyncListDeletion),
    than current: (snapshot: DeviceSyncSnapshot, deletion: SyncListDeletion)
  ) -> Bool {
    compare(
      timestamp: candidate.deletion.deletedAt,
      snapshot: candidate.snapshot,
      toTimestamp: current.deletion.deletedAt,
      snapshot: current.snapshot
    ) == .orderedDescending
  }

  private static func isNewer(
    _ deletion: (snapshot: DeviceSyncSnapshot, deletion: SyncListDeletion),
    than list: (snapshot: DeviceSyncSnapshot, list: CardCollectionRecord)
  ) -> Bool {
    compare(
      timestamp: deletion.deletion.deletedAt,
      snapshot: deletion.snapshot,
      toTimestamp: list.list.updatedAt,
      snapshot: list.snapshot
    ) == .orderedDescending
  }

  private static func compare(
    timestamp: Date,
    snapshot: DeviceSyncSnapshot,
    toTimestamp otherTimestamp: Date,
    snapshot otherSnapshot: DeviceSyncSnapshot
  ) -> ComparisonResult {
    if timestamp != otherTimestamp {
      return timestamp < otherTimestamp ? .orderedAscending : .orderedDescending
    }
    if snapshot.capturedAt != otherSnapshot.capturedAt {
      return snapshot.capturedAt < otherSnapshot.capturedAt ? .orderedAscending : .orderedDescending
    }
    if snapshot.id == otherSnapshot.id {
      return .orderedSame
    }
    return snapshot.id < otherSnapshot.id ? .orderedAscending : .orderedDescending
  }

  private static func normalizedListPositions(_ lists: [CardCollectionRecord]) -> [CardCollectionRecord] {
    var normalized: [CardCollectionRecord] = []
    for isPinned in [true, false] {
      let section = lists
        .filter { $0.isPinned == isPinned }
        .sorted {
          if $0.position != $1.position {
            return $0.position < $1.position
          }
          if $0.createdAt != $1.createdAt {
            return $0.createdAt < $1.createdAt
          }
          return $0.id < $1.id
        }
      normalized.append(
        contentsOf: section.enumerated().map { position, list in
          var list = list
          list.position = position
          return list
        }
      )
    }
    return normalized
  }
}

public enum SyncEntityType: String, Codable, Equatable, Sendable {
  case library
  case searchSettings
  // Raw values are the on-the-wire / persisted (sync outbox + CloudKit payload)
  // identifiers. The Swift cases were renamed list -> collection, but these raw
  // strings MUST stay as the original "cardList*" so existing synced data and
  // outbox rows continue to decode.
  case cardCollection = "cardList"
  case cardCollectionCategory = "cardListCategory"
  case cardCollectionEntry = "cardListEntry"
  case snapshot
}

public enum SyncOutboxOperation: String, Codable, Equatable, Sendable {
  case upsert
  case delete
  case snapshot
}

public struct SyncOutboxChange: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var entityType: SyncEntityType
  public var recordID: String
  public var operation: SyncOutboxOperation
  public var payload: Data?
  public var createdAt: Date

  public init(
    id: String = UUID().uuidString.lowercased(),
    entityType: SyncEntityType,
    recordID: String,
    operation: SyncOutboxOperation,
    payload: Data? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.entityType = entityType
    self.recordID = recordID
    self.operation = operation
    self.payload = payload
    self.createdAt = createdAt
  }
}

public struct SyncTombstone: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var entityType: SyncEntityType
  public var recordID: String
  public var deletedAt: Date

  public init(
    id: String = UUID().uuidString.lowercased(),
    entityType: SyncEntityType,
    recordID: String,
    deletedAt: Date = Date()
  ) {
    self.id = id
    self.entityType = entityType
    self.recordID = recordID
    self.deletedAt = deletedAt
  }
}

public struct CloudRemoteState: Codable, Equatable, Sendable {
  public var requiredLibraryIdentity: LibraryIdentity?
  public var snapshots: [DeviceSyncSnapshot]
  public var recoverySnapshots: [CloudSyncRecoverySnapshot]

  public init(
    requiredLibraryIdentity: LibraryIdentity? = nil,
    snapshots: [DeviceSyncSnapshot] = [],
    recoverySnapshots: [CloudSyncRecoverySnapshot] = []
  ) {
    self.requiredLibraryIdentity = requiredLibraryIdentity
    self.snapshots = snapshots
    self.recoverySnapshots = recoverySnapshots
  }

  private enum CodingKeys: String, CodingKey {
    case requiredLibraryIdentity
    case snapshots
    case recoverySnapshots
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    requiredLibraryIdentity =
      try container.decodeIfPresent(LibraryIdentity.self, forKey: .requiredLibraryIdentity)
    snapshots =
      try container.decodeIfPresent([DeviceSyncSnapshot].self, forKey: .snapshots) ?? []
    recoverySnapshots =
      try container.decodeIfPresent(
        [CloudSyncRecoverySnapshot].self,
        forKey: .recoverySnapshots
      ) ?? []
  }
}
