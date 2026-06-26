import Foundation

public enum GrimoraCloudKitSchema {
  public static let zoneName = "GrimoraSync"
  public static let bootstrapRecordPrefix = "schema-bootstrap-"

  public enum RecordType {
    public static let legacyLibraryIdentity = "LibraryIdentity"
    public static let legacyDeviceSnapshot = "DeviceSnapshot"
    public static let metadata = "GrimoraSyncMetadata"
    public static let preferences = "GrimoraUserPreferences"
    public static let cardCollection = "GrimoraCardList"
    public static let cardCollectionCategory = "GrimoraCardListCategory"
    public static let cardCollectionEntry = "GrimoraCardListEntry"
    public static let recoveryRevision = "GrimoraRecoveryRevision"
  }

  public enum Field {
    public static let payload = "payload"
    public static let capturedAt = "capturedAt"
    public static let updatedAt = "updatedAt"
    public static let deletedAt = "deletedAt"
    public static let entityID = "entityID"
    public static let sourceDeviceID = "sourceDeviceID"
  }

  public static let entityFields = [
    Field.payload,
    Field.entityID,
    Field.updatedAt,
    Field.deletedAt,
    Field.sourceDeviceID,
  ]

  public static let historicalFields = [
    Field.payload,
    Field.capturedAt,
  ]

  public static let entityRecordTypes = [
    RecordType.metadata,
    RecordType.preferences,
    RecordType.cardCollection,
    RecordType.cardCollectionCategory,
    RecordType.cardCollectionEntry,
  ]

  public static let legacyRecordTypes = [
    RecordType.recoveryRevision,
    RecordType.legacyLibraryIdentity,
    RecordType.legacyDeviceSnapshot,
  ]

  public static let allRecordTypes = entityRecordTypes + legacyRecordTypes

  public static let fieldsByRecordType: [String: [String]] = Dictionary(
    uniqueKeysWithValues:
      entityRecordTypes.map { ($0, entityFields) }
      + legacyRecordTypes.map { ($0, historicalFields) }
  )

  public static let allFieldNames = Array(
    Set(fieldsByRecordType.values.flatMap { $0 })
  ).sorted()

  public static func requiredFields(for recordType: String) -> [String] {
    fieldsByRecordType[recordType] ?? []
  }
}
