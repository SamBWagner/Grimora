import Foundation

public enum GrimoraCloudSyncConstants {
  public static let containerIdentifier = "iCloud.com.samwagner.Grimora"
  public static let currentSyncSchemaVersion = 1
}

public enum CloudSyncStatus: Equatable, Sendable {
  case disabled
  case unavailable(String)
  case preparing
  case ready
  case appliedRemoteSnapshot(DeviceSyncSnapshot)
  case syncing
  case waitingForDatabaseUpdate(LibraryIdentity)
  case needsAppUpdate(requiredSyncSchemaVersion: Int)
  case resolving([DeviceSyncSnapshot])
  case failed(String)
}

public struct LibraryIdentity: Codable, Equatable, Sendable {
  public var defaultCardsUpdatedAt: String?
  public var defaultCardsDownloadURI: URL?
  public var defaultCardsName: String
  public var defaultCardsSize: Int
  public var searchSchemaVersion: String
  public var syncSchemaVersion: Int

  public init(
    defaultCardsUpdatedAt: String? = nil,
    defaultCardsDownloadURI: URL? = nil,
    defaultCardsName: String = "Default Cards",
    defaultCardsSize: Int = 0,
    searchSchemaVersion: String = CardDatabase.currentSearchSchemaVersion,
    syncSchemaVersion: Int = GrimoraCloudSyncConstants.currentSyncSchemaVersion
  ) {
    self.defaultCardsUpdatedAt = defaultCardsUpdatedAt
    self.defaultCardsDownloadURI = defaultCardsDownloadURI
    self.defaultCardsName = defaultCardsName
    self.defaultCardsSize = defaultCardsSize
    self.searchSchemaVersion = searchSchemaVersion
    self.syncSchemaVersion = syncSchemaVersion
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

    guard defaultCardsUpdatedAt != localIdentity.defaultCardsUpdatedAt
      || searchSchemaVersion != localIdentity.searchSchemaVersion
    else {
      return .satisfied
    }

    return .needsDatabaseUpdate(self)
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
  case needsDatabaseUpdate(LibraryIdentity)
  case needsAppUpdate(requiredSyncSchemaVersion: Int)
}

public struct SyncSearchSettings: Codable, Equatable, Sendable {
  public var defaultSearchText: String
  public var alwaysIncludedSearchText: String
  public var defaultSortModeRawValue: String
  public var defaultSortDirectionRawValue: String
  public var searchInputModeRawValue: String
  public var updatedAt: Date

  public init(
    defaultSearchText: String = "",
    alwaysIncludedSearchText: String = "",
    defaultSortModeRawValue: String = SortMode.releaseDate.rawValue,
    defaultSortDirectionRawValue: String = "ascending",
    searchInputModeRawValue: String = "scryfall",
    updatedAt: Date = Date()
  ) {
    self.defaultSearchText = defaultSearchText
    self.alwaysIncludedSearchText = alwaysIncludedSearchText
    self.defaultSortModeRawValue = defaultSortModeRawValue
    self.defaultSortDirectionRawValue = defaultSortDirectionRawValue
    self.searchInputModeRawValue = searchInputModeRawValue
    self.updatedAt = updatedAt
  }
}

public struct DeviceSyncSnapshot: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var deviceName: String
  public var capturedAt: Date
  public var libraryIdentity: LibraryIdentity
  public var searchSettings: SyncSearchSettings
  public var listSnapshot: CardListLibrarySnapshot

  public init(
    id: String,
    deviceName: String,
    capturedAt: Date = Date(),
    libraryIdentity: LibraryIdentity,
    searchSettings: SyncSearchSettings,
    listSnapshot: CardListLibrarySnapshot
  ) {
    self.id = id
    self.deviceName = deviceName
    self.capturedAt = capturedAt
    self.libraryIdentity = libraryIdentity
    self.searchSettings = searchSettings
    self.listSnapshot = listSnapshot
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

public struct SyncResolutionPlan: Codable, Equatable, Sendable {
  public var sourceSnapshotID: DeviceSyncSnapshot.ID
  public var importedListIDsBySnapshotID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]

  public init(
    sourceSnapshotID: DeviceSyncSnapshot.ID,
    importedListIDsBySnapshotID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>] = [:]
  ) {
    self.sourceSnapshotID = sourceSnapshotID
    self.importedListIDsBySnapshotID = importedListIDsBySnapshotID
  }

  public func resolvedSnapshot(from snapshots: [DeviceSyncSnapshot]) throws -> DeviceSyncSnapshot {
    guard var resolved = snapshots.first(where: { $0.id == sourceSnapshotID }) else {
      throw SyncResolutionError.sourceSnapshotNotFound
    }

    var listSnapshot = resolved.listSnapshot
    var usedListIDs = Set(listSnapshot.lists.map(\.id))
    var usedCategoryIDs = Set(listSnapshot.categories.map(\.id))
    var usedEntryIDs = Set(listSnapshot.entries.map(\.id))

    for snapshot in snapshots where snapshot.id != sourceSnapshotID {
      let selectedListIDs = importedListIDsBySnapshotID[snapshot.id] ?? []
      guard !selectedListIDs.isEmpty else {
        continue
      }

      for sourceList in snapshot.listSnapshot.lists where selectedListIDs.contains(sourceList.id) {
        var list = sourceList
        let originalListID = sourceList.id
        if usedListIDs.contains(list.id) {
          list.id = UUID().uuidString.lowercased()
          list.name = "\(list.name) (Imported)"
        }
        list.position = listSnapshot.lists.filter { $0.isPinned == list.isPinned }.count
        usedListIDs.insert(list.id)

        var categoryIDMap: [CardListCategoryRecord.ID: CardListCategoryRecord.ID] = [:]
        let copiedCategories = snapshot.listSnapshot.categories
          .filter { $0.listID == originalListID }
          .map { category -> CardListCategoryRecord in
            var copied = category
            if usedCategoryIDs.contains(copied.id) {
              copied.id = UUID().uuidString.lowercased()
            }
            usedCategoryIDs.insert(copied.id)
            categoryIDMap[category.id] = copied.id
            copied.listID = list.id
            return copied
          }

        let copiedEntries = snapshot.listSnapshot.entries
          .filter { $0.listID == originalListID }
          .map { entry -> CardListEntryRecord in
            var copied = entry
            if usedEntryIDs.contains(copied.id) {
              copied.id = UUID().uuidString.lowercased()
            }
            usedEntryIDs.insert(copied.id)
            copied.listID = list.id
            copied.categoryID = entry.categoryID.flatMap { categoryIDMap[$0] }
            copied.card = nil
            return copied
          }

        list.entryCount = copiedEntries.reduce(0) { $0 + max(1, $1.quantity) }
        listSnapshot.lists.append(list)
        listSnapshot.categories.append(contentsOf: copiedCategories)
        listSnapshot.entries.append(contentsOf: copiedEntries)
      }
    }

    resolved.listSnapshot = listSnapshot
    resolved.capturedAt = Date()
    return resolved
  }
}

public enum SyncResolutionError: Error, Equatable, Sendable {
  case sourceSnapshotNotFound
}

public enum SyncEntityType: String, Codable, Equatable, Sendable {
  case library
  case searchSettings
  case cardList
  case cardListCategory
  case cardListEntry
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

public struct CloudRemoteState: Equatable, Sendable {
  public var requiredLibraryIdentity: LibraryIdentity?
  public var snapshots: [DeviceSyncSnapshot]

  public init(
    requiredLibraryIdentity: LibraryIdentity? = nil,
    snapshots: [DeviceSyncSnapshot] = []
  ) {
    self.requiredLibraryIdentity = requiredLibraryIdentity
    self.snapshots = snapshots
  }
}
