import Foundation

// Label definitions (`card_labels`) and their per-entry assignments (`card_list_entries.label_ids`).
// Definitions mirror `CardCollectionCategoryRecord` CRUD; assignments mirror the secondary-category
// serialized-id-list writes. Every mutation stamps the monotonic sync clock and records a ledger
// row, exactly like the list/category/entry mutations, so labels sync and merge robustly.
extension CardDatabase {

  /// The column list every `card_labels` read selects, kept in one place so the fixed-index
  /// `readCardLabel` mapper and every SELECT stay in lockstep. `updated_at` is read via COALESCE so
  /// the sync-visible timestamp (advanced by the trigger) is the one that surfaces.
  static let cardLabelColumns =
    "id, list_id, name, color, position, created_at, COALESCE(sync_updated_at, updated_at)"

  // MARK: - Reads

  func readCardLabel(from statement: SQLiteStatement) -> CardLabelRecord {
    CardLabelRecord(
      id: statement.string(at: 0) ?? "",
      listID: statement.string(at: 1),
      name: statement.string(at: 2) ?? "",
      color: LabelColor(token: statement.string(at: 3)),
      position: statement.int(at: 4) ?? 0,
      createdAt: Self.parseListDate(statement.string(at: 5)),
      updatedAt: Self.parseListDate(statement.string(at: 6))
    )
  }

  func cardLabelUnlocked(id: String) throws -> CardLabelRecord? {
    let statement = try database.prepare(
      "SELECT \(Self.cardLabelColumns) FROM card_labels WHERE id = ? LIMIT 1")
    try statement.bind(id, at: 1)
    guard try statement.step() else { return nil }
    return readCardLabel(from: statement)
  }

  /// Every label, globals first then per-list, each block ordered by `position`.
  func cardLabelsUnlocked() throws -> [CardLabelRecord] {
    let statement = try database.prepare(
      """
      SELECT \(Self.cardLabelColumns) FROM card_labels
      ORDER BY (list_id IS NOT NULL) ASC, list_id ASC, position ASC, created_at ASC, id ASC
      """)
    var labels: [CardLabelRecord] = []
    while try statement.step() { labels.append(readCardLabel(from: statement)) }
    return labels
  }

  /// The labels usable inside a given collection: every global label plus that list's own labels.
  func applicableCardLabelsUnlocked(forListID listID: String) throws -> [CardLabelRecord] {
    let statement = try database.prepare(
      """
      SELECT \(Self.cardLabelColumns) FROM card_labels
      WHERE list_id IS NULL OR list_id = ?
      ORDER BY (list_id IS NOT NULL) ASC, position ASC, created_at ASC, id ASC
      """)
    try statement.bind(listID, at: 1)
    var labels: [CardLabelRecord] = []
    while try statement.step() { labels.append(readCardLabel(from: statement)) }
    return labels
  }

  public func cardLabels() throws -> [CardLabelRecord] {
    try withDatabaseLock { try cardLabelsUnlocked() }
  }

  public func applicableCardLabels(forListID listID: String) throws -> [CardLabelRecord] {
    try withDatabaseLock { try applicableCardLabelsUnlocked(forListID: listID) }
  }

  public func cardLabel(id: String) throws -> CardLabelRecord? {
    try withDatabaseLock { try cardLabelUnlocked(id: id) }
  }

  // MARK: - Definition CRUD

  @discardableResult
  public func createCardLabel(
    named name: String,
    color: LabelColor,
    listID: String? = nil,
    now: Date = Date()
  ) throws -> CardLabelRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else { throw CardCollectionDatabaseError.emptyName }
    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      if let listID, try cardCollectionUnlocked(id: listID) == nil {
        throw CardCollectionDatabaseError.listNotFound
      }
      let id = UUID().uuidString.lowercased()
      let date = Self.formattedListDate(now)
      let position = try nextCardLabelPositionUnlocked(listID: listID)
      try database.transaction {
        try insertCardLabelRowUnlocked(
          id: id, listID: listID, name: normalizedName, color: color,
          position: position, createdAt: date, updatedAt: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.createLabel, entityType: .cardLabel,
          entityID: id, listID: listID, summary: normalizedName, date: now)
      }
      guard let label = try cardLabelUnlocked(id: id) else {
        throw CardCollectionDatabaseError.labelNotFound
      }
      return label
    }
  }

  @discardableResult
  public func updateCardLabel(
    id: String,
    name: String? = nil,
    color: LabelColor? = nil,
    now: Date = Date()
  ) throws -> CardLabelRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let label = try cardLabelUnlocked(id: id) else {
        throw CardCollectionDatabaseError.labelNotFound
      }
      let newName = name.map(Self.normalizedListName) ?? label.name
      guard !newName.isEmpty else { throw CardCollectionDatabaseError.emptyName }
      let newColor = color ?? label.color
      let date = Self.formattedListDate(now)
      try database.transaction {
        let update = try database.prepare(
          "UPDATE card_labels SET name = ?, color = ?, updated_at = ? WHERE id = ?")
        try update.bind(newName, at: 1)
        try update.bind(newColor.rawValue, at: 2)
        try update.bind(date, at: 3)
        try update.bind(id, at: 4)
        try update.step()
        try recordChangeUnlocked(
          action: ChangeLogAction.updateLabel, entityType: .cardLabel,
          entityID: id, listID: label.listID, summary: newName, date: now)
      }
      guard let updated = try cardLabelUnlocked(id: id) else {
        throw CardCollectionDatabaseError.labelNotFound
      }
      return updated
    }
  }

  /// Promotes a list-local label to global (instance-wide). A no-op if it is already global.
  @discardableResult
  public func exportCardLabelToGlobal(id: String, now: Date = Date()) throws -> CardLabelRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let label = try cardLabelUnlocked(id: id) else {
        throw CardCollectionDatabaseError.labelNotFound
      }
      guard label.listID != nil else { return label }
      let date = Self.formattedListDate(now)
      try database.transaction {
        let update = try database.prepare(
          "UPDATE card_labels SET list_id = NULL, updated_at = ? WHERE id = ?")
        try update.bind(date, at: 1)
        try update.bind(id, at: 2)
        try update.step()
        try recordChangeUnlocked(
          action: ChangeLogAction.exportLabel, entityType: .cardLabel,
          entityID: id, listID: nil, summary: label.name, date: now)
      }
      guard let updated = try cardLabelUnlocked(id: id) else {
        throw CardCollectionDatabaseError.labelNotFound
      }
      return updated
    }
  }

  public func deleteCardLabel(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let label = try cardLabelUnlocked(id: id) else {
        throw CardCollectionDatabaseError.labelNotFound
      }
      let date = Self.formattedListDate(now)
      try database.transaction {
        // Drop the deleted label from every entry that carried it — a global label can be attached
        // to entries in any list, so this is unscoped (unlike category strip). `%|id|%` matches any
        // position in the `|id|id|` list.
        try stripCardLabelFromEntriesUnlocked(id, date: date)
        let delete = try database.prepare("DELETE FROM card_labels WHERE id = ?")
        try delete.bind(id, at: 1)
        try delete.step()
        try insertSyncTombstoneUnlocked(entityType: .cardLabel, recordID: id, deletedAt: now)
        try recordChangeUnlocked(
          action: ChangeLogAction.deleteLabel, entityType: .cardLabel,
          entityID: id, listID: label.listID, summary: label.name, date: now)
      }
    }
  }

  // MARK: - Assignments (per entry)

  @discardableResult
  public func toggleCardCollectionEntryLabel(
    entryID: String,
    labelID: String,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: entryID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      try validateLabelApplicableUnlocked(labelID: labelID, forEntryListID: entry.listID)
      if entry.labelIDs.contains(labelID) {
        return try writeCardLabelsUnlocked(
          entryID: entryID, listID: entry.listID,
          labelIDs: entry.labelIDs.filter { $0 != labelID },
          changeAction: ChangeLogAction.removeLabel, changeLabelID: labelID, now: now)
      } else {
        return try writeCardLabelsUnlocked(
          entryID: entryID, listID: entry.listID,
          labelIDs: entry.labelIDs + [labelID],
          changeAction: ChangeLogAction.addLabel, changeLabelID: labelID, now: now)
      }
    }
  }

  @discardableResult
  public func addCardCollectionEntryLabel(
    entryID: String,
    labelID: String,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: entryID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      try validateLabelApplicableUnlocked(labelID: labelID, forEntryListID: entry.listID)
      guard !entry.labelIDs.contains(labelID) else { return try hydratedEntryUnlocked(entryID) }
      return try writeCardLabelsUnlocked(
        entryID: entryID, listID: entry.listID, labelIDs: entry.labelIDs + [labelID],
        changeAction: ChangeLogAction.addLabel, changeLabelID: labelID, now: now)
    }
  }

  @discardableResult
  public func removeCardCollectionEntryLabel(
    entryID: String,
    labelID: String,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: entryID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      guard entry.labelIDs.contains(labelID) else { return try hydratedEntryUnlocked(entryID) }
      return try writeCardLabelsUnlocked(
        entryID: entryID, listID: entry.listID, labelIDs: entry.labelIDs.filter { $0 != labelID },
        changeAction: ChangeLogAction.removeLabel, changeLabelID: labelID, now: now)
    }
  }

  // MARK: - Search resolution

  /// Resolves a user-typed label name to matching label ids. Matching is separator-insensitive so
  /// `label:on-the-way`, `label:"on the way"`, and `label:ontheway` all hit "On the way". When
  /// `listID` is given (within-collection search) only global + that list's labels are considered;
  /// when nil (cross-list dashboard) any label with the name matches.
  func cardLabelIDsUnlocked(matchingName name: String, listID: String?) throws -> [String] {
    let needle = Self.labelSearchKey(name)
    guard !needle.isEmpty else { return [] }
    let statement: SQLiteStatement
    if let listID {
      statement = try database.prepare(
        "SELECT id, name FROM card_labels WHERE list_id IS NULL OR list_id = ?")
      try statement.bind(listID, at: 1)
    } else {
      statement = try database.prepare("SELECT id, name FROM card_labels")
    }
    var ids: [String] = []
    while try statement.step() {
      guard let id = statement.string(at: 0), let labelName = statement.string(at: 1) else { continue }
      if Self.labelSearchKey(labelName) == needle { ids.append(id) }
    }
    return ids
  }

  /// A separator- and case-insensitive key for matching a typed label term against a label name.
  static func labelSearchKey(_ value: String) -> String {
    value.normalizedSearchKey
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "_", with: "")
  }

  // MARK: - Default seeding

  /// Seeds the built-in default labels once per instance. Global, fixed-id rows stamped with an
  /// epoch timestamp so independent per-device seeding unions to one set and any user edit/delete
  /// always wins last-writer-wins. Gated by a local `sync_metadata` flag so a user-deleted default
  /// is not resurrected on the next launch.
  public func ensureDefaultLabelsSeeded(seededAt: Date = Date(timeIntervalSince1970: 0)) throws {
    try withDatabaseLock { try ensureDefaultLabelsSeededUnlocked(seededAt: seededAt) }
  }

  func ensureDefaultLabelsSeededUnlocked(seededAt: Date = Date(timeIntervalSince1970: 0)) throws {
    guard try !didSeedDefaultLabelsUnlocked() else { return }
    let date = Self.formattedListDate(seededAt)
    try database.transaction {
      for label in CardLabelRecord.defaultLabels(seededAt: seededAt) {
        try insertCardLabelRowUnlocked(
          insertVerb: "INSERT OR IGNORE",
          id: label.id, listID: label.listID, name: label.name, color: label.color,
          position: label.position, createdAt: date, updatedAt: date)
      }
      try setDidSeedDefaultLabelsUnlocked()
    }
  }

  // MARK: - Shared helpers

  /// Inserts one `card_labels` row. Shared by create, seeding (`INSERT OR IGNORE`) and the
  /// sync-restore apply path (plain `INSERT` after a full delete).
  func insertCardLabelRowUnlocked(
    insertVerb: String = "INSERT",
    id: String,
    listID: String?,
    name: String,
    color: LabelColor,
    position: Int,
    createdAt: String,
    updatedAt: String
  ) throws {
    let insert = try database.prepare(
      """
      \(insertVerb) INTO card_labels (id, list_id, name, color, position, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """)
    try insert.bind(id, at: 1)
    try insert.bind(listID, at: 2)
    try insert.bind(name, at: 3)
    try insert.bind(color.rawValue, at: 4)
    try insert.bind(position, at: 5)
    try insert.bind(createdAt, at: 6)
    try insert.bind(updatedAt, at: 7)
    try insert.step()
  }

  private func nextCardLabelPositionUnlocked(listID: String?) throws -> Int {
    let statement = try database.prepare(
      "SELECT COALESCE(MAX(position), -1) + 1 FROM card_labels WHERE list_id IS ?")
    try statement.bind(listID, at: 1)
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  private func validateLabelApplicableUnlocked(labelID: String, forEntryListID entryListID: String) throws {
    guard let label = try cardLabelUnlocked(id: labelID),
      label.listID == nil || label.listID == entryListID
    else {
      throw CardCollectionDatabaseError.labelNotFound
    }
  }

  private func writeCardLabelsUnlocked(
    entryID: String,
    listID: String,
    labelIDs: [String],
    changeAction: String,
    changeLabelID: String,
    now: Date
  ) throws -> CardCollectionEntryRecord {
    let date = Self.formattedListDate(now)
    try database.transaction {
      let update = try database.prepare(
        "UPDATE card_list_entries SET label_ids = ?, updated_at = ? WHERE id = ?")
      try update.bind(Self.serializedList(labelIDs), at: 1)
      try update.bind(date, at: 2)
      try update.bind(entryID, at: 3)
      try update.step()
      try touchCardCollectionUnlocked(id: listID, date: date)
      try recordChangeUnlocked(
        action: changeAction, entityType: .cardCollectionEntry,
        entityID: entryID, listID: listID, summary: changeLabelID, date: now)
    }
    return try hydratedEntryUnlocked(entryID)
  }

  private func hydratedEntryUnlocked(_ entryID: String) throws -> CardCollectionEntryRecord {
    guard var entry = try cardCollectionEntryUnlocked(id: entryID) else {
      throw CardCollectionDatabaseError.entryNotFound
    }
    entry.card = try card(id: entry.cardID)
    return entry
  }

  /// Removes `labelID` from every entry's `label_ids`. Runs inside an open transaction. Stored as
  /// `|id1|id2|`, so `%|id|%` finds any entry referencing the label; bumping `updated_at` lets the
  /// removal sync.
  private func stripCardLabelFromEntriesUnlocked(_ labelID: String, date: String) throws {
    let select = try database.prepare(
      "SELECT id, label_ids FROM card_list_entries WHERE label_ids LIKE ?")
    try select.bind("%|\(labelID)|%", at: 1)
    var updates: [(id: String, remaining: [String])] = []
    while try select.step() {
      guard let entryID = select.string(at: 0) else { continue }
      let remaining = Self.deserializedList(select.string(at: 1)).filter { $0 != labelID }
      updates.append((entryID, remaining))
    }
    guard !updates.isEmpty else { return }
    let update = try database.prepare(
      "UPDATE card_list_entries SET label_ids = ?, updated_at = ? WHERE id = ?")
    for change in updates {
      try update.bind(Self.serializedList(change.remaining), at: 1)
      try update.bind(date, at: 2)
      try update.bind(change.id, at: 3)
      try update.step()
      try update.reset()
    }
  }

  private static let didSeedDefaultLabelsKey = "didSeedDefaultLabels"

  private func didSeedDefaultLabelsUnlocked() throws -> Bool {
    let statement = try database.prepare("SELECT value_text FROM sync_metadata WHERE key = ?")
    try statement.bind(Self.didSeedDefaultLabelsKey, at: 1)
    guard try statement.step() else { return false }
    return statement.string(at: 0) == "1"
  }

  private func setDidSeedDefaultLabelsUnlocked() throws {
    let statement = try database.prepare(
      """
      INSERT INTO sync_metadata (key, value_text, value_data) VALUES (?, '1', NULL)
      ON CONFLICT(key) DO UPDATE SET value_text = '1', value_data = NULL
      """)
    try statement.bind(Self.didSeedDefaultLabelsKey, at: 1)
    try statement.step()
  }
}
