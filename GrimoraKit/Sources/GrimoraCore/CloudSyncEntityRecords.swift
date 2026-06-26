import Foundation

public struct CloudSyncEntityRecord: Codable, Equatable, Identifiable, Sendable {
  public var entityType: SyncEntityType
  public var recordID: String
  public var payload: Data?
  public var updatedAt: Date
  public var deletedAt: Date?
  public var sourceDeviceID: String

  public var id: String {
    "\(entityType.rawValue):\(recordID)"
  }

  public init(
    entityType: SyncEntityType,
    recordID: String,
    payload: Data?,
    updatedAt: Date,
    deletedAt: Date? = nil,
    sourceDeviceID: String
  ) {
    self.entityType = entityType
    self.recordID = recordID
    self.payload = payload
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.sourceDeviceID = sourceDeviceID
  }

  public var isDeleted: Bool {
    deletedAt != nil
  }
}

public enum CloudSyncEntityCodec {
  public static let metadataRecordID = "sync-metadata"
  public static let preferencesRecordID = "user-preferences"
  public static let entitySnapshotID = "icloud-v4-entities"
  public static let favouritesListID = "grimora-favourites"

  public static func records(from snapshot: DeviceSyncSnapshot) throws -> [CloudSyncEntityRecord] {
    let snapshot = canonicalizedSnapshot(snapshot)
    var records: [String: CloudSyncEntityRecord] = [:]

    func insert(_ record: CloudSyncEntityRecord) {
      if let current = records[record.id], !isNewer(record, than: current) {
        return
      }
      records[record.id] = record
    }

    insert(
      CloudSyncEntityRecord(
        entityType: .library,
        recordID: metadataRecordID,
        payload: try CardDatabase.syncJSONData(snapshot.libraryIdentity),
        updatedAt: snapshot.capturedAt,
        sourceDeviceID: snapshot.id
      )
    )
    insert(
      CloudSyncEntityRecord(
        entityType: .searchSettings,
        recordID: preferencesRecordID,
        payload: try CardDatabase.syncJSONData(snapshot.searchSettings),
        updatedAt: snapshot.searchSettings.updatedAt,
        sourceDeviceID: snapshot.id
      )
    )

    for list in snapshot.listSnapshot.lists {
      insert(
        CloudSyncEntityRecord(
          entityType: .cardCollection,
          recordID: list.id,
          payload: try CardDatabase.syncJSONData(list),
          updatedAt: list.updatedAt,
          sourceDeviceID: snapshot.id
        )
      )
    }
    for category in snapshot.listSnapshot.categories {
      insert(
        CloudSyncEntityRecord(
          entityType: .cardCollectionCategory,
          recordID: category.id,
          payload: try CardDatabase.syncJSONData(category),
          updatedAt: category.updatedAt,
          sourceDeviceID: snapshot.id
        )
      )
    }
    for var entry in snapshot.listSnapshot.entries {
      entry.card = nil
      insert(
        CloudSyncEntityRecord(
          entityType: .cardCollectionEntry,
          recordID: entry.id,
          payload: try CardDatabase.syncJSONData(entry),
          updatedAt: entry.updatedAt,
          sourceDeviceID: snapshot.id
        )
      )
    }

    let tombstones =
      snapshot.deletedEntities
      + snapshot.deletedLists.map {
        SyncTombstone(entityType: .cardCollection, recordID: $0.id, deletedAt: $0.deletedAt)
      }
    for tombstone in tombstones {
      insert(
        CloudSyncEntityRecord(
          entityType: tombstone.entityType,
          recordID: tombstone.recordID,
          payload: nil,
          updatedAt: tombstone.deletedAt,
          deletedAt: tombstone.deletedAt,
          sourceDeviceID: snapshot.id
        )
      )
    }

    return records.values.sorted {
      if $0.entityType != $1.entityType {
        return $0.entityType.rawValue < $1.entityType.rawValue
      }
      return $0.recordID < $1.recordID
    }
  }

  public static func mergedRecords(
    _ recordSets: [[CloudSyncEntityRecord]]
  ) -> [CloudSyncEntityRecord] {
    var records: [String: CloudSyncEntityRecord] = [:]
    for record in recordSets.flatMap({ $0 }) {
      if let current = records[record.id], !isNewer(record, than: current) {
        continue
      }
      records[record.id] = record
    }
    return records.values.sorted {
      if $0.entityType != $1.entityType {
        return $0.entityType.rawValue < $1.entityType.rawValue
      }
      return $0.recordID < $1.recordID
    }
  }

  public static func snapshot(
    from records: [CloudSyncEntityRecord],
    fallbackIdentity: LibraryIdentity? = nil,
    capturedAt: Date = .now
  ) throws -> DeviceSyncSnapshot? {
    guard !records.isEmpty else {
      return nil
    }

    let merged = mergedRecords([records])
    let identityRecord = merged.first {
      $0.entityType == .library && $0.recordID == metadataRecordID && !$0.isDeleted
    }
    let identity: LibraryIdentity
    if let payload = identityRecord?.payload {
      identity = try CardDatabase.syncJSONValue(LibraryIdentity.self, from: payload)
    } else if let fallbackIdentity {
      identity = fallbackIdentity
    } else {
      identity = LibraryIdentity()
    }

    let searchSettings: SyncSearchSettings
    if let payload = merged.first(where: {
      $0.entityType == .searchSettings
        && $0.recordID == preferencesRecordID
        && !$0.isDeleted
    })?.payload {
      searchSettings = try CardDatabase.syncJSONValue(SyncSearchSettings.self, from: payload)
    } else {
      searchSettings = SyncSearchSettings(updatedAt: .distantPast)
    }

    let lists = try decodedValues(
      CardCollectionRecord.self,
      entityType: .cardCollection,
      records: merged
    )
    let listIDs = Set(lists.map(\.id))
    let categories = try decodedValues(
      CardCollectionCategoryRecord.self,
      entityType: .cardCollectionCategory,
      records: merged
    ).filter { listIDs.contains($0.listID) }
    let categoryIDs = Set(categories.map(\.id))
    let entries = try decodedValues(
      CardCollectionEntryRecord.self,
      entityType: .cardCollectionEntry,
      records: merged
    ).filter { entry in
      listIDs.contains(entry.listID)
        && entry.categoryID.map(categoryIDs.contains) != false
    }.map { entry in
      var entry = entry
      entry.card = nil
      return entry
    }

    let tombstones = merged.compactMap { record -> SyncTombstone? in
      guard let deletedAt = record.deletedAt,
        record.entityType == .cardCollection
          || record.entityType == .cardCollectionCategory
          || record.entityType == .cardCollectionEntry
      else {
        return nil
      }
      return SyncTombstone(
        entityType: record.entityType,
        recordID: record.recordID,
        deletedAt: deletedAt
      )
    }
    let deletedLists = tombstones
      .filter { $0.entityType == .cardCollection }
      .map { SyncListDeletion(id: $0.recordID, deletedAt: $0.deletedAt) }

    return DeviceSyncSnapshot(
      id: entitySnapshotID,
      deviceName: "iCloud",
      capturedAt: max(
        capturedAt,
        merged.map(\.updatedAt).max() ?? .distantPast
      ),
      libraryIdentity: identity,
      searchSettings: searchSettings,
      listSnapshot: CardCollectionLibrarySnapshot(
        lists: lists,
        categories: categories,
        entries: entries
      ),
      deletedLists: deletedLists,
      deletedEntities: tombstones
    )
  }

  private static func decodedValues<T: Decodable>(
    _ type: T.Type,
    entityType: SyncEntityType,
    records: [CloudSyncEntityRecord]
  ) throws -> [T] {
    try records.compactMap { record in
      guard record.entityType == entityType, !record.isDeleted, let payload = record.payload else {
        return nil
      }
      return try CardDatabase.syncJSONValue(type, from: payload)
    }
  }

  private static func isNewer(
    _ candidate: CloudSyncEntityRecord,
    than current: CloudSyncEntityRecord
  ) -> Bool {
    if candidate.updatedAt != current.updatedAt {
      return candidate.updatedAt > current.updatedAt
    }
    if candidate.isDeleted != current.isDeleted {
      return candidate.isDeleted
    }
    if candidate.sourceDeviceID == current.sourceDeviceID {
      return true
    }
    return candidate.sourceDeviceID > current.sourceDeviceID
  }

  public static func favouriteEntryID(cardID: CardRecord.ID) -> String {
    "favourite-\(cardID.lowercased())"
  }

  public static func isFavouritesListName(_ name: String) -> Bool {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "favourites", "favorites":
      return true
    default:
      return false
    }
  }

  /// Drops lists that hold no cards and carry no description text when device
  /// data is combined, tombstoning them so the deletion propagates. The system
  /// Favourites list is always preserved even when empty. Lists are only pruned
  /// at combine time (bootstrap merge / manual resolution), never during ordinary
  /// single-device syncing, so freshly created empty lists are left untouched.
  public static func pruningEmptyContentlessLists(
    _ snapshot: DeviceSyncSnapshot
  ) -> DeviceSyncSnapshot {
    let entryListIDs = Set(snapshot.listSnapshot.entries.map(\.listID))
    let prunableListIDs = Set(
      snapshot.listSnapshot.lists.filter { list in
        guard !(isFavouritesListName(list.name) || list.id == favouritesListID) else {
          return false
        }
        guard !entryListIDs.contains(list.id) else {
          return false
        }
        let hasDescription =
          list.descriptionRTFDData != nil
          || !list.descriptionPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !hasDescription
      }.map(\.id)
    )
    guard !prunableListIDs.isEmpty else {
      return snapshot
    }

    var snapshot = snapshot
    let deletedAt = snapshot.capturedAt
    snapshot.listSnapshot.lists.removeAll { prunableListIDs.contains($0.id) }
    snapshot.listSnapshot.categories.removeAll { prunableListIDs.contains($0.listID) }
    snapshot.listSnapshot.entries.removeAll { prunableListIDs.contains($0.listID) }
    for listID in prunableListIDs {
      if !snapshot.deletedLists.contains(where: { $0.id == listID }) {
        snapshot.deletedLists.append(SyncListDeletion(id: listID, deletedAt: deletedAt))
      }
      snapshot.deletedEntities.append(
        SyncTombstone(entityType: .cardCollection, recordID: listID, deletedAt: deletedAt)
      )
    }
    return snapshot
  }

  public static func canonicalizedSnapshot(
    _ snapshot: DeviceSyncSnapshot
  ) -> DeviceSyncSnapshot {
    let favourites = snapshot.listSnapshot.lists.filter {
      isFavouritesListName($0.name) || $0.id == favouritesListID
    }
    guard !favourites.isEmpty else {
      return snapshot
    }

    var snapshot = snapshot
    let favouriteListIDs = Set(favourites.map(\.id))
    var canonicalList = favourites.max {
      if $0.updatedAt != $1.updatedAt {
        return $0.updatedAt < $1.updatedAt
      }
      return $0.id < $1.id
    } ?? favourites[0]
    canonicalList.id = favouritesListID
    canonicalList.name = "Favourites"
    canonicalList.createdAt = favourites.map(\.createdAt).min() ?? canonicalList.createdAt
    canonicalList.updatedAt = favourites.map(\.updatedAt).max() ?? canonicalList.updatedAt
    canonicalList.isPinned = false
    canonicalList.pinnedAt = nil
    canonicalList.position = 0

    var favouriteEntriesByCardID: [CardRecord.ID: CardCollectionEntryRecord] = [:]
    for entry in snapshot.listSnapshot.entries where favouriteListIDs.contains(entry.listID) {
      if let current = favouriteEntriesByCardID[entry.cardID],
        current.updatedAt >= entry.updatedAt
      {
        continue
      }
      var canonicalEntry = entry
      canonicalEntry.id = favouriteEntryID(cardID: entry.cardID)
      canonicalEntry.listID = favouritesListID
      canonicalEntry.zone = .mainboard
      canonicalEntry.categoryID = nil
      canonicalEntry.quantity = 1
      canonicalEntry.card = nil
      favouriteEntriesByCardID[entry.cardID] = canonicalEntry
    }
    let favouriteEntries = favouriteEntriesByCardID.values
      .sorted { $0.cardID < $1.cardID }
      .enumerated()
      .map { position, entry in
        var entry = entry
        entry.position = position
        return entry
      }
    canonicalList.entryCount = favouriteEntries.count

    snapshot.listSnapshot.lists =
      snapshot.listSnapshot.lists.filter { !favouriteListIDs.contains($0.id) }
      + [canonicalList]
    snapshot.listSnapshot.categories.removeAll {
      favouriteListIDs.contains($0.listID)
    }
    snapshot.listSnapshot.entries =
      snapshot.listSnapshot.entries.filter { !favouriteListIDs.contains($0.listID) }
      + favouriteEntries
    snapshot.deletedLists.removeAll {
      favouriteListIDs.contains($0.id) || $0.id == favouritesListID
    }
    snapshot.deletedEntities.removeAll {
      $0.entityType == .cardCollection
        && (favouriteListIDs.contains($0.recordID) || $0.recordID == favouritesListID)
    }
    return snapshot
  }
}
