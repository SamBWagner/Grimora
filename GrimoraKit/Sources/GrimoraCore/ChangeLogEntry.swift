import Foundation

/// One immutable entry in the append-only change ledger — a git-style record of a single user
/// action, stamped at the point of interaction. Entries are never mutated after creation, so they
/// sync as a pure union across devices (globally-unique `id`, merged with INSERT OR IGNORE) and
/// can never cause a revert. The ledger is history/observability/undo substrate; it is NOT the
/// sync merge authority (that is the logical clock on each entity's `updatedAt`).
public struct ChangeLogEntry: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  /// When the action happened, from the same monotonic sync clock that stamps entity edits.
  public var recordedAt: Date
  /// Which device performed the action (stable per-device provenance token).
  public var deviceID: String
  /// A short machine-readable verb, e.g. "addCard", "setQuantity", "changePrint", "renameList".
  public var action: String
  /// The kind of entity the action touched.
  public var entityType: SyncEntityType
  /// The id of the entity the action touched (entry / list / category id).
  public var entityID: String
  /// The collection this change belongs to, when applicable (nil for library-level actions).
  public var listID: String?
  /// Optional short human-readable description, e.g. "Set quantity to 3" or a card id.
  public var summary: String?

  public init(
    id: String = UUID().uuidString.lowercased(),
    recordedAt: Date,
    deviceID: String,
    action: String,
    entityType: SyncEntityType,
    entityID: String,
    listID: String? = nil,
    summary: String? = nil
  ) {
    self.id = id
    self.recordedAt = recordedAt
    self.deviceID = deviceID
    self.action = action
    self.entityType = entityType
    self.entityID = entityID
    self.listID = listID
    self.summary = summary
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case recordedAt
    case deviceID
    case action
    case entityType
    case entityID
    case listID
    case summary
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    recordedAt = try container.decode(Date.self, forKey: .recordedAt)
    deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? "unknown"
    action = try container.decode(String.self, forKey: .action)
    entityType = try container.decodeIfPresent(SyncEntityType.self, forKey: .entityType) ?? .cardCollectionEntry
    entityID = try container.decode(String.self, forKey: .entityID)
    listID = try container.decodeIfPresent(String.self, forKey: .listID)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
  }
}

/// Common `ChangeLogEntry.action` verbs. Kept as plain strings so new actions never break decoding
/// of older rows.
public enum ChangeLogAction {
  public static let addCard = "addCard"
  public static let setQuantity = "setQuantity"
  public static let removeCard = "removeCard"
  public static let setFinish = "setFinish"
  public static let changePrint = "changePrint"
  public static let moveZone = "moveZone"
  public static let moveCategory = "moveCategory"
  public static let setCategory = "setCategory"
  public static let addTag = "addTag"
  public static let removeTag = "removeTag"
  public static let createList = "createList"
  public static let renameList = "renameList"
  public static let deleteList = "deleteList"
  public static let setListDescription = "setListDescription"
  public static let setListOption = "setListOption"
  public static let moveList = "moveList"
  public static let setRuleset = "setRuleset"
  public static let createCategory = "createCategory"
  public static let renameCategory = "renameCategory"
  public static let deleteCategory = "deleteCategory"
  public static let reorderCategory = "reorderCategory"
}
