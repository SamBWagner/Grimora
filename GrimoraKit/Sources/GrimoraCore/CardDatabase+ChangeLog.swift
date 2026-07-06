import Foundation

// MARK: - Append-only change ledger
//
// A git-style history of user actions. Rows are immutable and globally unique, so they sync as a
// pure union (INSERT OR IGNORE) and never conflict. Writes happen at the mutation site via
// `recordChangeUnlocked`, using the same monotonic instant the edit was stamped with. Sync-apply
// (restore) never routes through the mutation functions, so pulling remote data does not manufacture
// spurious ledger rows.
extension CardDatabase {
  private static let ledgerDeviceIDMetadataKey = "ledgerDeviceID"

  /// Records one immutable ledger row. Must be called inside `withDatabaseLock` (typically inside
  /// the same transaction as the mutation it describes). `date` is the monotonic instant the edit
  /// was stamped with (from `issueSyncTimestampUnlocked`).
  func recordChangeUnlocked(
    action: String,
    entityType: SyncEntityType,
    entityID: String,
    listID: String?,
    summary: String? = nil,
    date: Date
  ) throws {
    let statement = try database.prepare(
      """
      INSERT INTO change_log (id, recorded_at, device_id, action, entity_type, entity_id, list_id, summary)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """)
    try statement.bind(UUID().uuidString.lowercased(), at: 1)
    try statement.bind(Self.formattedListDate(date), at: 2)
    try statement.bind(try ledgerDeviceIDUnlocked(), at: 3)
    try statement.bind(action, at: 4)
    try statement.bind(entityType.rawValue, at: 5)
    try statement.bind(entityID, at: 6)
    try statement.bind(listID, at: 7)
    try statement.bind(summary, at: 8)
    try statement.step()
  }

  /// All ledger rows, newest first. Used to build the sync snapshot and (later) a history view.
  func changeLogEntriesUnlocked(limit: Int? = nil) throws -> [ChangeLogEntry] {
    let sql =
      """
      SELECT id, recorded_at, device_id, action, entity_type, entity_id, list_id, summary
      FROM change_log
      ORDER BY recorded_at DESC, id DESC
      """ + (limit.map { " LIMIT \($0)" } ?? "")
    let statement = try database.prepare(sql)
    var entries: [ChangeLogEntry] = []
    while try statement.step() {
      guard let entry = Self.readChangeLogEntry(from: statement) else { continue }
      entries.append(entry)
    }
    return entries
  }

  public func changeLogEntries(limit: Int? = nil) throws -> [ChangeLogEntry] {
    try withDatabaseLock {
      try changeLogEntriesUnlocked(limit: limit)
    }
  }

  /// Unions incoming ledger rows into the local log. Rows are immutable, so an id we already hold
  /// is ignored — this can never overwrite or revert anything.
  func mergeChangeLogUnlocked(_ entries: [ChangeLogEntry]) throws {
    guard !entries.isEmpty else { return }
    let statement = try database.prepare(
      """
      INSERT OR IGNORE INTO change_log
        (id, recorded_at, device_id, action, entity_type, entity_id, list_id, summary)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """)
    for entry in entries {
      try statement.bind(entry.id, at: 1)
      try statement.bind(Self.formattedListDate(entry.recordedAt), at: 2)
      try statement.bind(entry.deviceID, at: 3)
      try statement.bind(entry.action, at: 4)
      try statement.bind(entry.entityType.rawValue, at: 5)
      try statement.bind(entry.entityID, at: 6)
      try statement.bind(entry.listID, at: 7)
      try statement.bind(entry.summary, at: 8)
      try statement.step()
      try statement.reset()
    }
  }

  public func mergeChangeLog(_ entries: [ChangeLogEntry]) throws {
    try withDatabaseLock {
      try database.transaction {
        try mergeChangeLogUnlocked(entries)
      }
    }
  }

  /// A stable per-device provenance token for ledger rows, generated and persisted on first use.
  private func ledgerDeviceIDUnlocked() throws -> String {
    let selectStatement = try database.prepare("SELECT value_text FROM sync_metadata WHERE key = ?")
    try selectStatement.bind(Self.ledgerDeviceIDMetadataKey, at: 1)
    if try selectStatement.step(), let existing = selectStatement.string(at: 0), !existing.isEmpty {
      return existing
    }
    let generated = UUID().uuidString.lowercased()
    let insertStatement = try database.prepare(
      """
      INSERT INTO sync_metadata (key, value_text, value_data) VALUES (?, ?, NULL)
      ON CONFLICT(key) DO UPDATE SET value_text = excluded.value_text, value_data = NULL
      """)
    try insertStatement.bind(Self.ledgerDeviceIDMetadataKey, at: 1)
    try insertStatement.bind(generated, at: 2)
    try insertStatement.step()
    return generated
  }

  private static func readChangeLogEntry(from statement: SQLiteStatement) -> ChangeLogEntry? {
    guard let id = statement.string(at: 0),
      let action = statement.string(at: 3),
      let entityTypeRaw = statement.string(at: 4),
      let entityType = SyncEntityType(rawValue: entityTypeRaw),
      let entityID = statement.string(at: 5)
    else {
      return nil
    }
    return ChangeLogEntry(
      id: id,
      recordedAt: parseListDate(statement.string(at: 1)),
      deviceID: statement.string(at: 2) ?? "unknown",
      action: action,
      entityType: entityType,
      entityID: entityID,
      listID: statement.string(at: 6),
      summary: statement.string(at: 7)
    )
  }
}
