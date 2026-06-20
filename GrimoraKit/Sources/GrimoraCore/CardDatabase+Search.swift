import Foundation

extension CardDatabase {
  public func search(_ request: CardSearchRequest) throws -> CardSearchResponse {
    try withDatabaseLock {
      let pageLimit = max(0, request.limit)
      let pageOffset = max(0, request.offset)
      let plan: SearchQueryPlan
      switch SearchQuery.compile(request.text) {
      case .success(let compiledPlan):
        plan = compiledPlan
      case .failure(let reason):
        return .unsupported(reason)
      }

      var whereClauses: [String] = []
      let bindings = plan.bindings

      if let whereSQL = plan.whereSQL {
        whereClauses.append(whereSQL)
      }

      if plan.displayOptions.preferences.contains(.notUniversesBeyond) {
        whereClauses.append("is_universes_beyond = 0")
      }

      let whereSQL = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
      let printingDisplayMode = plan.displayOptions.printingDisplayMode ?? request.printingDisplayMode
      let sortMode = plan.displayOptions.sortMode ?? request.sortMode
      let sortDirection = plan.displayOptions.sortDirection ?? request.sortDirection
      let orderClause = sortMode.sqlOrderClause(direction: sortDirection)
      let shouldPageInSQL = !plan.hasPostFilters
      let pageSQL = shouldPageInSQL ? "LIMIT ? OFFSET ?" : ""
      let countSQL: String
      let sql: String
      switch printingDisplayMode {
      case .all:
        countSQL = """
          SELECT COUNT(*)
          FROM cards
          \(whereSQL)
          """
        sql = """
          SELECT \(Self.cardColumns)
          FROM cards
          \(whereSQL)
          ORDER BY \(orderClause)
          \(pageSQL)
          """
      case .art:
        let rankedCardsSQL = """
          WITH ranked_cards AS (
              SELECT
                  id,
                  ROW_NUMBER() OVER (
                      PARTITION BY COALESCE(illustration_id, id)
                      ORDER BY \(Self.preferredPrintingOrderClause(preferences: plan.displayOptions.preferences))
                  ) AS printing_rank
              FROM cards
              \(whereSQL)
          )
          """
        countSQL = """
          \(rankedCardsSQL)
          SELECT COUNT(*)
          FROM ranked_cards
          WHERE printing_rank = 1
          """
        sql = """
          \(rankedCardsSQL)
          SELECT \(Self.cardColumns)
          FROM cards
          WHERE id IN (
              SELECT id
              FROM ranked_cards
              WHERE printing_rank = 1
          )
          ORDER BY \(orderClause)
          \(pageSQL)
          """
      case .preferred:
        let rankedCardsSQL = """
          WITH ranked_cards AS (
              SELECT
                  id,
                  ROW_NUMBER() OVER (
                      PARTITION BY display_name_key
                      ORDER BY \(Self.preferredPrintingOrderClause(preferences: plan.displayOptions.preferences))
                  ) AS printing_rank
              FROM cards
              \(whereSQL)
          )
          """
        countSQL = """
          \(rankedCardsSQL)
          SELECT COUNT(*)
          FROM ranked_cards
          WHERE printing_rank = 1
          """
        sql = """
          \(rankedCardsSQL)
          SELECT \(Self.cardColumns)
          FROM cards
          WHERE id IN (
              SELECT id
              FROM ranked_cards
              WHERE printing_rank = 1
          )
          ORDER BY \(orderClause)
          \(pageSQL)
          """
      }

      func bindSearchBindings(to statement: SQLiteStatement) throws {
        for (index, binding) in bindings.enumerated() {
          try binding.apply(to: statement, index: Int32(index + 1))
        }
      }

      func totalMatchingCardCount() throws -> Int {
        let statement = try database.prepare(countSQL)
        try bindSearchBindings(to: statement)
        _ = try statement.step()
        return statement.int(at: 0)!
      }

      let statement = try database.prepare(sql)
      try bindSearchBindings(to: statement)
      if shouldPageInSQL {
        try statement.bind(pageLimit, at: Int32(bindings.count + 1))
        try statement.bind(pageOffset, at: Int32(bindings.count + 2))
      }

      var cards: [CardRecord] = []
      var totalCount = shouldPageInSQL ? try totalMatchingCardCount() : 0
      while try statement.step() {
        cards.append(readCard(from: statement))
      }

      try hydrateFaces(for: &cards)

      if !shouldPageInSQL {
        let unfilteredCards = cards
        cards = []
        for card in unfilteredCards where plan.postFilters.allSatisfy({ $0.matches(card) }) {
          let matchingIndex = totalCount
          totalCount += 1
          if matchingIndex >= pageOffset && cards.count < pageLimit {
            cards.append(card)
          }
        }
      }

      return .results(cards, totalCount: totalCount)
    }
  }

  public func printings(for card: CardRecord) throws -> [CardRecord] {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT \(Self.cardColumns)
        FROM cards
        WHERE display_name_key = ?
        ORDER BY \(Self.preferredPrintingOrderClause(preferences: []))
        """)
      try statement.bind(card.displayNameKey.isEmpty ? card.name.sortKey : card.displayNameKey, at: 1)

      var printings: [CardRecord] = []
      while try statement.step() {
        printings.append(readCard(from: statement))
      }
      try hydrateFaces(for: &printings)
      return printings
    }
  }
}
