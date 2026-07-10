import Foundation

extension CardDatabase {
  public func cardCollections() throws -> [CardCollectionRecord] {
    try withDatabaseLock {
      try cardCollectionsUnlocked()
    }
  }

  public func cardCollection(id: String) throws -> CardCollectionRecord? {
    try withDatabaseLock {
      try cardCollectionUnlocked(id: id)
    }
  }

  public func cardCollectionEntries(forListID listID: String) throws -> [CardCollectionEntryRecord] {
    try withDatabaseLock {
      try cardCollectionEntriesUnlocked(forListID: listID)
    }
  }

  public func searchCardCollectionEntries(
    forListID listID: String,
    text: String
  ) throws -> CardCollectionEntrySearchResponse {
    try withDatabaseLock {
      let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else {
        return .results(try cardCollectionEntriesUnlocked(forListID: listID))
      }

      let plan: SearchQueryPlan
      switch SearchQuery.compile(query) {
      case .success(let compiledPlan):
        plan = compiledPlan
      case .failure(let reason):
        return .unsupported(reason)
      }

      var entries = try cardCollectionEntriesUnlocked(
        forListID: listID,
        cardWhereSQL: plan.whereSQL,
        cardWhereBindings: plan.bindings
      )

      if plan.hasPostFilters {
        entries = entries.filter { entry in
          guard let card = entry.card else {
            return false
          }
          return plan.postFilters.allSatisfy { $0.matches(card) }
        }
      }

      return .results(entries)
    }
  }

  /// Searches every list at once, compiling the Scryfall query a single time and returning the
  /// lists whose cards match together with the matching entries. Returns `.results([])` for an
  /// empty query so callers can treat "no filter" as "no matches surfaced".
  public func searchAllCardCollectionEntries(text: String) throws -> CrossListSearchResponse {
    try withDatabaseLock {
      let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else {
        return .results([])
      }

      let plan: SearchQueryPlan
      switch SearchQuery.compile(query) {
      case .success(let compiledPlan):
        plan = compiledPlan
      case .failure(let reason):
        return .unsupported(reason)
      }

      var entries = try allMatchingCardCollectionEntriesUnlocked(
        cardWhereSQL: plan.whereSQL,
        cardWhereBindings: plan.bindings
      )

      if plan.hasPostFilters {
        entries = entries.filter { entry in
          guard let card = entry.card else {
            return false
          }
          return plan.postFilters.allSatisfy { $0.matches(card) }
        }
      }

      return .results(Self.groupedCrossListMatches(from: entries))
    }
  }

  /// Fetches the entries across all lists whose card matches the compiled query, then batch-hydrates
  /// every distinct card in a handful of queries (via `cardsByID(forIDs:)`) to avoid per-entry lookups
  /// over large libraries.
  func allMatchingCardCollectionEntriesUnlocked(
    cardWhereSQL: String?,
    cardWhereBindings: [SearchQuery.SQLBinding] = []
  ) throws -> [CardCollectionEntryRecord] {
    let searchClause = cardWhereSQL.map { whereSQL in
      """
      AND card_id IN (
          SELECT id
          FROM cards
          WHERE \(whereSQL)
      )
      """
    } ?? ""
    let statement = try database.prepare(
      """
      SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at,
          COALESCE(sync_updated_at, updated_at), selected_finish, secondary_category_ids
      FROM card_list_entries
      WHERE 1 = 1
      \(searchClause)
      ORDER BY list_id ASC, zone ASC, position ASC, created_at ASC, id ASC
      """)
    for (index, binding) in cardWhereBindings.enumerated() {
      try binding.apply(to: statement, index: Int32(index + 1))
    }

    var entries: [CardCollectionEntryRecord] = []
    while try statement.step() {
      entries.append(readCardCollectionEntry(from: statement))
    }
    guard !entries.isEmpty else {
      return entries
    }

    let cardsByID = try cardsByID(forIDs: entries.map(\.cardID))
    for index in entries.indices {
      entries[index].card = cardsByID[entries[index].cardID]
    }
    return entries
  }

  /// Groups matching entries into per-list matches, preserving first-seen list order.
  static func groupedCrossListMatches(
    from entries: [CardCollectionEntryRecord]
  ) -> [CrossListSearchMatch] {
    var order: [String] = []
    var grouped: [String: [CardCollectionEntryRecord]] = [:]
    for entry in entries {
      if grouped[entry.listID] == nil {
        order.append(entry.listID)
      }
      grouped[entry.listID, default: []].append(entry)
    }
    return order.map { CrossListSearchMatch(listID: $0, entries: grouped[$0] ?? []) }
  }

  func cardCollectionEntriesUnlocked(
    forListID listID: String,
    cardWhereSQL: String? = nil,
    cardWhereBindings: [SearchQuery.SQLBinding] = []
  ) throws -> [CardCollectionEntryRecord] {
    let searchClause = cardWhereSQL.map { whereSQL in
      """
      AND card_id IN (
          SELECT id
          FROM cards
          WHERE \(whereSQL)
      )
      """
    } ?? ""
    let statement = try database.prepare(
      """
      SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at,
          COALESCE(sync_updated_at, updated_at), selected_finish, secondary_category_ids
      FROM card_list_entries
      WHERE list_id = ?
      \(searchClause)
      ORDER BY zone ASC, position ASC, created_at ASC, id ASC
      """)
    try statement.bind(listID, at: 1)
    for (index, binding) in cardWhereBindings.enumerated() {
      try binding.apply(to: statement, index: Int32(index + 2))
    }

    var entries: [CardCollectionEntryRecord] = []
    while try statement.step() {
      entries.append(readCardCollectionEntry(from: statement))
    }
    guard !entries.isEmpty else {
      return entries
    }

    // Batch-hydrate every card in one set of queries rather than one (plus faces) per entry. The
    // map is keyed by card id, so duplicate cardIDs (e.g. the same card in different zones) each
    // receive their card, and a missing card leaves `entry.card == nil` exactly like `card(id:)`.
    // Entry order is preserved from the ORDER BY above, never from the cards fetch.
    let cardsByID = try cardsByID(forIDs: entries.map(\.cardID))
    for index in entries.indices {
      entries[index].card = cardsByID[entries[index].cardID]
    }
    return entries
  }

  public func cardCollectionCategories(forListID listID: String) throws -> [CardCollectionCategoryRecord] {
    try withDatabaseLock {
      try cardCollectionCategoriesUnlocked(forListID: listID)
    }
  }

  public func cardCollectionLibrarySnapshot() throws -> CardCollectionLibrarySnapshot {
    try withDatabaseLock {
      try cardCollectionLibrarySnapshotUnlocked()
    }
  }

  public func restoreCardCollectionLibrarySnapshot(_ snapshot: CardCollectionLibrarySnapshot) throws {
    try withDatabaseLock {
      try database.transaction {
        try restoreCardCollectionLibrarySnapshotUnlocked(snapshot)
      }
    }
  }

  func cardCollectionLibrarySnapshotUnlocked() throws -> CardCollectionLibrarySnapshot {
    try CardCollectionLibrarySnapshot(
      lists: cardCollectionsUnlocked(),
      categories: cardCollectionCategoriesUnlocked(),
      entries: cardCollectionEntriesUnlocked()
    )
  }

  func restoreCardCollectionLibrarySnapshotUnlocked(_ snapshot: CardCollectionLibrarySnapshot) throws {
    try database.execute("DELETE FROM card_list_entries")
    try database.execute("DELETE FROM card_list_categories")
    try database.execute("DELETE FROM card_lists")

    let listInsert = try database.prepare(
      """
      INSERT INTO card_lists (
          id, name, ruleset, description_rtfd, description_plain_text, created_at, updated_at,
          is_pinned, pinned_at, position, shows_dashboard, dashboard_includes_lands,
          display_sort_mode, display_sort_direction, view_mode, shows_multi_category_cards
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """)
    for list in snapshot.lists {
      try listInsert.bind(list.id, at: 1)
      try listInsert.bind(list.name, at: 2)
      try listInsert.bind(list.ruleset.rawValue, at: 3)
      try listInsert.bind(list.descriptionRTFDData, at: 4)
      try listInsert.bind(list.descriptionPlainText, at: 5)
      try listInsert.bind(Self.formattedListDate(list.createdAt), at: 6)
      try listInsert.bind(Self.formattedListDate(list.updatedAt), at: 7)
      try listInsert.bind(list.isPinned, at: 8)
      try listInsert.bind(list.pinnedAt.map(Self.formattedListDate), at: 9)
      try listInsert.bind(list.position, at: 10)
      try listInsert.bind(list.showsDashboard, at: 11)
      try listInsert.bind(list.dashboardIncludesLands, at: 12)
      try listInsert.bind(list.displaySortMode?.rawValue, at: 13)
      try listInsert.bind(list.displaySortDirection.rawValue, at: 14)
      try listInsert.bind(list.viewMode.rawValue, at: 15)
      try listInsert.bind(list.showsMultiCategoryCards, at: 16)
      try listInsert.step()
      try listInsert.reset()
    }

    let categoryInsert = try database.prepare(
      """
      INSERT INTO card_list_categories (id, list_id, zone, name, position, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """)
    for category in snapshot.categories {
      try categoryInsert.bind(category.id, at: 1)
      try categoryInsert.bind(category.listID, at: 2)
      try categoryInsert.bind(category.zone.rawValue, at: 3)
      try categoryInsert.bind(category.name, at: 4)
      try categoryInsert.bind(category.position, at: 5)
      try categoryInsert.bind(Self.formattedListDate(category.createdAt), at: 6)
      try categoryInsert.bind(Self.formattedListDate(category.updatedAt), at: 7)
      try categoryInsert.step()
      try categoryInsert.reset()
    }

    let entryInsert = try database.prepare(
      """
      INSERT INTO card_list_entries (
          id, list_id, zone, category_id, card_id, position, quantity, created_at, updated_at,
          selected_finish, secondary_category_ids
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """)
    for entry in snapshot.entries {
      try entryInsert.bind(entry.id, at: 1)
      try entryInsert.bind(entry.listID, at: 2)
      try entryInsert.bind(entry.zone.rawValue, at: 3)
      try entryInsert.bind(entry.categoryID, at: 4)
      try entryInsert.bind(entry.cardID, at: 5)
      try entryInsert.bind(entry.position, at: 6)
      try entryInsert.bind(max(1, entry.quantity), at: 7)
      try entryInsert.bind(Self.formattedListDate(entry.createdAt), at: 8)
      try entryInsert.bind(Self.formattedListDate(entry.updatedAt), at: 9)
      try entryInsert.bind(entry.selectedFinish?.rawValue, at: 10)
      try entryInsert.bind(Self.serializedList(entry.secondaryCategoryIDs), at: 11)
      try entryInsert.step()
      try entryInsert.reset()
    }
  }

  @discardableResult
  public func createCardCollection(
    named name: String,
    ruleset: CardCollectionRuleset = .none,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardCollectionDatabaseError.emptyName
    }

    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let id = UUID().uuidString.lowercased()
      let date = Self.formattedListDate(now)
      let position = try nextCardCollectionPositionUnlocked(isPinned: false)
      let statement = try database.prepare(
        """
        INSERT INTO card_lists (id, name, ruleset, created_at, updated_at, position)
        VALUES (?, ?, ?, ?, ?, ?)
        """)
      try statement.bind(id, at: 1)
      try statement.bind(normalizedName, at: 2)
      try statement.bind(ruleset.rawValue, at: 3)
      try statement.bind(date, at: 4)
      try statement.bind(date, at: 5)
      try statement.bind(position, at: 6)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.createList,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: list.name,
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func renameCardCollection(id: String, to name: String, now: Date = Date()) throws -> CardCollectionRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardCollectionDatabaseError.emptyName
    }

    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET name = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(normalizedName, at: 1)
      try statement.bind(Self.formattedListDate(now), at: 2)
      try statement.bind(id, at: 3)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.renameList,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: normalizedName,
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func updateCardCollectionDescription(
    id: String,
    rtfdData: Data?,
    plainText: String,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET description_rtfd = ?, description_plain_text = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(rtfdData, at: 1)
      try statement.bind(plainText, at: 2)
      try statement.bind(Self.formattedListDate(now), at: 3)
      try statement.bind(id, at: 4)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      // Summary is intentionally omitted: the description text can be arbitrarily long and lives on
      // the entity itself, so keeping it out of the ledger avoids bloating every sync snapshot.
      try recordChangeUnlocked(
        action: ChangeLogAction.setListDescription,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func setCardCollectionDashboardVisibility(
    id: String,
    showsDashboard: Bool,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET shows_dashboard = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(showsDashboard, at: 1)
      try statement.bind(Self.formattedListDate(now), at: 2)
      try statement.bind(id, at: 3)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.setListOption,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: "showsDashboard=\(showsDashboard)",
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func setCardCollectionMultiCategoryVisibility(
    id: String,
    showsMultiCategoryCards: Bool,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET shows_multi_category_cards = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(showsMultiCategoryCards, at: 1)
      try statement.bind(Self.formattedListDate(now), at: 2)
      try statement.bind(id, at: 3)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.setListOption,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: "showsMultiCategoryCards=\(showsMultiCategoryCards)",
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func setCardCollectionDashboardIncludesLands(
    id: String,
    includesLands: Bool,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET dashboard_includes_lands = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(includesLands, at: 1)
      try statement.bind(Self.formattedListDate(now), at: 2)
      try statement.bind(id, at: 3)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.setListOption,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: "dashboardIncludesLands=\(includesLands)",
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func setCardCollectionDisplaySort(
    id: String,
    mode: SortMode?,
    direction: SearchSortDirection,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET display_sort_mode = ?, display_sort_direction = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(mode?.rawValue, at: 1)
      try statement.bind(direction.rawValue, at: 2)
      try statement.bind(Self.formattedListDate(now), at: 3)
      try statement.bind(id, at: 4)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.setListOption,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: "displaySort=\(mode?.rawValue ?? "default"):\(direction.rawValue)",
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func setCardCollectionViewMode(
    id: String,
    viewMode: CardCollectionViewMode,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET view_mode = ?, updated_at = ?
        WHERE id = ?
        """)
      try statement.bind(viewMode.rawValue, at: 1)
      try statement.bind(Self.formattedListDate(now), at: 2)
      try statement.bind(id, at: 3)
      try statement.step()

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.setListOption,
        entityType: .cardCollection,
        entityID: id,
        listID: id,
        summary: "viewMode=\(viewMode.rawValue)",
        date: now
      )
      return list
    }
  }

  @discardableResult
  public func setCardCollectionRuleset(
    id: String,
    ruleset: CardCollectionRuleset,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      let date = Self.formattedListDate(now)
      let statement = try database.prepare(
        """
        UPDATE card_lists
        SET ruleset = ?, updated_at = ?
        WHERE id = ?
        """)
      try database.transaction {
        try statement.bind(ruleset.rawValue, at: 1)
        try statement.bind(date, at: 2)
        try statement.bind(id, at: 3)
        try statement.step()

        try normalizeCardCollectionZonesUnlocked(listID: id, ruleset: ruleset, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.setRuleset,
          entityType: .cardCollection,
          entityID: id,
          listID: id,
          summary: ruleset.rawValue,
          date: now
        )
      }

      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      return list
    }
  }

  public func deleteCardCollection(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      try database.transaction {
        let statement = try database.prepare("DELETE FROM card_lists WHERE id = ?")
        try statement.bind(id, at: 1)
        try statement.step()
        try insertSyncTombstoneUnlocked(entityType: .cardCollection, recordID: id)
        try recordChangeUnlocked(
          action: ChangeLogAction.deleteList,
          entityType: .cardCollection,
          entityID: id,
          listID: id,
          date: now
        )
      }
    }
  }

  @discardableResult
  public func setCardCollectionPinned(
    id: String,
    isPinned: Bool,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try moveCardCollection(id: id, toPosition: 0, isPinned: isPinned, now: now)
  }

  @discardableResult
  public func moveCardCollection(
    id: String,
    toPosition requestedPosition: Int,
    isPinned requestedPinnedState: Bool? = nil,
    now: Date = Date()
  ) throws -> CardCollectionRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let list = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }

      let destinationIsPinned = requestedPinnedState ?? list.isPinned
      let date = Self.formattedListDate(now)
      var sourceLists = try cardCollectionsUnlocked(isPinned: list.isPinned, ordering: .storedPosition)
      var destinationLists = destinationIsPinned == list.isPinned
        ? sourceLists
        : try cardCollectionsUnlocked(isPinned: destinationIsPinned, ordering: .storedPosition)

      sourceLists.removeAll { $0.id == id }
      destinationLists.removeAll { $0.id == id }

      var movedList = list
      movedList.isPinned = destinationIsPinned
      movedList.pinnedAt = destinationIsPinned ? now : nil
      movedList.updatedAt = now

      let newIndex = max(0, min(requestedPosition, destinationLists.count))
      destinationLists.insert(movedList, at: newIndex)

      try database.transaction {
        if destinationIsPinned != list.isPinned {
          let statement = try database.prepare(
            """
            UPDATE card_lists
            SET is_pinned = ?, pinned_at = ?, updated_at = ?
            WHERE id = ?
            """)
          try statement.bind(destinationIsPinned, at: 1)
          try statement.bind(destinationIsPinned ? date : nil, at: 2)
          try statement.bind(date, at: 3)
          try statement.bind(id, at: 4)
          try statement.step()
        } else {
          try touchCardCollectionUnlocked(id: id, date: date)
        }

        if destinationIsPinned != list.isPinned {
          try updateCardCollectionPositionsUnlocked(sourceLists, date: date)
        }
        try updateCardCollectionPositionsUnlocked(destinationLists, date: date)

        // A reorder within a section records the new position; a pin-state flip (used by
        // `setCardCollectionPinned`, which routes here) records the pin instead.
        try recordChangeUnlocked(
          action: ChangeLogAction.moveList,
          entityType: .cardCollection,
          entityID: id,
          listID: id,
          summary: destinationIsPinned == list.isPinned
            ? "position=\(newIndex)"
            : (destinationIsPinned ? "pinned" : "unpinned"),
          date: now
        )
      }

      guard let moved = try cardCollectionUnlocked(id: id) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      return moved
    }
  }

  @discardableResult
  public func createCardCollectionCategory(
    inList listID: String,
    zone: CardCollectionZone = .mainboard,
    named name: String,
    now: Date = Date()
  ) throws -> CardCollectionCategoryRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardCollectionDatabaseError.emptyName
    }
    guard !Self.isImplicitCategoryName(normalizedName) else {
      throw CardCollectionDatabaseError.duplicateName
    }

    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let list = try cardCollectionUnlocked(id: listID) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      let zone = list.ruleset.normalizedZone(zone)
      guard try !cardCollectionCategoryNameExistsUnlocked(
        inList: listID,
        zone: zone,
        named: normalizedName,
        excluding: nil
      ) else {
        throw CardCollectionDatabaseError.duplicateName
      }

      let position: Int = try {
        let statement = try database.prepare(
          """
          SELECT COALESCE(MAX(position), -1) + 1
          FROM card_list_categories
          WHERE list_id = ? AND zone = ?
          """)
        try statement.bind(listID, at: 1)
        try statement.bind(zone.rawValue, at: 2)
        _ = try statement.step()
        return statement.int(at: 0) ?? 0
      }()
      let id = UUID().uuidString.lowercased()
      let date = Self.formattedListDate(now)

      try database.transaction {
        let insert = try database.prepare(
          """
          INSERT INTO card_list_categories (id, list_id, zone, name, position, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """)
        try insert.bind(id, at: 1)
        try insert.bind(listID, at: 2)
        try insert.bind(zone.rawValue, at: 3)
        try insert.bind(normalizedName, at: 4)
        try insert.bind(position, at: 5)
        try insert.bind(date, at: 6)
        try insert.bind(date, at: 7)
        try insert.step()

        try touchCardCollectionUnlocked(id: listID, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.createCategory,
          entityType: .cardCollectionCategory,
          entityID: id,
          listID: listID,
          summary: normalizedName,
          date: now
        )
      }

      guard let category = try cardCollectionCategoryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }
      return category
    }
  }

  @discardableResult
  public func renameCardCollectionCategory(
    id: String,
    to name: String,
    now: Date = Date()
  ) throws -> CardCollectionCategoryRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardCollectionDatabaseError.emptyName
    }
    guard !Self.isImplicitCategoryName(normalizedName) else {
      throw CardCollectionDatabaseError.duplicateName
    }

    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let category = try cardCollectionCategoryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }
      guard try !cardCollectionCategoryNameExistsUnlocked(
        inList: category.listID,
        zone: category.zone,
        named: normalizedName,
        excluding: id
      ) else {
        throw CardCollectionDatabaseError.duplicateName
      }

      let date = Self.formattedListDate(now)
      try database.transaction {
        let statement = try database.prepare(
          """
          UPDATE card_list_categories
          SET name = ?, updated_at = ?
          WHERE id = ?
          """)
        try statement.bind(normalizedName, at: 1)
        try statement.bind(date, at: 2)
        try statement.bind(id, at: 3)
        try statement.step()

        try touchCardCollectionUnlocked(id: category.listID, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.renameCategory,
          entityType: .cardCollectionCategory,
          entityID: id,
          listID: category.listID,
          summary: normalizedName,
          date: now
        )
      }

      guard let renamed = try cardCollectionCategoryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }
      return renamed
    }
  }

  public func deleteCardCollectionCategory(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let category = try cardCollectionCategoryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }

      let date = Self.formattedListDate(now)
      try database.transaction {
        let uncategorizeEntries = try database.prepare(
          """
          UPDATE card_list_entries
          SET category_id = NULL, updated_at = ?
          WHERE category_id = ?
          """)
        try uncategorizeEntries.bind(date, at: 1)
        try uncategorizeEntries.bind(id, at: 2)
        try uncategorizeEntries.step()

        // Also drop the deleted category from any entry that carried it as a secondary tag.
        // Secondary IDs are stored delimited as `|id1|id2|`, so `%|id|%` matches any position.
        try stripSecondaryCategoryUnlocked(id, fromListID: category.listID, date: date)

        let delete = try database.prepare("DELETE FROM card_list_categories WHERE id = ?")
        try delete.bind(id, at: 1)
        try delete.step()
        try insertSyncTombstoneUnlocked(entityType: .cardCollectionCategory, recordID: id, deletedAt: now)

        try consolidateDuplicateCardCollectionEntriesUnlocked(listID: category.listID)
        try normalizeCardCollectionCategoryPositionsUnlocked(listID: category.listID, date: date)
        try touchCardCollectionUnlocked(id: category.listID, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.deleteCategory,
          entityType: .cardCollectionCategory,
          entityID: id,
          listID: category.listID,
          date: now
        )
      }
    }
  }

  @discardableResult
  public func moveCardCollectionCategory(
    id: String,
    toPosition requestedPosition: Int,
    now: Date = Date()
  ) throws -> CardCollectionCategoryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let category = try cardCollectionCategoryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }

      var categories = try cardCollectionCategoriesUnlocked(forListID: category.listID)
        .filter { $0.zone == category.zone }
      guard let currentIndex = categories.firstIndex(where: { $0.id == id }) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }
      let moved = categories.remove(at: currentIndex)
      let newIndex = max(0, min(requestedPosition, categories.count))
      categories.insert(moved, at: newIndex)

      let date = Self.formattedListDate(now)
      try database.transaction {
        try updateCardCollectionCategoryPositionsUnlocked(categories, date: date)
        try touchCardCollectionUnlocked(id: category.listID, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.reorderCategory,
          entityType: .cardCollectionCategory,
          entityID: id,
          listID: category.listID,
          summary: "position=\(newIndex)",
          date: now
        )
      }

      guard let updated = try cardCollectionCategoryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.categoryNotFound
      }
      return updated
    }
  }

  @discardableResult
  public func moveCardCollectionEntry(
    id: String,
    toCategory categoryID: String?,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      guard let list = try cardCollectionUnlocked(id: entry.listID) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      var categoryID = categoryID
      let destinationZone: CardCollectionZone
      if let resolvedCategoryID = categoryID {
        guard let category = try cardCollectionCategoryUnlocked(id: resolvedCategoryID),
          category.listID == entry.listID
        else {
          throw CardCollectionDatabaseError.categoryNotFound
        }
        let categoryZone = list.ruleset.normalizedZone(category.zone)
        if categoryZone == category.zone {
          destinationZone = categoryZone
        } else {
          categoryID = nil
          destinationZone = categoryZone
        }
      } else {
        destinationZone = list.ruleset.normalizedZone(entry.zone)
      }

      let date = Self.formattedListDate(now)
      try database.transaction {
        if let existingEntry = try matchingCardCollectionEntryUnlocked(
          listID: entry.listID,
          zone: destinationZone,
          categoryID: categoryID,
          cardID: entry.cardID,
          excluding: entry.id
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?, updated_at = ?
            WHERE id = ?
            """)
          try update.bind(entry.quantity, at: 1)
          try update.bind(date, at: 2)
          try update.bind(existingEntry.id, at: 3)
          try update.step()

          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(entry.id, at: 1)
          try delete.step()
          // The source row merged into an existing duplicate and was deleted; tombstone it so the
          // deletion propagates and the source can't resurrect from another device's union merge.
          try insertSyncTombstoneUnlocked(
            entityType: .cardCollectionEntry,
            recordID: try cloudSyncEntryRecordIDUnlocked(for: entry),
            deletedAt: now
          )
        } else if destinationZone != entry.zone {
          // The primary category move also crossed zones, so the old-zone secondary tags
          // no longer apply — clear them alongside the zone/category update.
          let statement = try database.prepare(
            """
            UPDATE card_list_entries
            SET zone = ?, category_id = ?, secondary_category_ids = '', updated_at = ?
            WHERE id = ?
            """)
          try statement.bind(destinationZone.rawValue, at: 1)
          try statement.bind(categoryID, at: 2)
          try statement.bind(date, at: 3)
          try statement.bind(id, at: 4)
          try statement.step()
        } else {
          let statement = try database.prepare(
            """
            UPDATE card_list_entries
            SET zone = ?, category_id = ?, updated_at = ?
            WHERE id = ?
            """)
          try statement.bind(destinationZone.rawValue, at: 1)
          try statement.bind(categoryID, at: 2)
          try statement.bind(date, at: 3)
          try statement.bind(id, at: 4)
          try statement.step()
        }

        try touchCardCollectionUnlocked(id: entry.listID, date: date)
      }

      let movedID = try matchingCardCollectionEntryUnlocked(
        listID: entry.listID,
        zone: destinationZone,
        categoryID: categoryID,
        cardID: entry.cardID,
        excluding: nil
      )?.id ?? id
      guard var moved = try cardCollectionEntryUnlocked(id: movedID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.moveCategory,
        entityType: .cardCollectionEntry,
        entityID: moved.id,
        listID: entry.listID,
        summary: categoryID,
        date: now
      )
      moved.card = try card(id: moved.cardID)
      return moved
    }
  }

  /// Sets an entry's primary category in place — no zone change and no duplicate-merge.
  /// The bulk "Reorganize by Type" pass uses this so re-filing cards can't collapse rows.
  /// The category must belong to the entry's list and zone; if the new primary was one of
  /// the entry's secondary tags, it's removed from there (a card is filed under a category
  /// once).
  @discardableResult
  public func setCardCollectionEntryPrimaryCategory(
    id: String,
    categoryID: String?,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      if let categoryID {
        guard let category = try cardCollectionCategoryUnlocked(id: categoryID),
          category.listID == entry.listID,
          category.zone == entry.zone
        else {
          throw CardCollectionDatabaseError.categoryNotFound
        }
      }

      let remainingSecondaries = categoryID
        .map { primary in entry.secondaryCategoryIDs.filter { $0 != primary } }
        ?? entry.secondaryCategoryIDs

      let date = Self.formattedListDate(now)
      try database.transaction {
        let update = try database.prepare(
          """
          UPDATE card_list_entries
          SET category_id = ?, secondary_category_ids = ?, updated_at = ?
          WHERE id = ?
          """)
        try update.bind(categoryID, at: 1)
        try update.bind(Self.serializedList(remainingSecondaries), at: 2)
        try update.bind(date, at: 3)
        try update.bind(id, at: 4)
        try update.step()
        try touchCardCollectionUnlocked(id: entry.listID, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.setCategory,
          entityType: .cardCollectionEntry,
          entityID: id,
          listID: entry.listID,
          summary: categoryID,
          date: now
        )
      }

      guard var updated = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      updated.card = try card(id: updated.cardID)
      return updated
    }
  }

  /// Tags an entry with an extra (secondary) category. The category must belong to the
  /// entry's list and zone; adding the primary category or an existing tag is a no-op.
  @discardableResult
  public func addSecondaryCategory(
    entryID: String,
    categoryID: String,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: entryID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      guard let category = try cardCollectionCategoryUnlocked(id: categoryID),
        category.listID == entry.listID,
        category.zone == entry.zone
      else {
        throw CardCollectionDatabaseError.categoryNotFound
      }

      var secondaries = entry.secondaryCategoryIDs
      if entry.categoryID != categoryID, !secondaries.contains(categoryID) {
        secondaries.append(categoryID)
      }
      return try writeSecondaryCategoriesUnlocked(
        entryID: entryID,
        listID: entry.listID,
        secondaries: secondaries,
        changeAction: ChangeLogAction.addTag,
        changeCategoryID: categoryID,
        now: now
      )
    }
  }

  /// Removes a secondary-category tag from an entry (a no-op if it wasn't tagged).
  @discardableResult
  public func removeSecondaryCategory(
    entryID: String,
    categoryID: String,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: entryID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      let secondaries = entry.secondaryCategoryIDs.filter { $0 != categoryID }
      return try writeSecondaryCategoriesUnlocked(
        entryID: entryID,
        listID: entry.listID,
        secondaries: secondaries,
        changeAction: ChangeLogAction.removeTag,
        changeCategoryID: categoryID,
        now: now
      )
    }
  }

  private func writeSecondaryCategoriesUnlocked(
    entryID: String,
    listID: String,
    secondaries: [String],
    changeAction: String,
    changeCategoryID: String,
    now: Date
  ) throws -> CardCollectionEntryRecord {
    let date = Self.formattedListDate(now)
    try database.transaction {
      let update = try database.prepare(
        "UPDATE card_list_entries SET secondary_category_ids = ?, updated_at = ? WHERE id = ?")
      try update.bind(Self.serializedList(secondaries), at: 1)
      try update.bind(date, at: 2)
      try update.bind(entryID, at: 3)
      try update.step()
      try touchCardCollectionUnlocked(id: listID, date: date)
      try recordChangeUnlocked(
        action: changeAction,
        entityType: .cardCollectionEntry,
        entityID: entryID,
        listID: listID,
        summary: changeCategoryID,
        date: now
      )
    }
    guard var updated = try cardCollectionEntryUnlocked(id: entryID) else {
      throw CardCollectionDatabaseError.entryNotFound
    }
    updated.card = try card(id: updated.cardID)
    return updated
  }

  /// Removes `categoryID` from every entry's secondary-tag list in `listID`. Called when a
  /// category is deleted. Must run inside an open transaction. Secondary IDs are stored as
  /// `|id1|id2|`, so `%|id|%` finds any entry that references the category.
  private func stripSecondaryCategoryUnlocked(_ categoryID: String, fromListID listID: String, date: String) throws {
    let select = try database.prepare(
      """
      SELECT id, secondary_category_ids
      FROM card_list_entries
      WHERE list_id = ? AND secondary_category_ids LIKE ?
      """)
    try select.bind(listID, at: 1)
    try select.bind("%|\(categoryID)|%", at: 2)
    var updates: [(id: String, remaining: [String])] = []
    while try select.step() {
      guard let entryID = select.string(at: 0) else { continue }
      let remaining = Self.deserializedList(select.string(at: 1)).filter { $0 != categoryID }
      updates.append((entryID, remaining))
    }
    guard !updates.isEmpty else { return }
    let update = try database.prepare(
      "UPDATE card_list_entries SET secondary_category_ids = ?, updated_at = ? WHERE id = ?")
    for change in updates {
      try update.bind(Self.serializedList(change.remaining), at: 1)
      try update.bind(date, at: 2)
      try update.bind(change.id, at: 3)
      try update.step()
      try update.reset()
    }
  }

  @discardableResult
  public func moveCardCollectionEntry(
    id: String,
    toZone zone: CardCollectionZone,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      guard let list = try cardCollectionUnlocked(id: entry.listID) else {
        throw CardCollectionDatabaseError.listNotFound
      }
      let zone = list.ruleset.normalizedZone(zone)

      let date = Self.formattedListDate(now)
      try database.transaction {
        if let existingEntry = try matchingCardCollectionEntryUnlocked(
          listID: entry.listID,
          zone: zone,
          categoryID: nil,
          cardID: entry.cardID,
          excluding: entry.id
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?, updated_at = ?
            WHERE id = ?
            """)
          try update.bind(entry.quantity, at: 1)
          try update.bind(date, at: 2)
          try update.bind(existingEntry.id, at: 3)
          try update.step()

          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(entry.id, at: 1)
          try delete.step()
          // The source row merged into an existing duplicate and was deleted; tombstone it so the
          // deletion propagates and the source can't resurrect from another device's union merge.
          try insertSyncTombstoneUnlocked(
            entityType: .cardCollectionEntry,
            recordID: try cloudSyncEntryRecordIDUnlocked(for: entry),
            deletedAt: now
          )
        } else {
          // Zone changed: the entry's secondary tags belonged to the old zone, so drop them.
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET zone = ?, category_id = NULL, secondary_category_ids = '', updated_at = ?
            WHERE id = ?
            """)
          try update.bind(zone.rawValue, at: 1)
          try update.bind(date, at: 2)
          try update.bind(entry.id, at: 3)
          try update.step()
        }

        try touchCardCollectionUnlocked(id: entry.listID, date: date)
      }

      let movedID = try matchingCardCollectionEntryUnlocked(
        listID: entry.listID,
        zone: zone,
        categoryID: nil,
        cardID: entry.cardID,
        excluding: nil
      )?.id ?? id
      guard var moved = try cardCollectionEntryUnlocked(id: movedID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.moveZone,
        entityType: .cardCollectionEntry,
        entityID: moved.id,
        listID: entry.listID,
        summary: zone.rawValue,
        date: now
      )
      moved.card = try card(id: moved.cardID)
      return moved
    }
  }

  @discardableResult
  public func appendCard(
    _ cardID: String,
    toList listID: String,
    zone requestedZone: CardCollectionZone = .mainboard,
    categoryID: String? = nil,
    quantity requestedQuantity: Int = 1,
    enforceRulesetLimits: Bool = true,
    now: Date = Date()
  ) throws
    -> CardCollectionEntryRecord
  {
    let quantity = max(1, requestedQuantity)
    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let list = try cardCollectionUnlocked(id: listID) else {
        throw CardCollectionDatabaseError.listNotFound
      }

      // Guard-rail against duplicate adds that would break a Commander deck's singleton rule.
      // Interactive callers leave this on; bulk/import/rescan paths pass `false` (and a "force"
      // add flips it off) so they never abort mid-batch. Only enforced when the card resolves —
      // an unknown card falls through to the lenient legacy behavior.
      if enforceRulesetLimits,
        list.ruleset == .commander,
        let card = try card(id: cardID),
        !CardCollectionRulesetValidator.commanderSingletonAllowsAdding(
          card,
          quantity: quantity,
          toExisting: try cardCollectionEntriesUnlocked(forListID: listID)
        )
      {
        throw CardCollectionDatabaseError.commanderSingletonLimit
      }

      var zone = list.ruleset.normalizedZone(requestedZone)
      var categoryID = categoryID
      if let resolvedCategoryID = categoryID {
        guard let category = try cardCollectionCategoryUnlocked(id: resolvedCategoryID),
          category.listID == listID
        else {
          throw CardCollectionDatabaseError.categoryNotFound
        }
        let categoryZone = list.ruleset.normalizedZone(category.zone)
        if categoryZone == category.zone {
          zone = categoryZone
        } else {
          categoryID = nil
          zone = categoryZone
        }
      }

      let position: Int = try {
        let positionStatement = try database.prepare(
          """
          SELECT COALESCE(MAX(position), -1) + 1
          FROM card_list_entries
          WHERE list_id = ? AND zone = ?
          """)
        try positionStatement.bind(listID, at: 1)
        try positionStatement.bind(zone.rawValue, at: 2)
        _ = try positionStatement.step()
        return positionStatement.int(at: 0) ?? 0
      }()
      let entryID = UUID().uuidString.lowercased()
      let date = Self.formattedListDate(now)

      try database.transaction {
        if let existingEntry = try matchingCardCollectionEntryUnlocked(
          listID: listID,
          zone: zone,
          categoryID: categoryID,
          cardID: cardID,
          excluding: nil
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?, updated_at = ?
            WHERE id = ?
            """)
          try update.bind(quantity, at: 1)
          try update.bind(date, at: 2)
          try update.bind(existingEntry.id, at: 3)
          try update.step()
        } else {
          let insert = try database.prepare(
            """
            INSERT INTO card_list_entries (
                id, list_id, zone, category_id, card_id, position, quantity, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
          try insert.bind(entryID, at: 1)
          try insert.bind(listID, at: 2)
          try insert.bind(zone.rawValue, at: 3)
          try insert.bind(categoryID, at: 4)
          try insert.bind(cardID, at: 5)
          try insert.bind(position, at: 6)
          try insert.bind(quantity, at: 7)
          try insert.bind(date, at: 8)
          try insert.bind(date, at: 9)
          try insert.step()
        }

        try touchCardCollectionUnlocked(id: listID, date: date)
      }

      guard var entry = try matchingCardCollectionEntryUnlocked(
        listID: listID,
        zone: zone,
        categoryID: categoryID,
        cardID: cardID,
        excluding: nil
      ) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.addCard,
        entityType: .cardCollectionEntry,
        entityID: entry.id,
        listID: listID,
        summary: cardID,
        date: now
      )
      entry.card = try card(id: cardID)
      return entry
    }
  }

  @discardableResult
  public func replaceCardCollectionEntryPrint(
    id: String,
    withCardID cardID: String,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }

      guard entry.cardID != cardID else {
        var current = entry
        current.card = try card(id: current.cardID)
        return current
      }

      let date = Self.formattedListDate(now)
      var updatedEntryID = id

      // Carry the pinned finish onto the new printing, but drop it if that printing
      // cannot be foil (e.g. swapping a foil pick onto a nonfoil-only version).
      let newPrintingSupportsFoil = (try card(id: cardID))?.supportsFoil ?? false
      let carriedFinish = newPrintingSupportsFoil ? entry.selectedFinish?.rawValue : nil

      try database.transaction {
        if let existingEntry = try matchingCardCollectionEntryUnlocked(
          listID: entry.listID,
          zone: entry.zone,
          categoryID: entry.categoryID,
          cardID: cardID,
          excluding: entry.id
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?, updated_at = ?
            WHERE id = ?
            """)
          try update.bind(entry.quantity, at: 1)
          try update.bind(date, at: 2)
          try update.bind(existingEntry.id, at: 3)
          try update.step()

          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(entry.id, at: 1)
          try delete.step()
          // The source row merged into an existing duplicate and was deleted; tombstone it so the
          // deletion propagates and the source can't resurrect from another device's union merge.
          try insertSyncTombstoneUnlocked(
            entityType: .cardCollectionEntry,
            recordID: try cloudSyncEntryRecordIDUnlocked(for: entry),
            deletedAt: now
          )

          updatedEntryID = existingEntry.id
        } else {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET card_id = ?, selected_finish = ?, updated_at = ?
            WHERE id = ?
            """)
          try update.bind(cardID, at: 1)
          try update.bind(carriedFinish, at: 2)
          try update.bind(date, at: 3)
          try update.bind(entry.id, at: 4)
          try update.step()
        }

        try touchCardCollectionUnlocked(id: entry.listID, date: date)
      }

      guard var updatedEntry = try cardCollectionEntryUnlocked(id: updatedEntryID) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      try recordChangeUnlocked(
        action: ChangeLogAction.changePrint,
        entityType: .cardCollectionEntry,
        entityID: updatedEntry.id,
        listID: updatedEntry.listID,
        summary: cardID,
        date: now
      )
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  /// Pins the finish (e.g. foil) the user chose for a collection entry. Passing `nil`
  /// or `.normal` clears the pin. Persisted and synced like a printing swap.
  @discardableResult
  public func setCardCollectionEntryFinish(
    id: String,
    finish: CardValueFinish?,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }

      let storedFinish = (finish == .normal) ? nil : finish?.rawValue
      let date = Self.formattedListDate(now)

      try database.transaction {
        let update = try database.prepare(
          """
          UPDATE card_list_entries
          SET selected_finish = ?, updated_at = ?
          WHERE id = ?
          """)
        try update.bind(storedFinish, at: 1)
        try update.bind(date, at: 2)
        try update.bind(id, at: 3)
        try update.step()

        try touchCardCollectionUnlocked(id: entry.listID, date: date)
        try recordChangeUnlocked(
          action: ChangeLogAction.setFinish,
          entityType: .cardCollectionEntry,
          entityID: id,
          listID: entry.listID,
          summary: (finish ?? .normal).rawValue,
          date: now
        )
      }

      guard var updatedEntry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  public func removeCardCollectionEntry(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        return
      }

      try database.transaction {
        if entry.quantity > 1 {
          let decrement = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity - 1, updated_at = ?
            WHERE id = ?
            """)
          try decrement.bind(Self.formattedListDate(now), at: 1)
          try decrement.bind(id, at: 2)
          try decrement.step()
        } else {
          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(id, at: 1)
          try delete.step()
          let recordID = try cloudSyncEntryRecordIDUnlocked(for: entry)
          try insertSyncTombstoneUnlocked(
            entityType: .cardCollectionEntry,
            recordID: recordID,
            deletedAt: now
          )
        }

        try touchCardCollectionUnlocked(id: entry.listID, date: Self.formattedListDate(now))
        try recordChangeUnlocked(
          action: ChangeLogAction.removeCard,
          entityType: .cardCollectionEntry,
          entityID: entry.id,
          listID: entry.listID,
          summary: entry.cardID,
          date: now
        )
      }
    }
  }

  @discardableResult
  public func incrementCardCollectionEntryQuantity(
    id: String,
    by amount: Int = 1,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    let quantityDelta = max(1, amount)
    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }

      let update = try database.prepare(
        """
        UPDATE card_list_entries
        SET quantity = quantity + ?, updated_at = ?
        WHERE id = ?
        """)
      try database.transaction {
        try update.bind(quantityDelta, at: 1)
        try update.bind(Self.formattedListDate(now), at: 2)
        try update.bind(id, at: 3)
        try update.step()
        try touchCardCollectionUnlocked(id: entry.listID, date: Self.formattedListDate(now))
        try recordChangeUnlocked(
          action: ChangeLogAction.setQuantity,
          entityType: .cardCollectionEntry,
          entityID: id,
          listID: entry.listID,
          summary: "+\(quantityDelta)",
          date: now
        )
      }

      guard var updatedEntry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  @discardableResult
  public func setCardCollectionEntryQuantity(
    id: String,
    quantity requestedQuantity: Int,
    now: Date = Date()
  ) throws -> CardCollectionEntryRecord {
    let quantity = max(1, requestedQuantity)
    return try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }

      let update = try database.prepare(
        """
        UPDATE card_list_entries
        SET quantity = ?, updated_at = ?
        WHERE id = ?
        """)
      try database.transaction {
        try update.bind(quantity, at: 1)
        try update.bind(Self.formattedListDate(now), at: 2)
        try update.bind(id, at: 3)
        try update.step()
        try touchCardCollectionUnlocked(id: entry.listID, date: Self.formattedListDate(now))
        try recordChangeUnlocked(
          action: ChangeLogAction.setQuantity,
          entityType: .cardCollectionEntry,
          entityID: id,
          listID: entry.listID,
          summary: "×\(quantity)",
          date: now
        )
      }

      guard var updatedEntry = try cardCollectionEntryUnlocked(id: id) else {
        throw CardCollectionDatabaseError.entryNotFound
      }
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  public func removeCardCollectionEntryCompletely(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      let now = try issueSyncTimestampUnlocked(now: now)
      guard let entry = try cardCollectionEntryUnlocked(id: id) else {
        return
      }

      try database.transaction {
        let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
        try delete.bind(id, at: 1)
        try delete.step()
        let recordID = try cloudSyncEntryRecordIDUnlocked(for: entry)
        try insertSyncTombstoneUnlocked(
          entityType: .cardCollectionEntry,
          recordID: recordID,
          deletedAt: now
        )
        try touchCardCollectionUnlocked(id: entry.listID, date: Self.formattedListDate(now))
        try recordChangeUnlocked(
          action: ChangeLogAction.removeCard,
          entityType: .cardCollectionEntry,
          entityID: entry.id,
          listID: entry.listID,
          summary: entry.cardID,
          date: now
        )
      }
    }
  }

  private func cloudSyncEntryRecordIDUnlocked(
    for entry: CardCollectionEntryRecord
  ) throws -> CardCollectionEntryRecord.ID {
    guard let list = try cardCollectionUnlocked(id: entry.listID),
      CloudSyncEntityCodec.isFavouritesListName(list.name)
        || list.id == CloudSyncEntityCodec.favouritesListID
    else {
      return entry.id
    }
    return CloudSyncEntityCodec.favouriteEntryID(cardID: entry.cardID)
  }

  func normalizeCardCollectionZonesForRulesetsUnlocked() throws {
    let lists = try cardCollectionsUnlocked()
    let date = Self.formattedListDate(Date())
    try database.transaction {
      for list in lists {
        try normalizeCardCollectionZonesUnlocked(listID: list.id, ruleset: list.ruleset, date: date)
      }
    }
  }

  @discardableResult
  func normalizeCardCollectionZonesUnlocked(
    listID: String,
    ruleset: CardCollectionRuleset,
    date: String
  ) throws -> Bool {
    var changed = false
    var categories = try cardCollectionCategoriesUnlocked(forListID: listID)

    for category in categories {
      let destinationZone = ruleset.normalizedZone(category.zone)
      guard destinationZone != category.zone else {
        continue
      }

      if let existingCategory = categories.first(where: {
        $0.id != category.id
          && $0.zone == destinationZone
          && $0.name.caseInsensitiveCompare(category.name) == .orderedSame
      }) {
        let updateEntries = try database.prepare(
          """
          UPDATE card_list_entries
          SET zone = ?, category_id = ?, updated_at = ?
          WHERE list_id = ? AND category_id = ?
          """)
        try updateEntries.bind(destinationZone.rawValue, at: 1)
        try updateEntries.bind(existingCategory.id, at: 2)
        try updateEntries.bind(date, at: 3)
        try updateEntries.bind(listID, at: 4)
        try updateEntries.bind(category.id, at: 5)
        try updateEntries.step()

        let deleteCategory = try database.prepare("DELETE FROM card_list_categories WHERE id = ?")
        try deleteCategory.bind(category.id, at: 1)
        try deleteCategory.step()
        // The duplicate category is gone; tombstone it so the deletion propagates and the
        // category can't resurrect from another device on the next union merge.
        try insertSyncTombstoneUnlocked(
          entityType: .cardCollectionCategory,
          recordID: category.id,
          deletedAt: Self.parseListDate(date)
        )

        categories.removeAll { $0.id == category.id }
      } else {
        let updateCategory = try database.prepare(
          """
          UPDATE card_list_categories
          SET zone = ?, updated_at = ?
          WHERE id = ?
          """)
        try updateCategory.bind(destinationZone.rawValue, at: 1)
        try updateCategory.bind(date, at: 2)
        try updateCategory.bind(category.id, at: 3)
        try updateCategory.step()

        let updateEntries = try database.prepare(
          """
          UPDATE card_list_entries
          SET zone = ?, updated_at = ?
          WHERE list_id = ? AND category_id = ?
          """)
        try updateEntries.bind(destinationZone.rawValue, at: 1)
        try updateEntries.bind(date, at: 2)
        try updateEntries.bind(listID, at: 3)
        try updateEntries.bind(category.id, at: 4)
        try updateEntries.step()

        if let index = categories.firstIndex(where: { $0.id == category.id }) {
          categories[index].zone = destinationZone
        }
      }

      changed = true
    }

    categories = try cardCollectionCategoriesUnlocked(forListID: listID)
    for category in categories where ruleset.allowedZones.contains(category.zone) {
      let mismatchCount = try database.prepare(
        """
        SELECT COUNT(*)
        FROM card_list_entries
        WHERE list_id = ? AND category_id = ? AND zone != ?
        """)
      try mismatchCount.bind(listID, at: 1)
      try mismatchCount.bind(category.id, at: 2)
      try mismatchCount.bind(category.zone.rawValue, at: 3)
      _ = try mismatchCount.step()
      guard (mismatchCount.int(at: 0) ?? 0) > 0 else {
        continue
      }

      let updateEntries = try database.prepare(
        """
        UPDATE card_list_entries
        SET zone = ?, updated_at = ?
        WHERE list_id = ? AND category_id = ?
        """)
      try updateEntries.bind(category.zone.rawValue, at: 1)
      try updateEntries.bind(date, at: 2)
      try updateEntries.bind(listID, at: 3)
      try updateEntries.bind(category.id, at: 4)
      try updateEntries.step()
      changed = true
    }

    for zone in CardCollectionZone.allCases {
      let destinationZone = ruleset.normalizedZone(zone)
      guard destinationZone != zone else {
        continue
      }

      let invalidCount = try database.prepare(
        """
        SELECT COUNT(*)
        FROM card_list_entries
        WHERE list_id = ? AND zone = ?
        """)
      try invalidCount.bind(listID, at: 1)
      try invalidCount.bind(zone.rawValue, at: 2)
      _ = try invalidCount.step()
      guard (invalidCount.int(at: 0) ?? 0) > 0 else {
        continue
      }

      let updateEntries = try database.prepare(
        """
        UPDATE card_list_entries
        SET zone = ?, category_id = NULL, updated_at = ?
        WHERE list_id = ? AND zone = ?
        """)
      try updateEntries.bind(destinationZone.rawValue, at: 1)
      try updateEntries.bind(date, at: 2)
      try updateEntries.bind(listID, at: 3)
      try updateEntries.bind(zone.rawValue, at: 4)
      try updateEntries.step()
      changed = true
    }

    guard changed else {
      return false
    }

    try consolidateDuplicateCardCollectionEntriesUnlocked(listID: listID)
    try normalizeCardCollectionCategoryPositionsUnlocked(listID: listID, date: date)
    return true
  }

  public func saveMetadataValue(_ value: String?, forKey key: String) throws {
    try withDatabaseLock {
      if let value {
        let statement = try database.prepare(
          """
          INSERT INTO metadata (key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
          """)
        try statement.bind(key, at: 1)
        try statement.bind(value, at: 2)
        try statement.step()
      } else {
        let statement = try database.prepare("DELETE FROM metadata WHERE key = ?")
        try statement.bind(key, at: 1)
        try statement.step()
      }
    }
  }

  public func metadataValue(forKey key: String) throws -> String? {
    try withDatabaseLock {
      let statement = try database.prepare("SELECT value FROM metadata WHERE key = ?")
      try statement.bind(key, at: 1)
      guard try statement.step() else {
        return nil
      }
      return statement.string(at: 0)
    }
  }
}
