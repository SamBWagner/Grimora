import Foundation

extension CardDatabase {
  public func cardLists() throws -> [CardListRecord] {
    try withDatabaseLock {
      try cardListsUnlocked()
    }
  }

  public func cardList(id: String) throws -> CardListRecord? {
    try withDatabaseLock {
      try cardListUnlocked(id: id)
    }
  }

  public func cardListEntries(forListID listID: String) throws -> [CardListEntryRecord] {
    try withDatabaseLock {
      try cardListEntriesUnlocked(forListID: listID)
    }
  }

  public func searchCardListEntries(
    forListID listID: String,
    text: String
  ) throws -> CardListEntrySearchResponse {
    try withDatabaseLock {
      let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else {
        return .results(try cardListEntriesUnlocked(forListID: listID))
      }

      let plan: SearchQueryPlan
      switch SearchQuery.compile(query) {
      case .success(let compiledPlan):
        plan = compiledPlan
      case .failure(let reason):
        return .unsupported(reason)
      }

      var entries = try cardListEntriesUnlocked(
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
  public func searchAllCardListEntries(text: String) throws -> CrossListSearchResponse {
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

      var entries = try allMatchingCardListEntriesUnlocked(
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

  /// Fetches the entries across all lists whose card matches the compiled query, hydrating each
  /// entry's card once per distinct card id to avoid repeated lookups over large libraries.
  func allMatchingCardListEntriesUnlocked(
    cardWhereSQL: String?,
    cardWhereBindings: [SearchQuery.SQLBinding] = []
  ) throws -> [CardListEntryRecord] {
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
      SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at
      FROM card_list_entries
      WHERE 1 = 1
      \(searchClause)
      ORDER BY list_id ASC, zone ASC, position ASC, created_at ASC, id ASC
      """)
    for (index, binding) in cardWhereBindings.enumerated() {
      try binding.apply(to: statement, index: Int32(index + 1))
    }

    var entries: [CardListEntryRecord] = []
    var cardsByID: [String: CardRecord?] = [:]
    while try statement.step() {
      var entry = readCardListEntry(from: statement)
      if let cached = cardsByID[entry.cardID] {
        entry.card = cached
      } else {
        let card = try card(id: entry.cardID)
        cardsByID[entry.cardID] = card
        entry.card = card
      }
      entries.append(entry)
    }
    return entries
  }

  /// Groups matching entries into per-list matches, preserving first-seen list order.
  static func groupedCrossListMatches(
    from entries: [CardListEntryRecord]
  ) -> [CrossListSearchMatch] {
    var order: [String] = []
    var grouped: [String: [CardListEntryRecord]] = [:]
    for entry in entries {
      if grouped[entry.listID] == nil {
        order.append(entry.listID)
      }
      grouped[entry.listID, default: []].append(entry)
    }
    return order.map { CrossListSearchMatch(listID: $0, entries: grouped[$0] ?? []) }
  }

  func cardListEntriesUnlocked(
    forListID listID: String,
    cardWhereSQL: String? = nil,
    cardWhereBindings: [SearchQuery.SQLBinding] = []
  ) throws -> [CardListEntryRecord] {
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
      SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at
      FROM card_list_entries
      WHERE list_id = ?
      \(searchClause)
      ORDER BY zone ASC, position ASC, created_at ASC, id ASC
      """)
    try statement.bind(listID, at: 1)
    for (index, binding) in cardWhereBindings.enumerated() {
      try binding.apply(to: statement, index: Int32(index + 2))
    }

    var entries: [CardListEntryRecord] = []
    while try statement.step() {
      var entry = readCardListEntry(from: statement)
      entry.card = try card(id: entry.cardID)
      entries.append(entry)
    }
    return entries
  }

  public func cardListCategories(forListID listID: String) throws -> [CardListCategoryRecord] {
    try withDatabaseLock {
      try cardListCategoriesUnlocked(forListID: listID)
    }
  }

  public func cardListLibrarySnapshot() throws -> CardListLibrarySnapshot {
    try withDatabaseLock {
      try cardListLibrarySnapshotUnlocked()
    }
  }

  public func restoreCardListLibrarySnapshot(_ snapshot: CardListLibrarySnapshot) throws {
    try withDatabaseLock {
      try database.transaction {
        try restoreCardListLibrarySnapshotUnlocked(snapshot)
      }
    }
  }

  func cardListLibrarySnapshotUnlocked() throws -> CardListLibrarySnapshot {
    try CardListLibrarySnapshot(
      lists: cardListsUnlocked(),
      categories: cardListCategoriesUnlocked(),
      entries: cardListEntriesUnlocked()
    )
  }

  func restoreCardListLibrarySnapshotUnlocked(_ snapshot: CardListLibrarySnapshot) throws {
    try database.execute("DELETE FROM card_list_entries")
    try database.execute("DELETE FROM card_list_categories")
    try database.execute("DELETE FROM card_lists")

    let listInsert = try database.prepare(
      """
      INSERT INTO card_lists (
          id, name, ruleset, description_rtfd, description_plain_text, created_at, updated_at,
          is_pinned, pinned_at, position, shows_dashboard, dashboard_includes_lands,
          display_sort_mode, display_sort_direction, view_mode
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          id, list_id, zone, category_id, card_id, position, quantity, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      try entryInsert.step()
      try entryInsert.reset()
    }
  }

  @discardableResult
  public func createCardList(named name: String, now: Date = Date()) throws -> CardListRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardListDatabaseError.emptyName
    }

    return try withDatabaseLock {
      let id = UUID().uuidString.lowercased()
      let date = Self.formattedListDate(now)
      let position = try nextCardListPositionUnlocked(isPinned: false)
      let statement = try database.prepare(
        """
        INSERT INTO card_lists (id, name, created_at, updated_at, position)
        VALUES (?, ?, ?, ?, ?)
        """)
      try statement.bind(id, at: 1)
      try statement.bind(normalizedName, at: 2)
      try statement.bind(date, at: 3)
      try statement.bind(date, at: 4)
      try statement.bind(position, at: 5)
      try statement.step()

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func renameCardList(id: String, to name: String, now: Date = Date()) throws -> CardListRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardListDatabaseError.emptyName
    }

    return try withDatabaseLock {
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

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func updateCardListDescription(
    id: String,
    rtfdData: Data?,
    plainText: String,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
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

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func setCardListDashboardVisibility(
    id: String,
    showsDashboard: Bool,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
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

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func setCardListDashboardIncludesLands(
    id: String,
    includesLands: Bool,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
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

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func setCardListDisplaySort(
    id: String,
    mode: SortMode?,
    direction: SearchSortDirection,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
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

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func setCardListViewMode(
    id: String,
    viewMode: CardListViewMode,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
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

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  @discardableResult
  public func setCardListRuleset(
    id: String,
    ruleset: CardListRuleset,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
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

        try normalizeCardListZonesUnlocked(listID: id, ruleset: ruleset, date: date)
      }

      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return list
    }
  }

  public func deleteCardList(id: String) throws {
    try withDatabaseLock {
      try database.transaction {
        let statement = try database.prepare("DELETE FROM card_lists WHERE id = ?")
        try statement.bind(id, at: 1)
        try statement.step()
        try insertSyncTombstoneUnlocked(entityType: .cardList, recordID: id)
      }
    }
  }

  @discardableResult
  public func setCardListPinned(
    id: String,
    isPinned: Bool,
    now: Date = Date()
  ) throws -> CardListRecord {
    try moveCardList(id: id, toPosition: 0, isPinned: isPinned, now: now)
  }

  @discardableResult
  public func moveCardList(
    id: String,
    toPosition requestedPosition: Int,
    isPinned requestedPinnedState: Bool? = nil,
    now: Date = Date()
  ) throws -> CardListRecord {
    try withDatabaseLock {
      guard let list = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }

      let destinationIsPinned = requestedPinnedState ?? list.isPinned
      let date = Self.formattedListDate(now)
      var sourceLists = try cardListsUnlocked(isPinned: list.isPinned, ordering: .storedPosition)
      var destinationLists = destinationIsPinned == list.isPinned
        ? sourceLists
        : try cardListsUnlocked(isPinned: destinationIsPinned, ordering: .storedPosition)

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
          try touchCardListUnlocked(id: id, date: date)
        }

        if destinationIsPinned != list.isPinned {
          try updateCardListPositionsUnlocked(sourceLists)
        }
        try updateCardListPositionsUnlocked(destinationLists)
      }

      guard let moved = try cardListUnlocked(id: id) else {
        throw CardListDatabaseError.listNotFound
      }
      return moved
    }
  }

  @discardableResult
  public func createCardListCategory(
    inList listID: String,
    zone: CardListZone = .mainboard,
    named name: String,
    now: Date = Date()
  ) throws -> CardListCategoryRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardListDatabaseError.emptyName
    }
    guard !Self.isImplicitCategoryName(normalizedName) else {
      throw CardListDatabaseError.duplicateName
    }

    return try withDatabaseLock {
      guard let list = try cardListUnlocked(id: listID) else {
        throw CardListDatabaseError.listNotFound
      }
      let zone = list.ruleset.normalizedZone(zone)
      guard try !cardListCategoryNameExistsUnlocked(
        inList: listID,
        zone: zone,
        named: normalizedName,
        excluding: nil
      ) else {
        throw CardListDatabaseError.duplicateName
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

        try touchCardListUnlocked(id: listID, date: date)
      }

      guard let category = try cardListCategoryUnlocked(id: id) else {
        throw CardListDatabaseError.categoryNotFound
      }
      return category
    }
  }

  @discardableResult
  public func renameCardListCategory(
    id: String,
    to name: String,
    now: Date = Date()
  ) throws -> CardListCategoryRecord {
    let normalizedName = Self.normalizedListName(name)
    guard !normalizedName.isEmpty else {
      throw CardListDatabaseError.emptyName
    }
    guard !Self.isImplicitCategoryName(normalizedName) else {
      throw CardListDatabaseError.duplicateName
    }

    return try withDatabaseLock {
      guard let category = try cardListCategoryUnlocked(id: id) else {
        throw CardListDatabaseError.categoryNotFound
      }
      guard try !cardListCategoryNameExistsUnlocked(
        inList: category.listID,
        zone: category.zone,
        named: normalizedName,
        excluding: id
      ) else {
        throw CardListDatabaseError.duplicateName
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

        try touchCardListUnlocked(id: category.listID, date: date)
      }

      guard let renamed = try cardListCategoryUnlocked(id: id) else {
        throw CardListDatabaseError.categoryNotFound
      }
      return renamed
    }
  }

  public func deleteCardListCategory(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      guard let category = try cardListCategoryUnlocked(id: id) else {
        throw CardListDatabaseError.categoryNotFound
      }

      let date = Self.formattedListDate(now)
      try database.transaction {
        let uncategorizeEntries = try database.prepare(
          """
          UPDATE card_list_entries
          SET category_id = NULL
          WHERE category_id = ?
          """)
        try uncategorizeEntries.bind(id, at: 1)
        try uncategorizeEntries.step()

        let delete = try database.prepare("DELETE FROM card_list_categories WHERE id = ?")
        try delete.bind(id, at: 1)
        try delete.step()
        try insertSyncTombstoneUnlocked(entityType: .cardListCategory, recordID: id, deletedAt: now)

        try consolidateDuplicateCardListEntriesUnlocked(listID: category.listID)
        try normalizeCardListCategoryPositionsUnlocked(listID: category.listID, date: date)
        try touchCardListUnlocked(id: category.listID, date: date)
      }
    }
  }

  @discardableResult
  public func moveCardListCategory(
    id: String,
    toPosition requestedPosition: Int,
    now: Date = Date()
  ) throws -> CardListCategoryRecord {
    try withDatabaseLock {
      guard let category = try cardListCategoryUnlocked(id: id) else {
        throw CardListDatabaseError.categoryNotFound
      }

      var categories = try cardListCategoriesUnlocked(forListID: category.listID)
        .filter { $0.zone == category.zone }
      guard let currentIndex = categories.firstIndex(where: { $0.id == id }) else {
        throw CardListDatabaseError.categoryNotFound
      }
      let moved = categories.remove(at: currentIndex)
      let newIndex = max(0, min(requestedPosition, categories.count))
      categories.insert(moved, at: newIndex)

      let date = Self.formattedListDate(now)
      try database.transaction {
        try updateCardListCategoryPositionsUnlocked(categories, date: date)
        try touchCardListUnlocked(id: category.listID, date: date)
      }

      guard let updated = try cardListCategoryUnlocked(id: id) else {
        throw CardListDatabaseError.categoryNotFound
      }
      return updated
    }
  }

  @discardableResult
  public func moveCardListEntry(
    id: String,
    toCategory categoryID: String?,
    now: Date = Date()
  ) throws -> CardListEntryRecord {
    try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
      }
      guard let list = try cardListUnlocked(id: entry.listID) else {
        throw CardListDatabaseError.listNotFound
      }
      var categoryID = categoryID
      let destinationZone: CardListZone
      if let resolvedCategoryID = categoryID {
        guard let category = try cardListCategoryUnlocked(id: resolvedCategoryID),
          category.listID == entry.listID
        else {
          throw CardListDatabaseError.categoryNotFound
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
        if let existingEntry = try matchingCardListEntryUnlocked(
          listID: entry.listID,
          zone: destinationZone,
          categoryID: categoryID,
          cardID: entry.cardID,
          excluding: entry.id
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?
            WHERE id = ?
            """)
          try update.bind(entry.quantity, at: 1)
          try update.bind(existingEntry.id, at: 2)
          try update.step()

          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(entry.id, at: 1)
          try delete.step()
        } else {
          let statement = try database.prepare(
            """
            UPDATE card_list_entries
            SET zone = ?, category_id = ?
            WHERE id = ?
            """)
          try statement.bind(destinationZone.rawValue, at: 1)
          try statement.bind(categoryID, at: 2)
          try statement.bind(id, at: 3)
          try statement.step()
        }

        try touchCardListUnlocked(id: entry.listID, date: date)
      }

      let movedID = try matchingCardListEntryUnlocked(
        listID: entry.listID,
        zone: destinationZone,
        categoryID: categoryID,
        cardID: entry.cardID,
        excluding: nil
      )?.id ?? id
      guard var moved = try cardListEntryUnlocked(id: movedID) else {
        throw CardListDatabaseError.entryNotFound
      }
      moved.card = try card(id: moved.cardID)
      return moved
    }
  }

  @discardableResult
  public func moveCardListEntry(
    id: String,
    toZone zone: CardListZone,
    now: Date = Date()
  ) throws -> CardListEntryRecord {
    try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
      }
      guard let list = try cardListUnlocked(id: entry.listID) else {
        throw CardListDatabaseError.listNotFound
      }
      let zone = list.ruleset.normalizedZone(zone)

      let date = Self.formattedListDate(now)
      try database.transaction {
        if let existingEntry = try matchingCardListEntryUnlocked(
          listID: entry.listID,
          zone: zone,
          categoryID: nil,
          cardID: entry.cardID,
          excluding: entry.id
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?
            WHERE id = ?
            """)
          try update.bind(entry.quantity, at: 1)
          try update.bind(existingEntry.id, at: 2)
          try update.step()

          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(entry.id, at: 1)
          try delete.step()
        } else {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET zone = ?, category_id = NULL
            WHERE id = ?
            """)
          try update.bind(zone.rawValue, at: 1)
          try update.bind(entry.id, at: 2)
          try update.step()
        }

        try touchCardListUnlocked(id: entry.listID, date: date)
      }

      let movedID = try matchingCardListEntryUnlocked(
        listID: entry.listID,
        zone: zone,
        categoryID: nil,
        cardID: entry.cardID,
        excluding: nil
      )?.id ?? id
      guard var moved = try cardListEntryUnlocked(id: movedID) else {
        throw CardListDatabaseError.entryNotFound
      }
      moved.card = try card(id: moved.cardID)
      return moved
    }
  }

  @discardableResult
  public func appendCard(
    _ cardID: String,
    toList listID: String,
    zone requestedZone: CardListZone = .mainboard,
    categoryID: String? = nil,
    quantity requestedQuantity: Int = 1,
    now: Date = Date()
  ) throws
    -> CardListEntryRecord
  {
    let quantity = max(1, requestedQuantity)
    return try withDatabaseLock {
      guard let list = try cardListUnlocked(id: listID) else {
        throw CardListDatabaseError.listNotFound
      }
      var zone = list.ruleset.normalizedZone(requestedZone)
      var categoryID = categoryID
      if let resolvedCategoryID = categoryID {
        guard let category = try cardListCategoryUnlocked(id: resolvedCategoryID),
          category.listID == listID
        else {
          throw CardListDatabaseError.categoryNotFound
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
        if let existingEntry = try matchingCardListEntryUnlocked(
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

        try touchCardListUnlocked(id: listID, date: date)
      }

      guard var entry = try matchingCardListEntryUnlocked(
        listID: listID,
        zone: zone,
        categoryID: categoryID,
        cardID: cardID,
        excluding: nil
      ) else {
        throw CardListDatabaseError.entryNotFound
      }
      entry.card = try card(id: cardID)
      return entry
    }
  }

  @discardableResult
  public func replaceCardListEntryPrint(
    id: String,
    withCardID cardID: String,
    now: Date = Date()
  ) throws -> CardListEntryRecord {
    try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
      }

      guard entry.cardID != cardID else {
        var current = entry
        current.card = try card(id: current.cardID)
        return current
      }

      let date = Self.formattedListDate(now)
      var updatedEntryID = id

      try database.transaction {
        if let existingEntry = try matchingCardListEntryUnlocked(
          listID: entry.listID,
          zone: entry.zone,
          categoryID: entry.categoryID,
          cardID: cardID,
          excluding: entry.id
        ) {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET quantity = quantity + ?
            WHERE id = ?
            """)
          try update.bind(entry.quantity, at: 1)
          try update.bind(existingEntry.id, at: 2)
          try update.step()

          let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
          try delete.bind(entry.id, at: 1)
          try delete.step()

          updatedEntryID = existingEntry.id
        } else {
          let update = try database.prepare(
            """
            UPDATE card_list_entries
            SET card_id = ?
            WHERE id = ?
            """)
          try update.bind(cardID, at: 1)
          try update.bind(entry.id, at: 2)
          try update.step()
        }

        try touchCardListUnlocked(id: entry.listID, date: date)
      }

      guard var updatedEntry = try cardListEntryUnlocked(id: updatedEntryID) else {
        throw CardListDatabaseError.entryNotFound
      }
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  public func removeCardListEntry(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
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
            entityType: .cardListEntry,
            recordID: recordID,
            deletedAt: now
          )
        }

        try touchCardListUnlocked(id: entry.listID, date: Self.formattedListDate(now))
      }
    }
  }

  @discardableResult
  public func incrementCardListEntryQuantity(
    id: String,
    by amount: Int = 1,
    now: Date = Date()
  ) throws -> CardListEntryRecord {
    let quantityDelta = max(1, amount)
    return try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
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
        try touchCardListUnlocked(id: entry.listID, date: Self.formattedListDate(now))
      }

      guard var updatedEntry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
      }
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  @discardableResult
  public func setCardListEntryQuantity(
    id: String,
    quantity requestedQuantity: Int,
    now: Date = Date()
  ) throws -> CardListEntryRecord {
    let quantity = max(1, requestedQuantity)
    return try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
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
        try touchCardListUnlocked(id: entry.listID, date: Self.formattedListDate(now))
      }

      guard var updatedEntry = try cardListEntryUnlocked(id: id) else {
        throw CardListDatabaseError.entryNotFound
      }
      updatedEntry.card = try card(id: updatedEntry.cardID)
      return updatedEntry
    }
  }

  public func removeCardListEntryCompletely(id: String, now: Date = Date()) throws {
    try withDatabaseLock {
      guard let entry = try cardListEntryUnlocked(id: id) else {
        return
      }

      try database.transaction {
        let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")
        try delete.bind(id, at: 1)
        try delete.step()
        let recordID = try cloudSyncEntryRecordIDUnlocked(for: entry)
        try insertSyncTombstoneUnlocked(
          entityType: .cardListEntry,
          recordID: recordID,
          deletedAt: now
        )
        try touchCardListUnlocked(id: entry.listID, date: Self.formattedListDate(now))
      }
    }
  }

  private func cloudSyncEntryRecordIDUnlocked(
    for entry: CardListEntryRecord
  ) throws -> CardListEntryRecord.ID {
    guard let list = try cardListUnlocked(id: entry.listID),
      CloudSyncEntityCodec.isFavouritesListName(list.name)
        || list.id == CloudSyncEntityCodec.favouritesListID
    else {
      return entry.id
    }
    return CloudSyncEntityCodec.favouriteEntryID(cardID: entry.cardID)
  }

  func normalizeCardListZonesForRulesetsUnlocked() throws {
    let lists = try cardListsUnlocked()
    let date = Self.formattedListDate(Date())
    try database.transaction {
      for list in lists {
        try normalizeCardListZonesUnlocked(listID: list.id, ruleset: list.ruleset, date: date)
      }
    }
  }

  @discardableResult
  func normalizeCardListZonesUnlocked(
    listID: String,
    ruleset: CardListRuleset,
    date: String
  ) throws -> Bool {
    var changed = false
    var categories = try cardListCategoriesUnlocked(forListID: listID)

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
          SET zone = ?, category_id = ?
          WHERE list_id = ? AND category_id = ?
          """)
        try updateEntries.bind(destinationZone.rawValue, at: 1)
        try updateEntries.bind(existingCategory.id, at: 2)
        try updateEntries.bind(listID, at: 3)
        try updateEntries.bind(category.id, at: 4)
        try updateEntries.step()

        let deleteCategory = try database.prepare("DELETE FROM card_list_categories WHERE id = ?")
        try deleteCategory.bind(category.id, at: 1)
        try deleteCategory.step()

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
          SET zone = ?
          WHERE list_id = ? AND category_id = ?
          """)
        try updateEntries.bind(destinationZone.rawValue, at: 1)
        try updateEntries.bind(listID, at: 2)
        try updateEntries.bind(category.id, at: 3)
        try updateEntries.step()

        if let index = categories.firstIndex(where: { $0.id == category.id }) {
          categories[index].zone = destinationZone
        }
      }

      changed = true
    }

    categories = try cardListCategoriesUnlocked(forListID: listID)
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
        SET zone = ?
        WHERE list_id = ? AND category_id = ?
        """)
      try updateEntries.bind(category.zone.rawValue, at: 1)
      try updateEntries.bind(listID, at: 2)
      try updateEntries.bind(category.id, at: 3)
      try updateEntries.step()
      changed = true
    }

    for zone in CardListZone.allCases {
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
        SET zone = ?, category_id = NULL
        WHERE list_id = ? AND zone = ?
        """)
      try updateEntries.bind(destinationZone.rawValue, at: 1)
      try updateEntries.bind(listID, at: 2)
      try updateEntries.bind(zone.rawValue, at: 3)
      try updateEntries.step()
      changed = true
    }

    guard changed else {
      return false
    }

    try consolidateDuplicateCardListEntriesUnlocked(listID: listID)
    try normalizeCardListCategoryPositionsUnlocked(listID: listID, date: date)
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
