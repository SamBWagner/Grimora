import Foundation
import GrimoraCore
import Testing

struct SemanticStorageBenchmarkTests {
  @Test
  func hierarchyLayoutsProduceEquivalentResultsForAHundredCardDeck() throws {
    let fixture = try SemanticStorageFixture.load(cardCount: 100)
    let workspace = try SemanticStorageWorkspace()
    defer { workspace.remove() }

    let recursive = try workspace.build(layout: .recursive, fixture: fixture)
    let closure = try workspace.build(layout: .closure, fixture: fixture)
    let flattened = try workspace.build(layout: .flattened, fixture: fixture)

    let recursiveResults = try recursive.correctnessResults(fixture: fixture)
    let closureResults = try closure.correctnessResults(fixture: fixture)
    let flattenedResults = try flattened.correctnessResults(fixture: fixture)
    #expect(recursiveResults == closureResults)
    #expect(recursiveResults == flattenedResults)
    #expect(recursiveResults.featureVectors.count == 100)
    #expect(!recursiveResults.relatedCards.isEmpty)
    #expect(!recursiveResults.functionalSearch.isEmpty)
    #expect(!recursiveResults.deckProfile.isEmpty)
    #expect(!recursiveResults.inducedGraph.isEmpty)
  }

  @Test
  func reportsOptInHierarchyStorageMeasurements() throws {
    guard ProcessInfo.processInfo.environment["GRIMORA_SEMANTIC_STORAGE_BENCHMARK"] != nil else {
      return
    }

    let fixture = try SemanticStorageFixture.load(cardCount: 100)
    let workspace = try SemanticStorageWorkspace()
    defer { workspace.remove() }
    let iterations = 50

    var measurements: [SemanticStorageMeasurement] = []
    for layout in SemanticStorageLayout.allCases {
      let start = DispatchTime.now().uptimeNanoseconds
      let store = try workspace.build(layout: layout, fixture: fixture)
      let importNanoseconds = DispatchTime.now().uptimeNanoseconds - start
      let results = try store.correctnessResults(fixture: fixture)
      let queryTimings = try store.measureQueries(fixture: fixture, iterations: iterations)
      measurements.append(
        SemanticStorageMeasurement(
          layout: layout,
          databaseBytes: store.databaseBytes,
          importMilliseconds: milliseconds(importNanoseconds),
          relatedLookupMilliseconds: queryTimings.related,
          functionalSearchMilliseconds: queryTimings.functionalSearch,
          deckProfileMilliseconds: queryTimings.deckProfile,
          inducedGraphMilliseconds: queryTimings.inducedGraph,
          featureRows: results.featureVectors.values.reduce(0) { $0 + $1.count },
          inducedGraphEdges: results.inducedGraph.count
        )
      )
    }

    print("\nSEMANTIC_STORAGE_BENCHMARK_BEGIN")
    print("layout,database_bytes,import_ms,related_ms,function_search_ms,deck_profile_ms,induced_graph_ms,feature_rows,graph_edges")
    for measurement in measurements {
      print(measurement.csv)
    }
    print("SEMANTIC_STORAGE_BENCHMARK_END\n")
  }
}

private enum SemanticStorageLayout: String, CaseIterable {
  case recursive
  case closure
  case flattened
}

private struct SemanticStorageCorrectnessResults: Equatable {
  var featureVectors: [String: [String: Int]]
  var relatedCards: [SemanticStorageScoredCard]
  var functionalSearch: [String]
  var deckProfile: [SemanticStorageTagAggregate]
  var inducedGraph: [SemanticStorageGraphEdge]
}

private struct SemanticStorageScoredCard: Equatable {
  var cardKey: String
  var scoreMillis: Int
}

private struct SemanticStorageTagAggregate: Equatable {
  var tagID: String
  var weightMillis: Int
}

private struct SemanticStorageGraphEdge: Equatable {
  var lhs: String
  var rhs: String
  var scoreMillis: Int
}

private struct SemanticStorageMeasurement {
  var layout: SemanticStorageLayout
  var databaseBytes: Int
  var importMilliseconds: Double
  var relatedLookupMilliseconds: Double
  var functionalSearchMilliseconds: Double
  var deckProfileMilliseconds: Double
  var inducedGraphMilliseconds: Double
  var featureRows: Int
  var inducedGraphEdges: Int

  var csv: String {
    [
      layout.rawValue,
      String(databaseBytes),
      format(importMilliseconds),
      format(relatedLookupMilliseconds),
      format(functionalSearchMilliseconds),
      format(deckProfileMilliseconds),
      format(inducedGraphMilliseconds),
      String(featureRows),
      String(inducedGraphEdges),
    ].joined(separator: ",")
  }

  private func format(_ value: Double) -> String {
    String(format: "%.4f", value)
  }
}

private struct SemanticStorageQueryTimings {
  var related: Double
  var functionalSearch: Double
  var deckProfile: Double
  var inducedGraph: Double
}

private final class SemanticStorageStore {
  let layout: SemanticStorageLayout
  let url: URL
  let database: SQLiteDatabase

  init(layout: SemanticStorageLayout, url: URL, fixture: SemanticStorageFixture) throws {
    self.layout = layout
    self.url = url
    database = try SQLiteDatabase(storage: .file(url))
    try createSchema()
    try importFixture(fixture)
    try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    try database.execute("PRAGMA journal_mode = DELETE")
    try database.execute("VACUUM")
  }

  var databaseBytes: Int {
    let number = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    return number?.intValue ?? 0
  }

  func correctnessResults(fixture: SemanticStorageFixture) throws -> SemanticStorageCorrectnessResults {
    SemanticStorageCorrectnessResults(
      featureVectors: try featureVectors(),
      relatedCards: try relatedCards(to: fixture.deckCardKeys[0]),
      functionalSearch: try functionalSearch(slug: "draw"),
      deckProfile: try deckProfile(),
      inducedGraph: try inducedGraph()
    )
  }

  func measureQueries(
    fixture: SemanticStorageFixture,
    iterations: Int
  ) throws -> SemanticStorageQueryTimings {
    SemanticStorageQueryTimings(
      related: try averageMilliseconds(iterations: iterations) {
        _ = try relatedCards(to: fixture.deckCardKeys[0])
      },
      functionalSearch: try averageMilliseconds(iterations: iterations) {
        _ = try functionalSearch(slug: "draw")
      },
      deckProfile: try averageMilliseconds(iterations: iterations) {
        _ = try deckProfile()
      },
      inducedGraph: try averageMilliseconds(iterations: iterations) {
        _ = try inducedGraph()
      }
    )
  }

  private func createSchema() throws {
    try database.execute(
      """
      CREATE TABLE semantic_tags (
          id TEXT PRIMARY KEY,
          slug TEXT NOT NULL UNIQUE,
          similarity_enabled INTEGER NOT NULL
      );
      CREATE TABLE semantic_tag_edges (
          parent_tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
          child_tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
          PRIMARY KEY(parent_tag_id, child_tag_id)
      );
      CREATE TABLE semantic_card_tags (
          card_key TEXT NOT NULL,
          tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
          weight_millis INTEGER NOT NULL,
          PRIMARY KEY(card_key, tag_id)
      );
      CREATE TABLE benchmark_deck (
          card_key TEXT PRIMARY KEY
      );
      CREATE INDEX idx_semantic_edges_child_parent
      ON semantic_tag_edges(child_tag_id, parent_tag_id);
      CREATE INDEX idx_semantic_card_tags_tag_card
      ON semantic_card_tags(tag_id, card_key);
      CREATE INDEX idx_semantic_card_tags_card_tag
      ON semantic_card_tags(card_key, tag_id);
      """
    )

    switch layout {
    case .recursive:
      break
    case .closure:
      try database.execute(
        """
        CREATE TABLE semantic_tag_closure (
            descendant_tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
            ancestor_tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
            depth INTEGER NOT NULL,
            PRIMARY KEY(descendant_tag_id, ancestor_tag_id)
        );
        CREATE INDEX idx_semantic_tag_closure_ancestor
        ON semantic_tag_closure(ancestor_tag_id, descendant_tag_id);
        """
      )
    case .flattened:
      try database.execute(
        """
        CREATE TABLE semantic_card_features (
            card_key TEXT NOT NULL,
            tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
            weight_millis INTEGER NOT NULL,
            PRIMARY KEY(card_key, tag_id)
        );
        CREATE INDEX idx_semantic_card_features_tag_card
        ON semantic_card_features(tag_id, card_key);
        """
      )
    }
  }

  private func importFixture(_ fixture: SemanticStorageFixture) throws {
    try database.transaction {
      let tagInsert = try database.prepare(
        "INSERT INTO semantic_tags (id, slug, similarity_enabled) VALUES (?, ?, ?)"
      )
      for tag in fixture.tags {
        try tagInsert.bind(tag.id, at: 1)
        try tagInsert.bind(tag.slug, at: 2)
        try tagInsert.bind(tag.similarityEnabled, at: 3)
        _ = try tagInsert.step()
        try tagInsert.reset()
      }

      let edgeInsert = try database.prepare(
        "INSERT INTO semantic_tag_edges (parent_tag_id, child_tag_id) VALUES (?, ?)"
      )
      for edge in fixture.edges {
        try edgeInsert.bind(edge.parentID, at: 1)
        try edgeInsert.bind(edge.childID, at: 2)
        _ = try edgeInsert.step()
        try edgeInsert.reset()
      }

      let membershipInsert = try database.prepare(
        "INSERT INTO semantic_card_tags (card_key, tag_id, weight_millis) VALUES (?, ?, ?)"
      )
      for membership in fixture.memberships {
        try membershipInsert.bind(membership.cardKey, at: 1)
        try membershipInsert.bind(membership.tagID, at: 2)
        try membershipInsert.bind(membership.weightMillis, at: 3)
        _ = try membershipInsert.step()
        try membershipInsert.reset()
      }

      let deckInsert = try database.prepare("INSERT INTO benchmark_deck (card_key) VALUES (?)")
      for cardKey in fixture.deckCardKeys {
        try deckInsert.bind(cardKey, at: 1)
        _ = try deckInsert.step()
        try deckInsert.reset()
      }

      switch layout {
      case .recursive:
        break
      case .closure:
        let closureInsert = try database.prepare(
          "INSERT INTO semantic_tag_closure (descendant_tag_id, ancestor_tag_id, depth) VALUES (?, ?, ?)"
        )
        for row in fixture.closureRows {
          try closureInsert.bind(row.descendantID, at: 1)
          try closureInsert.bind(row.ancestorID, at: 2)
          try closureInsert.bind(row.depth, at: 3)
          _ = try closureInsert.step()
          try closureInsert.reset()
        }
      case .flattened:
        let featureInsert = try database.prepare(
          "INSERT INTO semantic_card_features (card_key, tag_id, weight_millis) VALUES (?, ?, ?)"
        )
        for feature in fixture.flattenedFeatures {
          try featureInsert.bind(feature.cardKey, at: 1)
          try featureInsert.bind(feature.tagID, at: 2)
          try featureInsert.bind(feature.weightMillis, at: 3)
          _ = try featureInsert.step()
          try featureInsert.reset()
        }
      }
    }
  }

  private func featureVectors() throws -> [String: [String: Int]] {
    let statement = try database.prepare(
      """
      \(effectiveFeatureCTE)
      SELECT card_key, tag_id, weight_millis
      FROM effective_features
      ORDER BY card_key, tag_id
      """
    )
    var result: [String: [String: Int]] = [:]
    while try statement.step() {
      guard let cardKey = statement.string(at: 0),
        let tagID = statement.string(at: 1),
        let weight = statement.int(at: 2)
      else {
        continue
      }
      result[cardKey, default: [:]][tagID] = weight
    }
    return result
  }

  private func relatedCards(to cardKey: String) throws -> [SemanticStorageScoredCard] {
    let statement = try database.prepare(
      """
      \(effectiveFeatureCTE),
      query_features AS (
          SELECT tag_id, weight_millis
          FROM effective_features
          WHERE card_key = ?
      )
      SELECT candidate.card_key,
             SUM(MIN(candidate.weight_millis, query_features.weight_millis)) AS score_millis
      FROM effective_features candidate
      JOIN query_features USING(tag_id)
      WHERE candidate.card_key <> ?
      GROUP BY candidate.card_key
      HAVING score_millis > 0
      ORDER BY score_millis DESC, candidate.card_key
      LIMIT 20
      """
    )
    try statement.bind(cardKey, at: 1)
    try statement.bind(cardKey, at: 2)
    var result: [SemanticStorageScoredCard] = []
    while try statement.step() {
      if let candidate = statement.string(at: 0), let score = statement.int(at: 1) {
        result.append(SemanticStorageScoredCard(cardKey: candidate, scoreMillis: score))
      }
    }
    return result
  }

  private func functionalSearch(slug: String) throws -> [String] {
    let statement = try database.prepare(
      """
      \(effectiveFeatureCTE)
      SELECT DISTINCT features.card_key
      FROM effective_features features
      JOIN semantic_tags tags ON tags.id = features.tag_id
      WHERE tags.slug = ?
      ORDER BY features.card_key
      """
    )
    try statement.bind(slug, at: 1)
    var result: [String] = []
    while try statement.step() {
      if let cardKey = statement.string(at: 0) {
        result.append(cardKey)
      }
    }
    return result
  }

  private func deckProfile() throws -> [SemanticStorageTagAggregate] {
    let statement = try database.prepare(
      """
      \(effectiveFeatureCTE)
      SELECT features.tag_id, SUM(features.weight_millis) AS total_weight
      FROM effective_features features
      JOIN benchmark_deck deck ON deck.card_key = features.card_key
      GROUP BY features.tag_id
      ORDER BY total_weight DESC, features.tag_id
      """
    )
    var result: [SemanticStorageTagAggregate] = []
    while try statement.step() {
      if let tagID = statement.string(at: 0), let weight = statement.int(at: 1) {
        result.append(SemanticStorageTagAggregate(tagID: tagID, weightMillis: weight))
      }
    }
    return result
  }

  private func inducedGraph() throws -> [SemanticStorageGraphEdge] {
    let statement = try database.prepare(
      """
      \(effectiveFeatureCTE)
      SELECT lhs.card_key,
             rhs.card_key,
             SUM(MIN(lhs.weight_millis, rhs.weight_millis)) AS score_millis
      FROM effective_features lhs
      JOIN effective_features rhs
        ON rhs.tag_id = lhs.tag_id
       AND rhs.card_key > lhs.card_key
      JOIN benchmark_deck lhs_deck ON lhs_deck.card_key = lhs.card_key
      JOIN benchmark_deck rhs_deck ON rhs_deck.card_key = rhs.card_key
      GROUP BY lhs.card_key, rhs.card_key
      HAVING score_millis > 0
      ORDER BY lhs.card_key, rhs.card_key
      """
    )
    var result: [SemanticStorageGraphEdge] = []
    while try statement.step() {
      guard let lhs = statement.string(at: 0),
        let rhs = statement.string(at: 1),
        let score = statement.int(at: 2)
      else {
        continue
      }
      result.append(SemanticStorageGraphEdge(lhs: lhs, rhs: rhs, scoreMillis: score))
    }
    return result
  }

  private var effectiveFeatureCTE: String {
    switch layout {
    case .recursive:
      """
      WITH RECURSIVE inherited_features(card_key, tag_id, weight_millis, depth) AS (
          SELECT memberships.card_key, memberships.tag_id, memberships.weight_millis, 0
          FROM semantic_card_tags memberships
          JOIN semantic_tags tags ON tags.id = memberships.tag_id
          WHERE tags.similarity_enabled = 1
          UNION ALL
          SELECT inherited.card_key,
                 edges.parent_tag_id,
                 inherited.weight_millis,
                 inherited.depth + 1
          FROM inherited_features inherited
          JOIN semantic_tag_edges edges ON edges.child_tag_id = inherited.tag_id
          JOIN semantic_tags parent ON parent.id = edges.parent_tag_id
          WHERE parent.similarity_enabled = 1
            AND inherited.depth < 32
      ),
      effective_features AS (
          SELECT card_key, tag_id, MAX(weight_millis >> depth) AS weight_millis
          FROM inherited_features
          GROUP BY card_key, tag_id
      )
      """
    case .closure:
      """
      WITH effective_features AS (
          SELECT memberships.card_key,
                 closure.ancestor_tag_id AS tag_id,
                 MAX(memberships.weight_millis >> closure.depth) AS weight_millis
          FROM semantic_card_tags memberships
          JOIN semantic_tag_closure closure ON closure.descendant_tag_id = memberships.tag_id
          JOIN semantic_tags tags ON tags.id = closure.ancestor_tag_id
          WHERE tags.similarity_enabled = 1
          GROUP BY memberships.card_key, closure.ancestor_tag_id
      )
      """
    case .flattened:
      """
      WITH effective_features AS (
          SELECT card_key, tag_id, weight_millis
          FROM semantic_card_features
      )
      """
    }
  }
}

private final class SemanticStorageWorkspace {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SemanticStorageBenchmark-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func build(
    layout: SemanticStorageLayout,
    fixture: SemanticStorageFixture
  ) throws -> SemanticStorageStore {
    try SemanticStorageStore(
      layout: layout,
      url: directory.appendingPathComponent("\(layout.rawValue).sqlite"),
      fixture: fixture
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct SemanticStorageFixture {
  var tags: [SemanticStorageTag]
  var edges: [SemanticStorageEdge]
  var memberships: [SemanticStorageMembership]
  var deckCardKeys: [String]
  var closureRows: [SemanticStorageClosureRow]
  var flattenedFeatures: [SemanticStorageMembership]

  static func load(cardCount: Int) throws -> SemanticStorageFixture {
    let cardsDocument: SemanticStorageCardsDocument = try decodeResource("SemanticCards")
    let tagsDocument: SemanticStorageTagsDocument = try decodeResource("SemanticTags")
    let tagsByID = Dictionary(uniqueKeysWithValues: tagsDocument.tags.map { ($0.id, $0) })
    let disabledIDs = disabledTagIDs(
      tagsByID: tagsByID,
      disabledRootSlugs: Set(tagsDocument.similarityDisabledRootSlugs)
    )
    let tags = tagsDocument.tags.map {
      SemanticStorageTag(id: $0.id, slug: $0.slug, similarityEnabled: !disabledIDs.contains($0.id))
    }
    let edges = tagsDocument.tags.flatMap { tag in
      tag.parentIDs.map { SemanticStorageEdge(parentID: $0, childID: tag.id) }
    }.sorted { ($0.parentID, $0.childID) < ($1.parentID, $1.childID) }
    let closureRows = closureRows(tagsByID: tagsByID)
    let taggedOracleIDs = Set(
      tagsDocument.tags.flatMap { $0.taggings.map(\.oracleID) }
    )
    let baseOracleIDs = Array(
      Set(cardsDocument.cards.map(\.oracleID)).intersection(taggedOracleIDs)
    ).sorted()
    let cardProfiles = (0..<cardCount).map { index in
      (
        key: "o:\(baseOracleIDs[index % baseOracleIDs.count])-benchmark-\(index)",
        sourceOracleID: baseOracleIDs[index % baseOracleIDs.count]
      )
    }
    let memberships = cardProfiles.flatMap { profile in
      tagsDocument.tags.flatMap { tag in
        tag.taggings.compactMap { tagging -> SemanticStorageMembership? in
          guard tagging.oracleID == profile.sourceOracleID else { return nil }
          return SemanticStorageMembership(
            cardKey: profile.key,
            tagID: tag.id,
            weightMillis: tagging.weight.millis
          )
        }
      }
    }.sorted { ($0.cardKey, $0.tagID) < ($1.cardKey, $1.tagID) }
    let enabledTagIDs = Set(tags.filter(\.similarityEnabled).map(\.id))
    let closureByDescendant = Dictionary(grouping: closureRows, by: \.descendantID)
    var flattened: [String: [String: Int]] = [:]
    for membership in memberships {
      for row in closureByDescendant[membership.tagID, default: []]
      where enabledTagIDs.contains(row.ancestorID) {
        let weight = membership.weightMillis >> row.depth
        flattened[membership.cardKey, default: [:]][row.ancestorID] = max(
          flattened[membership.cardKey, default: [:]][row.ancestorID, default: 0],
          weight
        )
      }
    }
    let flattenedFeatures = flattened.flatMap { cardKey, features in
      features.map {
        SemanticStorageMembership(cardKey: cardKey, tagID: $0.key, weightMillis: $0.value)
      }
    }.sorted { ($0.cardKey, $0.tagID) < ($1.cardKey, $1.tagID) }

    return SemanticStorageFixture(
      tags: tags,
      edges: edges,
      memberships: memberships,
      deckCardKeys: cardProfiles.map(\.key),
      closureRows: closureRows,
      flattenedFeatures: flattenedFeatures
    )
  }

  private static func closureRows(
    tagsByID: [String: SemanticStorageFixtureTag]
  ) -> [SemanticStorageClosureRow] {
    var rows: [SemanticStorageClosureRow] = []
    for tagID in tagsByID.keys.sorted() {
      var bestDepth: [String: Int] = [tagID: 0]
      var queue: [(id: String, depth: Int)] = [(tagID, 0)]
      var index = 0
      while index < queue.count {
        let current = queue[index]
        index += 1
        for parentID in tagsByID[current.id]?.parentIDs ?? [] {
          let nextDepth = current.depth + 1
          if nextDepth < bestDepth[parentID, default: .max] {
            bestDepth[parentID] = nextDepth
            queue.append((parentID, nextDepth))
          }
        }
      }
      rows.append(contentsOf: bestDepth.map {
        SemanticStorageClosureRow(descendantID: tagID, ancestorID: $0.key, depth: $0.value)
      })
    }
    return rows.sorted {
      ($0.descendantID, $0.depth, $0.ancestorID) < ($1.descendantID, $1.depth, $1.ancestorID)
    }
  }

  private static func disabledTagIDs(
    tagsByID: [String: SemanticStorageFixtureTag],
    disabledRootSlugs: Set<String>
  ) -> Set<String> {
    var memo: [String: Bool] = [:]
    func isDisabled(_ tagID: String, visiting: Set<String>) -> Bool {
      if let cached = memo[tagID] { return cached }
      guard let tag = tagsByID[tagID], !visiting.contains(tagID) else { return false }
      if disabledRootSlugs.contains(tag.slug) {
        memo[tagID] = true
        return true
      }
      var next = visiting
      next.insert(tagID)
      let result = tag.parentIDs.contains { isDisabled($0, visiting: next) }
      memo[tagID] = result
      return result
    }
    return Set(tagsByID.keys.filter { isDisabled($0, visiting: []) })
  }

  private static func decodeResource<Value: Decodable>(_ name: String) throws -> Value {
    guard let url = Bundle.module.url(
      forResource: name,
      withExtension: "json",
      subdirectory: "Fixtures"
    ) else {
      throw SemanticStorageFixtureError.missingResource(name)
    }
    return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
  }
}

private struct SemanticStorageTag {
  var id: String
  var slug: String
  var similarityEnabled: Bool
}

private struct SemanticStorageEdge {
  var parentID: String
  var childID: String
}

private struct SemanticStorageMembership {
  var cardKey: String
  var tagID: String
  var weightMillis: Int
}

private struct SemanticStorageClosureRow {
  var descendantID: String
  var ancestorID: String
  var depth: Int
}

private struct SemanticStorageCardsDocument: Decodable {
  var cards: [SemanticStorageFixtureCard]
}

private struct SemanticStorageTagsDocument: Decodable {
  var similarityDisabledRootSlugs: [String]
  var tags: [SemanticStorageFixtureTag]
}

private struct SemanticStorageFixtureCard: Decodable {
  var oracleID: String
}

private struct SemanticStorageFixtureTag: Decodable {
  var id: String
  var slug: String
  var parentIDs: [String]
  var taggings: [SemanticStorageFixtureTagging]
}

private struct SemanticStorageFixtureTagging: Decodable {
  var oracleID: String
  var weight: SemanticStorageFixtureWeight
}

private enum SemanticStorageFixtureWeight: String, Decodable {
  case weak
  case median
  case strong
  case veryStrong = "very_strong"

  var millis: Int {
    switch self {
    case .weak: 500
    case .median: 1_000
    case .strong: 1_500
    case .veryStrong: 2_000
    }
  }
}

private enum SemanticStorageFixtureError: Error {
  case missingResource(String)
}

private func averageMilliseconds(iterations: Int, body: () throws -> Void) throws -> Double {
  let start = DispatchTime.now().uptimeNanoseconds
  for _ in 0..<iterations {
    try body()
  }
  return milliseconds(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations)
}

private func milliseconds(_ nanoseconds: UInt64) -> Double {
  Double(nanoseconds) / 1_000_000
}
