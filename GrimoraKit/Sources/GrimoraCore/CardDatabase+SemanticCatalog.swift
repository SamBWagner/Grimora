import Foundation

extension CardDatabase {
  func migrateSemanticCatalogSchema() throws {
    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS semantic_tags (
          id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
          namespace TEXT NOT NULL CHECK (length(trim(namespace)) > 0),
          slug TEXT NOT NULL CHECK (length(trim(slug)) > 0),
          label TEXT NOT NULL CHECK (length(trim(label)) > 0),
          description TEXT,
          similarity_enabled INTEGER NOT NULL DEFAULT 1 CHECK (similarity_enabled IN (0, 1)),
          source TEXT NOT NULL CHECK (length(trim(source)) > 0),
          UNIQUE(source, slug)
      );

      CREATE TABLE IF NOT EXISTS semantic_tag_aliases (
          tag_id TEXT NOT NULL CHECK (length(trim(tag_id)) > 0)
              REFERENCES semantic_tags(id) ON DELETE CASCADE,
          alias TEXT NOT NULL CHECK (length(trim(alias)) > 0),
          alias_key TEXT NOT NULL CHECK (length(trim(alias_key)) > 0),
          PRIMARY KEY(tag_id, alias_key)
      );

      CREATE TABLE IF NOT EXISTS semantic_tag_edges (
          parent_tag_id TEXT NOT NULL CHECK (length(trim(parent_tag_id)) > 0)
              REFERENCES semantic_tags(id) ON DELETE CASCADE,
          child_tag_id TEXT NOT NULL CHECK (length(trim(child_tag_id)) > 0)
              REFERENCES semantic_tags(id) ON DELETE CASCADE,
          PRIMARY KEY(parent_tag_id, child_tag_id),
          CHECK(parent_tag_id <> child_tag_id)
      );

      CREATE TABLE IF NOT EXISTS semantic_card_tags (
          card_key TEXT NOT NULL CHECK (
              substr(card_key, 1, 2) IN ('o:', 'p:')
              AND length(trim(substr(card_key, 3))) > 0
          ),
          tag_id TEXT NOT NULL CHECK (length(trim(tag_id)) > 0)
              REFERENCES semantic_tags(id) ON DELETE CASCADE,
          weight_millis INTEGER NOT NULL CHECK (weight_millis >= 0),
          annotation TEXT,
          source TEXT NOT NULL CHECK (length(trim(source)) > 0),
          PRIMARY KEY(card_key, tag_id, source)
      );

      CREATE TABLE IF NOT EXISTS semantic_tag_stats (
          tag_id TEXT PRIMARY KEY CHECK (length(trim(tag_id)) > 0)
              REFERENCES semantic_tags(id) ON DELETE CASCADE,
          direct_card_count INTEGER NOT NULL CHECK (direct_card_count >= 0),
          effective_card_count INTEGER NOT NULL CHECK (
              effective_card_count >= direct_card_count
          ),
          idf_millis INTEGER NOT NULL CHECK (idf_millis >= 0)
      );

      CREATE INDEX IF NOT EXISTS idx_semantic_tag_aliases_key
      ON semantic_tag_aliases(alias_key, tag_id);

      CREATE INDEX IF NOT EXISTS idx_semantic_tag_edges_child_parent
      ON semantic_tag_edges(child_tag_id, parent_tag_id);

      CREATE INDEX IF NOT EXISTS idx_semantic_card_tags_tag_card
      ON semantic_card_tags(tag_id, card_key);

      CREATE INDEX IF NOT EXISTS idx_semantic_card_tags_card_tag
      ON semantic_card_tags(card_key, tag_id);
      """
    )
  }

  public func replaceSemanticCatalog(with snapshot: SemanticCatalogSnapshot) throws {
    guard !usesExternalCatalog else {
      throw CatalogStorageError.invalidCatalog("Attached catalogs are replaced as files")
    }

    try withDatabaseLock {
      try database.transaction {
        try validateSemanticCatalog(snapshot)

        try database.execute("DELETE FROM semantic_tag_stats")
        try database.execute("DELETE FROM semantic_card_tags")
        try database.execute("DELETE FROM semantic_tag_edges")
        try database.execute("DELETE FROM semantic_tag_aliases")
        try database.execute("DELETE FROM semantic_tags")

        let tagInsert = try database.prepare(
          """
          INSERT INTO semantic_tags (
              id, namespace, slug, label, description, similarity_enabled, source
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          """
        )
        for tag in snapshot.tags {
          try tagInsert.bind(tag.id, at: 1)
          try tagInsert.bind(tag.namespace, at: 2)
          try tagInsert.bind(tag.slug, at: 3)
          try tagInsert.bind(tag.label, at: 4)
          try tagInsert.bind(tag.description, at: 5)
          try tagInsert.bind(tag.similarityEnabled, at: 6)
          try tagInsert.bind(tag.source, at: 7)
          _ = try tagInsert.step()
          try tagInsert.reset()
        }

        let aliasInsert = try database.prepare(
          """
          INSERT INTO semantic_tag_aliases (tag_id, alias, alias_key)
          VALUES (?, ?, ?)
          """
        )
        for alias in snapshot.aliases {
          try aliasInsert.bind(alias.tagID, at: 1)
          try aliasInsert.bind(alias.alias, at: 2)
          try aliasInsert.bind(alias.aliasKey, at: 3)
          _ = try aliasInsert.step()
          try aliasInsert.reset()
        }

        let edgeInsert = try database.prepare(
          """
          INSERT INTO semantic_tag_edges (parent_tag_id, child_tag_id)
          VALUES (?, ?)
          """
        )
        for edge in snapshot.edges {
          try edgeInsert.bind(edge.parentTagID, at: 1)
          try edgeInsert.bind(edge.childTagID, at: 2)
          _ = try edgeInsert.step()
          try edgeInsert.reset()
        }

        let cardTagInsert = try database.prepare(
          """
          INSERT INTO semantic_card_tags (
              card_key, tag_id, weight_millis, annotation, source
          ) VALUES (?, ?, ?, ?, ?)
          """
        )
        for cardTag in snapshot.cardTags {
          try cardTagInsert.bind(cardTag.cardKey.rawValue, at: 1)
          try cardTagInsert.bind(cardTag.tagID, at: 2)
          try cardTagInsert.bind(cardTag.weightMillis, at: 3)
          try cardTagInsert.bind(cardTag.annotation, at: 4)
          try cardTagInsert.bind(cardTag.source, at: 5)
          _ = try cardTagInsert.step()
          try cardTagInsert.reset()
        }

        let statsInsert = try database.prepare(
          """
          INSERT INTO semantic_tag_stats (
              tag_id, direct_card_count, effective_card_count, idf_millis
          ) VALUES (?, ?, ?, ?)
          """
        )
        for stats in snapshot.stats {
          try statsInsert.bind(stats.tagID, at: 1)
          try statsInsert.bind(stats.directCardCount, at: 2)
          try statsInsert.bind(stats.effectiveCardCount, at: 3)
          try statsInsert.bind(stats.inverseFrequencyMillis, at: 4)
          _ = try statsInsert.step()
          try statsInsert.reset()
        }
      }
    }
  }

  public func semanticCatalogSnapshot() throws -> SemanticCatalogSnapshot {
    try withDatabaseLock {
      guard try semanticCatalogAvailableUnlocked() else {
        return .empty
      }
      return SemanticCatalogSnapshot(
        tags: try semanticTagsUnlocked(),
        aliases: try semanticAliasesUnlocked(),
        edges: try semanticEdgesUnlocked(),
        cardTags: try semanticCardTagsUnlocked(),
        stats: try semanticStatsUnlocked()
      )
    }
  }

  public func semanticTagIDs(for cardKey: SemanticCardKey) throws -> [String] {
    try withDatabaseLock {
      guard try semanticCatalogAvailableUnlocked() else {
        return []
      }
      let statement = try database.prepare(
        """
        SELECT DISTINCT tag_id
        FROM semantic_card_tags
        WHERE card_key = ?
        ORDER BY tag_id
        """
      )
      try statement.bind(cardKey.rawValue, at: 1)
      var result: [String] = []
      while try statement.step() {
        if let tagID = statement.string(at: 0) {
          result.append(tagID)
        }
      }
      return result
    }
  }

  public func semanticCardKeys(tagID: String) throws -> [SemanticCardKey] {
    try withDatabaseLock {
      guard try semanticCatalogAvailableUnlocked() else {
        return []
      }
      let statement = try database.prepare(
        """
        SELECT DISTINCT card_key
        FROM semantic_card_tags
        WHERE tag_id = ?
        ORDER BY card_key
        """
      )
      try statement.bind(tagID, at: 1)
      var result: [SemanticCardKey] = []
      while try statement.step() {
        if let rawValue = statement.string(at: 0) {
          result.append(SemanticCardKey(rawValue: rawValue))
        }
      }
      return result
    }
  }

  private func semanticCatalogAvailableUnlocked() throws -> Bool {
    let schema = usesExternalCatalog ? Self.catalogSchemaName : "main"
    let statement = try database.prepare(
      "SELECT 1 FROM \(schema).sqlite_master WHERE type = 'table' AND name = 'semantic_tags' COLLATE NOCASE LIMIT 1"
    )
    return try statement.step()
  }

  private func validateSemanticCatalog(_ snapshot: SemanticCatalogSnapshot) throws {
    let tagIDs = Set(snapshot.tags.map(\.id))
    guard tagIDs.count == snapshot.tags.count else {
      throw CatalogStorageError.invalidCatalog("Semantic tag identifiers must be unique")
    }

    for tag in snapshot.tags {
      guard !tag.id.isBlank,
        !tag.namespace.isBlank,
        !tag.slug.isBlank,
        !tag.label.isBlank,
        !tag.source.isBlank
      else {
        throw CatalogStorageError.invalidCatalog("Semantic tags require non-empty identity fields")
      }
    }

    var aliasIdentities: Set<String> = []
    for alias in snapshot.aliases {
      guard tagIDs.contains(alias.tagID),
        !alias.alias.isBlank,
        !alias.aliasKey.isBlank,
        alias.aliasKey == SemanticTagAliasRecord.normalizedKey(for: alias.alias)
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic aliases must be normalized and reference a tag"
        )
      }
      guard aliasIdentities.insert("\(alias.tagID)\u{0}\(alias.aliasKey)").inserted else {
        throw CatalogStorageError.invalidCatalog("Semantic aliases must be unique per tag")
      }
    }

    var edgeIdentities: Set<String> = []
    var childrenByParent: [String: [String]] = [:]
    for edge in snapshot.edges {
      guard tagIDs.contains(edge.parentTagID),
        tagIDs.contains(edge.childTagID),
        edge.parentTagID != edge.childTagID
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic hierarchy edges must reference distinct tags"
        )
      }
      guard edgeIdentities.insert("\(edge.parentTagID)\u{0}\(edge.childTagID)").inserted else {
        throw CatalogStorageError.invalidCatalog("Semantic hierarchy edges must be unique")
      }
      childrenByParent[edge.parentTagID, default: []].append(edge.childTagID)
    }
    try validateAcyclicSemanticHierarchy(tagIDs: tagIDs, childrenByParent: childrenByParent)

    var membershipIdentities: Set<String> = []
    for cardTag in snapshot.cardTags {
      guard cardTag.cardKey.hasValidIdentity,
        tagIDs.contains(cardTag.tagID),
        cardTag.weightMillis >= 0,
        !cardTag.source.isBlank
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic card memberships contain invalid identity data"
        )
      }
      let identity = "\(cardTag.cardKey.rawValue)\u{0}\(cardTag.tagID)\u{0}\(cardTag.source)"
      guard membershipIdentities.insert(identity).inserted else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic card memberships must be unique per source"
        )
      }
    }

    var statsTagIDs: Set<String> = []
    for stats in snapshot.stats {
      guard tagIDs.contains(stats.tagID),
        stats.directCardCount >= 0,
        stats.effectiveCardCount >= stats.directCardCount,
        stats.inverseFrequencyMillis >= 0,
        statsTagIDs.insert(stats.tagID).inserted
      else {
        throw CatalogStorageError.invalidCatalog("Semantic statistics contain invalid values")
      }
    }
  }

  private func validateAcyclicSemanticHierarchy(
    tagIDs: Set<String>,
    childrenByParent: [String: [String]]
  ) throws {
    var visiting: Set<String> = []
    var visited: Set<String> = []

    func visit(_ tagID: String) throws {
      if visited.contains(tagID) {
        return
      }
      guard visiting.insert(tagID).inserted else {
        throw CatalogStorageError.invalidCatalog("Semantic tag hierarchy must be acyclic")
      }
      for childID in childrenByParent[tagID, default: []] {
        try visit(childID)
      }
      visiting.remove(tagID)
      visited.insert(tagID)
    }

    for tagID in tagIDs {
      try visit(tagID)
    }
  }

  private func semanticTagsUnlocked() throws -> [SemanticTagRecord] {
    let statement = try database.prepare(
      """
      SELECT id, namespace, slug, label, description, similarity_enabled, source
      FROM semantic_tags
      ORDER BY id
      """
    )
    var result: [SemanticTagRecord] = []
    while try statement.step() {
      guard let id = statement.string(at: 0),
        let namespace = statement.string(at: 1),
        let slug = statement.string(at: 2),
        let label = statement.string(at: 3),
        let similarityEnabled = statement.int(at: 5),
        let source = statement.string(at: 6)
      else {
        continue
      }
      result.append(
        SemanticTagRecord(
          id: id,
          namespace: namespace,
          slug: slug,
          label: label,
          description: statement.string(at: 4),
          similarityEnabled: similarityEnabled != 0,
          source: source
        )
      )
    }
    return result
  }

  private func semanticAliasesUnlocked() throws -> [SemanticTagAliasRecord] {
    let statement = try database.prepare(
      """
      SELECT tag_id, alias, alias_key
      FROM semantic_tag_aliases
      ORDER BY tag_id, alias_key
      """
    )
    var result: [SemanticTagAliasRecord] = []
    while try statement.step() {
      guard let tagID = statement.string(at: 0),
        let alias = statement.string(at: 1),
        let aliasKey = statement.string(at: 2)
      else {
        continue
      }
      result.append(SemanticTagAliasRecord(tagID: tagID, alias: alias, aliasKey: aliasKey))
    }
    return result
  }

  private func semanticEdgesUnlocked() throws -> [SemanticTagEdgeRecord] {
    let statement = try database.prepare(
      """
      SELECT parent_tag_id, child_tag_id
      FROM semantic_tag_edges
      ORDER BY parent_tag_id, child_tag_id
      """
    )
    var result: [SemanticTagEdgeRecord] = []
    while try statement.step() {
      guard let parentID = statement.string(at: 0), let childID = statement.string(at: 1) else {
        continue
      }
      result.append(SemanticTagEdgeRecord(parentTagID: parentID, childTagID: childID))
    }
    return result
  }

  private func semanticCardTagsUnlocked() throws -> [SemanticCardTagRecord] {
    let statement = try database.prepare(
      """
      SELECT card_key, tag_id, weight_millis, annotation, source
      FROM semantic_card_tags
      ORDER BY card_key, tag_id, source
      """
    )
    var result: [SemanticCardTagRecord] = []
    while try statement.step() {
      guard let cardKey = statement.string(at: 0),
        let tagID = statement.string(at: 1),
        let weightMillis = statement.int(at: 2),
        let source = statement.string(at: 4)
      else {
        continue
      }
      result.append(
        SemanticCardTagRecord(
          cardKey: SemanticCardKey(rawValue: cardKey),
          tagID: tagID,
          weightMillis: weightMillis,
          annotation: statement.string(at: 3),
          source: source
        )
      )
    }
    return result
  }

  private func semanticStatsUnlocked() throws -> [SemanticTagStatsRecord] {
    let statement = try database.prepare(
      """
      SELECT tag_id, direct_card_count, effective_card_count, idf_millis
      FROM semantic_tag_stats
      ORDER BY tag_id
      """
    )
    var result: [SemanticTagStatsRecord] = []
    while try statement.step() {
      guard let tagID = statement.string(at: 0),
        let directCardCount = statement.int(at: 1),
        let effectiveCardCount = statement.int(at: 2),
        let inverseFrequencyMillis = statement.int(at: 3)
      else {
        continue
      }
      result.append(
        SemanticTagStatsRecord(
          tagID: tagID,
          directCardCount: directCardCount,
          effectiveCardCount: effectiveCardCount,
          inverseFrequencyMillis: inverseFrequencyMillis
        )
      )
    }
    return result
  }
}

private extension String {
  var isBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private extension SemanticCardKey {
  var hasValidIdentity: Bool {
    guard rawValue.hasPrefix("o:") || rawValue.hasPrefix("p:") else {
      return false
    }
    return !String(rawValue.dropFirst(2)).isBlank
  }
}
