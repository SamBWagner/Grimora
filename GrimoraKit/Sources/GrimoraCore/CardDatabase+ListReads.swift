import Foundation

extension CardDatabase {
  func cardListsUnlocked() throws -> [CardListRecord] {
    let statement = try database.prepare(
      """
      SELECT
          card_lists.id,
          card_lists.name,
          card_lists.ruleset,
          card_lists.description_rtfd,
          card_lists.description_plain_text,
          card_lists.created_at,
          card_lists.updated_at,
          card_lists.is_pinned,
          card_lists.pinned_at,
          card_lists.position,
          card_lists.shows_dashboard,
          card_lists.dashboard_includes_lands,
          card_lists.display_sort_mode,
          card_lists.display_sort_direction,
          card_lists.view_mode,
          COALESCE(SUM(card_list_entries.quantity), 0) AS entry_count
      FROM card_lists
      LEFT JOIN card_list_entries ON card_list_entries.list_id = card_lists.id
      GROUP BY card_lists.id
      ORDER BY card_lists.is_pinned DESC, card_lists.position ASC, card_lists.created_at ASC, card_lists.id ASC
      """)

    var lists: [CardListRecord] = []
    while try statement.step() {
      lists.append(readCardList(from: statement))
    }
    return lists
  }

  func cardListUnlocked(id: String) throws -> CardListRecord? {
    let statement = try database.prepare(
      """
      SELECT
          card_lists.id,
          card_lists.name,
          card_lists.ruleset,
          card_lists.description_rtfd,
          card_lists.description_plain_text,
          card_lists.created_at,
          card_lists.updated_at,
          card_lists.is_pinned,
          card_lists.pinned_at,
          card_lists.position,
          card_lists.shows_dashboard,
          card_lists.dashboard_includes_lands,
          card_lists.display_sort_mode,
          card_lists.display_sort_direction,
          card_lists.view_mode,
          COALESCE(SUM(card_list_entries.quantity), 0) AS entry_count
      FROM card_lists
      LEFT JOIN card_list_entries ON card_list_entries.list_id = card_lists.id
      WHERE card_lists.id = ?
      GROUP BY card_lists.id
      LIMIT 1
      """)
    try statement.bind(id, at: 1)

    guard try statement.step() else {
      return nil
    }
    return readCardList(from: statement)
  }

  func cardListsUnlocked(
    isPinned: Bool,
    ordering: CardListPositionOrdering
  ) throws -> [CardListRecord] {
    let orderClause: String
    switch ordering {
    case .storedPosition:
      orderClause = "card_lists.position ASC, card_lists.created_at ASC, card_lists.id ASC"
    case .legacySidebarOrder:
      if isPinned {
        orderClause = "card_lists.pinned_at DESC, card_lists.id ASC"
      } else {
        orderClause = "card_lists.created_at ASC, card_lists.id ASC"
      }
    }

    let statement = try database.prepare(
      """
      SELECT
          card_lists.id,
          card_lists.name,
          card_lists.ruleset,
          card_lists.description_rtfd,
          card_lists.description_plain_text,
          card_lists.created_at,
          card_lists.updated_at,
          card_lists.is_pinned,
          card_lists.pinned_at,
          card_lists.position,
          card_lists.shows_dashboard,
          card_lists.dashboard_includes_lands,
          card_lists.display_sort_mode,
          card_lists.display_sort_direction,
          card_lists.view_mode,
          COALESCE(SUM(card_list_entries.quantity), 0) AS entry_count
      FROM card_lists
      LEFT JOIN card_list_entries ON card_list_entries.list_id = card_lists.id
      WHERE card_lists.is_pinned = ?
      GROUP BY card_lists.id
      ORDER BY \(orderClause)
      """)
    try statement.bind(isPinned, at: 1)

    var lists: [CardListRecord] = []
    while try statement.step() {
      lists.append(readCardList(from: statement))
    }
    return lists
  }

  func cardListCategoriesUnlocked(forListID listID: String) throws -> [CardListCategoryRecord] {
    let statement = try database.prepare(
      """
      SELECT
          card_list_categories.id,
          card_list_categories.list_id,
          card_list_categories.zone,
          card_list_categories.name,
          card_list_categories.position,
          card_list_categories.created_at,
          card_list_categories.updated_at,
          COALESCE(SUM(card_list_entries.quantity), 0) AS entry_count
      FROM card_list_categories
      LEFT JOIN card_list_entries ON card_list_entries.category_id = card_list_categories.id
      WHERE card_list_categories.list_id = ?
      GROUP BY card_list_categories.id
      ORDER BY card_list_categories.zone ASC, card_list_categories.position ASC, card_list_categories.created_at ASC, card_list_categories.id ASC
      """)
    try statement.bind(listID, at: 1)

    var categories: [CardListCategoryRecord] = []
    while try statement.step() {
      categories.append(readCardListCategory(from: statement))
    }
    return categories
  }

  func cardListCategoriesUnlocked() throws -> [CardListCategoryRecord] {
    let statement = try database.prepare(
      """
      SELECT
          card_list_categories.id,
          card_list_categories.list_id,
          card_list_categories.zone,
          card_list_categories.name,
          card_list_categories.position,
          card_list_categories.created_at,
          card_list_categories.updated_at,
          COALESCE(SUM(card_list_entries.quantity), 0) AS entry_count
      FROM card_list_categories
      LEFT JOIN card_list_entries ON card_list_entries.category_id = card_list_categories.id
      GROUP BY card_list_categories.id
      ORDER BY card_list_categories.list_id ASC, card_list_categories.zone ASC,
          card_list_categories.position ASC, card_list_categories.created_at ASC, card_list_categories.id ASC
      """)

    var categories: [CardListCategoryRecord] = []
    while try statement.step() {
      categories.append(readCardListCategory(from: statement))
    }
    return categories
  }

  func cardListCategoryUnlocked(id: String) throws -> CardListCategoryRecord? {
    let statement = try database.prepare(
      """
      SELECT
          card_list_categories.id,
          card_list_categories.list_id,
          card_list_categories.zone,
          card_list_categories.name,
          card_list_categories.position,
          card_list_categories.created_at,
          card_list_categories.updated_at,
          COALESCE(SUM(card_list_entries.quantity), 0) AS entry_count
      FROM card_list_categories
      LEFT JOIN card_list_entries ON card_list_entries.category_id = card_list_categories.id
      WHERE card_list_categories.id = ?
      GROUP BY card_list_categories.id
      LIMIT 1
      """)
    try statement.bind(id, at: 1)

    guard try statement.step() else {
      return nil
    }
    return readCardListCategory(from: statement)
  }

  func cardListEntryUnlocked(id: String) throws -> CardListEntryRecord? {
    let statement = try database.prepare(
      """
      SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at
      FROM card_list_entries
      WHERE id = ?
      LIMIT 1
      """)
    try statement.bind(id, at: 1)

    guard try statement.step() else {
      return nil
    }
    return readCardListEntry(from: statement)
  }

  func cardListEntriesUnlocked() throws -> [CardListEntryRecord] {
    let statement = try database.prepare(
      """
      SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at
      FROM card_list_entries
      ORDER BY list_id ASC, zone ASC, position ASC, created_at ASC, id ASC
      """)

    var entries: [CardListEntryRecord] = []
    while try statement.step() {
      entries.append(readCardListEntry(from: statement))
    }
    return entries
  }

  func matchingCardListEntryUnlocked(
    listID: String,
    zone: CardListZone,
    categoryID: String?,
    cardID: String,
    excluding excludedID: String?
  ) throws -> CardListEntryRecord? {
    let statement: SQLiteStatement
    if let excludedID {
      statement = try database.prepare(
        """
        SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at
        FROM card_list_entries
        WHERE list_id = ? AND zone = ? AND category_id IS ? AND card_id = ? AND id != ?
        ORDER BY position ASC, created_at ASC, id ASC
        LIMIT 1
        """)
      try statement.bind(listID, at: 1)
      try statement.bind(zone.rawValue, at: 2)
      try statement.bind(categoryID, at: 3)
      try statement.bind(cardID, at: 4)
      try statement.bind(excludedID, at: 5)
    } else {
      statement = try database.prepare(
        """
        SELECT id, list_id, zone, category_id, card_id, position, quantity, created_at
        FROM card_list_entries
        WHERE list_id = ? AND zone = ? AND category_id IS ? AND card_id = ?
        ORDER BY position ASC, created_at ASC, id ASC
        LIMIT 1
        """)
      try statement.bind(listID, at: 1)
      try statement.bind(zone.rawValue, at: 2)
      try statement.bind(categoryID, at: 3)
      try statement.bind(cardID, at: 4)
    }

    guard try statement.step() else {
      return nil
    }
    return readCardListEntry(from: statement)
  }

  func cardListCategoryNameExistsUnlocked(
    inList listID: String,
    zone: CardListZone,
    named name: String,
    excluding excludedID: String?
  ) throws -> Bool {
    let statement: SQLiteStatement
    if let excludedID {
      statement = try database.prepare(
        """
        SELECT 1
        FROM card_list_categories
        WHERE list_id = ? AND zone = ? AND name = ? COLLATE NOCASE AND id != ?
        LIMIT 1
        """)
      try statement.bind(listID, at: 1)
      try statement.bind(zone.rawValue, at: 2)
      try statement.bind(name, at: 3)
      try statement.bind(excludedID, at: 4)
    } else {
      statement = try database.prepare(
        """
        SELECT 1
        FROM card_list_categories
        WHERE list_id = ? AND zone = ? AND name = ? COLLATE NOCASE
        LIMIT 1
        """)
      try statement.bind(listID, at: 1)
      try statement.bind(zone.rawValue, at: 2)
      try statement.bind(name, at: 3)
    }

    return try statement.step()
  }

  func touchCardListUnlocked(id: String, date: String) throws {
    let statement = try database.prepare(
      """
      UPDATE card_lists
      SET updated_at = ?
      WHERE id = ?
      """)
    try statement.bind(date, at: 1)
    try statement.bind(id, at: 2)
    try statement.step()
  }

  func nextCardListPositionUnlocked(isPinned: Bool) throws -> Int {
    let statement = try database.prepare(
      """
      SELECT COALESCE(MAX(position), -1) + 1
      FROM card_lists
      WHERE is_pinned = ?
      """)
    try statement.bind(isPinned, at: 1)
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  func normalizeCardListPositionsUnlocked(ordering: CardListPositionOrdering) throws {
    let pinnedLists = try cardListsUnlocked(isPinned: true, ordering: ordering)
    let unpinnedLists = try cardListsUnlocked(isPinned: false, ordering: ordering)
    try updateCardListPositionsUnlocked(pinnedLists)
    try updateCardListPositionsUnlocked(unpinnedLists)
  }

  func updateCardListPositionsUnlocked(_ lists: [CardListRecord]) throws {
    let statement = try database.prepare(
      """
      UPDATE card_lists
      SET position = ?
      WHERE id = ?
      """)
    for (position, list) in lists.enumerated() {
      try statement.bind(position, at: 1)
      try statement.bind(list.id, at: 2)
      try statement.step()
      try statement.reset()
    }
  }

  func normalizeCardListCategoryPositionsUnlocked(listID: String, date: String) throws {
    let categories = try cardListCategoriesUnlocked(forListID: listID)
    try updateCardListCategoryPositionsUnlocked(categories, date: date)
  }

  func updateCardListCategoryPositionsUnlocked(
    _ categories: [CardListCategoryRecord],
    date: String
  ) throws {
    let statement = try database.prepare(
      """
      UPDATE card_list_categories
      SET position = ?, updated_at = ?
      WHERE id = ?
      """)
    for (position, category) in categories.enumerated() {
      try statement.bind(position, at: 1)
      try statement.bind(date, at: 2)
      try statement.bind(category.id, at: 3)
      try statement.step()
      try statement.reset()
    }
  }

  func readCardList(from statement: SQLiteStatement) -> CardListRecord {
    CardListRecord(
      id: statement.string(at: 0) ?? "",
      name: statement.string(at: 1) ?? "",
      ruleset: CardListRuleset(rawValueOrDefault: statement.string(at: 2)),
      descriptionRTFDData: statement.data(at: 3),
      descriptionPlainText: statement.string(at: 4) ?? "",
      createdAt: Self.parseListDate(statement.string(at: 5)),
      updatedAt: Self.parseListDate(statement.string(at: 6)),
      isPinned: statement.bool(at: 7),
      pinnedAt: statement.string(at: 8).flatMap { Self.parseListDate($0) },
      position: statement.int(at: 9) ?? 0,
      showsDashboard: statement.bool(at: 10),
      dashboardIncludesLands: statement.bool(at: 11),
      displaySortMode: statement.string(at: 12).flatMap(SortMode.init(rawValue:)),
      displaySortDirection: SearchSortDirection(rawValue: statement.string(at: 13) ?? "")
        ?? .ascending,
      viewMode: CardListViewMode(rawValueOrDefault: statement.string(at: 14)),
      entryCount: statement.int(at: 15) ?? 0
    )
  }

  func readCardListCategory(from statement: SQLiteStatement) -> CardListCategoryRecord {
    CardListCategoryRecord(
      id: statement.string(at: 0) ?? "",
      listID: statement.string(at: 1) ?? "",
      zone: CardListZone(rawValueOrDefault: statement.string(at: 2)),
      name: statement.string(at: 3) ?? "",
      position: statement.int(at: 4) ?? 0,
      createdAt: Self.parseListDate(statement.string(at: 5)),
      updatedAt: Self.parseListDate(statement.string(at: 6)),
      entryCount: statement.int(at: 7) ?? 0
    )
  }

  func readCardListEntry(from statement: SQLiteStatement) -> CardListEntryRecord {
    CardListEntryRecord(
      id: statement.string(at: 0) ?? "",
      listID: statement.string(at: 1) ?? "",
      zone: CardListZone(rawValueOrDefault: statement.string(at: 2)),
      categoryID: statement.string(at: 3),
      cardID: statement.string(at: 4) ?? "",
      position: statement.int(at: 5) ?? 0,
      quantity: max(1, statement.int(at: 6) ?? 1),
      createdAt: Self.parseListDate(statement.string(at: 7))
    )
  }

  static func normalizedListName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func isImplicitCategoryName(_ name: String) -> Bool {
    name.caseInsensitiveCompare("Uncategorized") == .orderedSame
  }

  static func parseListDate(_ value: String?) -> Date {
    value.flatMap { isoListDateFormatter().date(from: $0) } ?? Date(timeIntervalSince1970: 0)
  }

  static func formattedListDate(_ date: Date) -> String {
    isoListDateFormatter().string(from: date)
  }

  static func isoListDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }
}
