@testable import GrimoraCore
import Foundation
import XCTest

final class CatalogStorageTests: XCTestCase {
  func testAttachedCatalogKeepsCardsReadOnlyAndUserListsWritable() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("Catalog.sqlite")
    try createCatalog(at: catalogURL, cards: [Fixtures.records()[0]])

    let database = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )
    XCTAssertTrue(database.usesExternalCatalog)
    XCTAssertEqual(try database.cardCount(), 1)

    let list = try database.createCardCollection(named: "Local List")
    try database.appendCard("alpha", toList: list.id)
    XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.cardID), ["alpha"])

    var card = try XCTUnwrap(database.card(id: "alpha"))
    card.smallImagePath = "/tmp/alpha-small.jpg"
    try database.updateImagePaths(for: card)
    XCTAssertEqual(try database.card(id: "alpha")?.smallImagePath, "/tmp/alpha-small.jpg")

    let readOnlyCatalog = try SQLiteDatabase(storage: .readOnlyFile(catalogURL))
    let statement = try readOnlyCatalog.prepare("SELECT small_image_path FROM cards WHERE id = 'alpha'")
    XCTAssertTrue(try statement.step())
    XCTAssertNil(statement.string(at: 0))
  }

  func testLegacyMigrationCopiesAndVerifiesUserTablesWithoutChangingLegacy() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("Grimora.sqlite")
    let userURL = directory.appendingPathComponent("User.sqlite")
    let rawLegacy = try SQLiteDatabase(storage: .file(legacyURL))
    try rawLegacy.execute(
      """
      CREATE TABLE card_lists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
      )
      """
    )
    let legacy = try CardDatabase(storage: .file(legacyURL))
    try legacy.replaceAllCards([Fixtures.records()[0]])
    let list = try legacy.createCardCollection(named: "Migrated")
    try legacy.appendCard("alpha", toList: list.id)
    let legacySize = try fileSize(legacyURL)

    let report = try XCTUnwrap(
      CardDatabase.migrateLegacyUserDatabaseIfNeeded(
        legacyURL: legacyURL,
        userDatabaseURL: userURL,
        temporaryDirectory: directory
      ))

    XCTAssertTrue(report.isVerified)
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    XCTAssertEqual(try fileSize(legacyURL), legacySize)
    let migrated = try CardDatabase(storage: .file(userURL))
    XCTAssertEqual(try migrated.cardCollections().map(\.name), ["Migrated"])
    XCTAssertEqual(try migrated.cardCollectionEntries(forListID: list.id).map(\.cardID), ["alpha"])
  }

  func testLiveLegacyMigrationWhenConfigured() throws {
    guard let legacyPath = ProcessInfo.processInfo.environment["GRIMORA_LIVE_LEGACY_DATABASE"] else {
      throw XCTSkip(
        "Set GRIMORA_LIVE_LEGACY_DATABASE to verify migration against a production database clone."
      )
    }
    let legacyURL = URL(fileURLWithPath: legacyPath)
    let originalAttributes = try FileManager.default.attributesOfItem(atPath: legacyURL.path)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let report = try XCTUnwrap(
      CardDatabase.migrateLegacyUserDatabaseIfNeeded(
        legacyURL: legacyURL,
        userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
        temporaryDirectory: directory
      ))

    XCTAssertTrue(report.isVerified)
    XCTAssertEqual(report.sourceCounts, report.destinationCounts)
    XCTAssertTrue(report.listSnapshotMatches)
    let finalAttributes = try FileManager.default.attributesOfItem(atPath: legacyURL.path)
    XCTAssertEqual(
      (originalAttributes[.size] as? NSNumber)?.int64Value,
      (finalAttributes[.size] as? NSNumber)?.int64Value
    )
    XCTAssertEqual(
      originalAttributes[.modificationDate] as? Date,
      finalAttributes[.modificationDate] as? Date
    )
    print("Verified production migration counts: \(report.destinationCounts)")
  }

  func testCatalogInstallReplacesArtifactAndInvalidStageKeepsPreviousCatalog() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("Catalog.sqlite")
    try createCatalog(at: catalogURL, cards: [Fixtures.records()[0]])
    let database = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )

    let replacementURL = directory.appendingPathComponent("replacement.sqlite")
    try createCatalog(at: replacementURL, cards: [Fixtures.records()[1]])
    let replacementCounts = try CardDatabase.validateCatalog(at: replacementURL)
    let manifest = catalogManifest(version: "replacement", counts: replacementCounts)
    try database.installCatalog(from: replacementURL, expectedManifest: manifest)
    XCTAssertNil(try database.card(id: "alpha"))
    XCTAssertNotNil(try database.card(id: "beta"))

    let invalidURL = directory.appendingPathComponent("invalid.sqlite")
    try Data("not sqlite".utf8).write(to: invalidURL)
    XCTAssertThrowsError(
      try database.installCatalog(
        from: invalidURL,
        expectedManifest: catalogManifest(version: "invalid", counts: replacementCounts)
      ))
    XCTAssertNotNil(try database.card(id: "beta"))
  }

  func testFreshManagedBootstrapCanRelaunchBeforeCatalogInstall() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bulkClient = BulkDataClient(network: BlockingNetworkClient())

    var first: ManagedCatalogBootstrap? = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: bulkClient
    )
    XCTAssertTrue(try XCTUnwrap(first).database.usesExternalCatalog)
    XCTAssertFalse(try XCTUnwrap(first).databaseAlreadyExists)
    XCTAssertEqual(try XCTUnwrap(first).database.cardCount(), 0)
    _ = try XCTUnwrap(first).database.createCardCollection(named: "Before Catalog")
    first = nil

    let second = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: bulkClient
    )
    XCTAssertTrue(second.database.usesExternalCatalog)
    XCTAssertFalse(second.databaseAlreadyExists)
    XCTAssertEqual(try second.database.cardCount(), 0)
    XCTAssertEqual(try second.database.cardCollections().map(\.name), ["Before Catalog"])
  }

  func testManagedMigrationStagesWithoutReplacingLegacyAndActivatesLatestUserDataOnNextLaunch()
    async throws
  {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("Grimora.sqlite")
    var legacy: CardDatabase? = try CardDatabase(storage: .file(legacyURL))
    try legacy?.replaceAllCards([Fixtures.records()[0]])
    let originalList = try XCTUnwrap(legacy?.createCardCollection(named: "Before Download"))
    try legacy?.appendCard("alpha", toList: originalList.id)

    let fixture = try managedCatalogFixture(in: directory, cards: [Fixtures.records()[1]])
    let manifestURL = URL(string: "https://example.test/v1/catalog")!
    let network = RecordingNetworkClient(dataResponses: [
      manifestURL: fixture.manifestData,
      fixture.manifest.artifact.downloadURL: fixture.compressedData,
    ])
    let bulkClient = BulkDataClient(network: network, catalogAPIURL: manifestURL)

    var first: ManagedCatalogBootstrap? = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: bulkClient,
      availableCapacity: { _ in Int64.max },
      now: { Date(timeIntervalSince1970: 100) }
    )
    XCTAssertFalse(try XCTUnwrap(first).database.usesExternalCatalog)
    let service = try XCTUnwrap(try XCTUnwrap(first).migrationService)
    let staged = try await service.stageLatestCatalog(manual: false)
    XCTAssertEqual(staged.version, fixture.manifest.version)
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("Database-v2").path
      ))
    let stageRequests = await network.requests()
    XCTAssertEqual(stageRequests.map(\.1), [.manifestCheck, .automaticCatalogDownload])

    let latestList = try legacy?.createCardCollection(named: "After Download")
    XCTAssertNotNil(latestList)
    legacy = nil
    first = nil

    var second: ManagedCatalogBootstrap? = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: bulkClient,
      availableCapacity: { _ in Int64.max },
      now: { Date(timeIntervalSince1970: 100) }
    )
    XCTAssertTrue(try XCTUnwrap(second).database.usesExternalCatalog)
    XCTAssertEqual(
      try XCTUnwrap(second).database.cardCollections().map(\.name).sorted(),
      ["After Download", "Before Download"]
    )
    XCTAssertNil(try XCTUnwrap(second).database.card(id: "alpha"))
    XCTAssertNotNil(try XCTUnwrap(second).database.card(id: "beta"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    second = nil

    let third = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: bulkClient,
      availableCapacity: { _ in Int64.max },
      now: { Date(timeIntervalSince1970: 100 + ManagedCatalogMigrationService.rollbackRetention + 1) }
    )
    XCTAssertTrue(third.database.usesExternalCatalog)
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
  }

  func testManagedMigrationRejectsInsufficientDiskWithoutChangingLegacy() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("Grimora.sqlite")
    let legacy = try CardDatabase(storage: .file(legacyURL))
    try legacy.replaceAllCards([Fixtures.records()[0]])

    let fixture = try managedCatalogFixture(in: directory, cards: [Fixtures.records()[1]])
    let manifestURL = URL(string: "https://example.test/v1/catalog")!
    let network = RecordingNetworkClient(dataResponses: [
      manifestURL: fixture.manifestData,
      fixture.manifest.artifact.downloadURL: fixture.compressedData,
    ])
    let bootstrap = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: BulkDataClient(network: network, catalogAPIURL: manifestURL),
      availableCapacity: { _ in 1 }
    )

    do {
      _ = try await XCTUnwrap(bootstrap.migrationService)
        .stageLatestCatalog(manual: false)
      XCTFail("Expected insufficient disk space")
    } catch ManagedCatalogMigrationError.insufficientDiskSpace {
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(".CatalogMigrationReady").path
      ))
    let requests = await network.requests()
    XCTAssertEqual(requests.map(\.1), [.manifestCheck])
  }

  func testManagedMigrationRejectsInvalidHashAndKeepsLegacyUsable() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("Grimora.sqlite")
    let legacy = try CardDatabase(storage: .file(legacyURL))
    try legacy.replaceAllCards([Fixtures.records()[0]])

    var fixture = try managedCatalogFixture(in: directory, cards: [Fixtures.records()[1]])
    fixture.compressedData.append(0)
    let manifestURL = URL(string: "https://example.test/v1/catalog")!
    let network = RecordingNetworkClient(dataResponses: [
      manifestURL: fixture.manifestData,
      fixture.manifest.artifact.downloadURL: fixture.compressedData,
    ])
    let bootstrap = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: BulkDataClient(network: network, catalogAPIURL: manifestURL),
      availableCapacity: { _ in Int64.max }
    )

    await XCTAssertThrowsErrorAsync {
      _ = try await XCTUnwrap(bootstrap.migrationService)
        .stageLatestCatalog(manual: true)
    }
    XCTAssertEqual(try bootstrap.database.cardCount(), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
  }

  func testManagedMigrationCleansInterruptedPendingDirectory() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("Grimora.sqlite")
    let legacy = try CardDatabase(storage: .file(legacyURL))
    try legacy.replaceAllCards([Fixtures.records()[0]])
    let pending = directory.appendingPathComponent("Database.pending-interrupted", isDirectory: true)
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    try Data("partial".utf8).write(to: pending.appendingPathComponent("Catalog.sqlite"))

    let bootstrap = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: BulkDataClient(network: BlockingNetworkClient()),
      availableCapacity: { _ in Int64.max }
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
    XCTAssertFalse(bootstrap.database.usesExternalCatalog)
    XCTAssertEqual(try bootstrap.database.cardCount(), 1)
  }

  func testManagedMigrationAPIOutageAndInterruptedStagingKeepLegacyUsable() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("Grimora.sqlite")
    let legacy = try CardDatabase(storage: .file(legacyURL))
    try legacy.replaceAllCards([Fixtures.records()[0]])
    let interrupted = directory.appendingPathComponent(
      ".CatalogMigrationBuilding-interrupted",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
    try Data("partial".utf8).write(to: interrupted.appendingPathComponent("Catalog.sqlite.gz"))

    let manifestURL = URL(string: "https://example.test/v1/catalog")!
    let network = RecordingNetworkClient(errors: [
      manifestURL: NetworkClientError.badHTTPStatus(503)
    ])
    let bootstrap = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: directory,
      bulkDataClient: BulkDataClient(network: network, catalogAPIURL: manifestURL),
      availableCapacity: { _ in Int64.max }
    )

    await XCTAssertThrowsErrorAsync {
      _ = try await XCTUnwrap(bootstrap.migrationService)
        .stageLatestCatalog(manual: false)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
    XCTAssertEqual(try bootstrap.database.cardCount(), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
  }

  func testCompactSeriesRoundTripsIntoValueGuide() throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([Fixtures.records()[0]])
    var prices = [Int32](repeating: CompactCardValueSeries.missingPrice, count: 91)
    for index in prices.indices {
      prices[index] = Int32(100 + index)
    }
    _ = try database.replaceCompactCardValueHistory(
      meta: MTGJSONPriceHistoryMeta(date: "2026-06-14", version: "5.2.1"),
      mappingsByMTGJSONUUID: ["uuid-alpha": "alpha"],
      series: [
        CompactCardValueSeries(
          cardID: "alpha",
          finish: .normal,
          startDate: "2026-03-16",
          endDate: "2026-06-14",
          pricesInCents: prices
        )
      ]
    )

    let entry = try XCTUnwrap(database.valueGuide(forCardID: "alpha").entries.first)
    XCTAssertEqual(entry.currentPrice, 1.90)
    XCTAssertEqual(entry.oneDay?.previousPrice, 1.89)
    XCTAssertEqual(entry.ninetyDay?.previousPrice, 1.00)
    XCTAssertEqual(entry.history.count, 91)
  }

  func testCompactSeriesMergesMultipleMTGJSONAliasesForOneCard() throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([Fixtures.records()[0]])
    var firstAlias = [Int32](repeating: CompactCardValueSeries.missingPrice, count: 3)
    firstAlias[0] = 100
    var secondAlias = [Int32](repeating: CompactCardValueSeries.missingPrice, count: 3)
    secondAlias[2] = 200

    let summary = try database.replaceCompactCardValueHistory(
      meta: MTGJSONPriceHistoryMeta(date: "2026-06-14", version: "5.3.0"),
      mappingsByMTGJSONUUID: [
        "uuid-alpha-primary": "alpha",
        "uuid-alpha-alias": "alpha",
      ],
      series: [
        CompactCardValueSeries(
          cardID: "alpha",
          finish: .normal,
          startDate: "2026-06-12",
          endDate: "2026-06-14",
          pricesInCents: firstAlias
        ),
        CompactCardValueSeries(
          cardID: "alpha",
          finish: .normal,
          startDate: "2026-06-12",
          endDate: "2026-06-14",
          pricesInCents: secondAlias
        ),
      ]
    )

    XCTAssertEqual(summary.mappedCards, 2)
    XCTAssertEqual(summary.importedPricePoints, 3)
    XCTAssertEqual(try rowCount(in: database, table: "card_value_mappings"), 2)
    XCTAssertEqual(try rowCount(in: database, table: "card_value_series"), 1)
    let entry = try XCTUnwrap(database.valueGuide(forCardID: "alpha").entries.first)
    XCTAssertEqual(entry.currentPrice, 2.00)
    XCTAssertEqual(entry.history.map(\.price), [1.00, 1.00, 2.00])
  }

  func testMigrationAllowsMultipleMTGJSONAliasesForOneCard() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("legacy-mappings.sqlite")
    var database: CardDatabase? = try CardDatabase(storage: .file(databaseURL))
    try database?.replaceAllCards([Fixtures.records()[0]])
    try database?.database.execute("DROP TABLE card_value_mappings")
    try database?.database.execute(
      """
      CREATE TABLE card_value_mappings (
          card_id TEXT PRIMARY KEY REFERENCES cards(id) ON DELETE CASCADE,
          mtgjson_uuid TEXT NOT NULL UNIQUE
      )
      """)
    try database?.database.execute(
      "INSERT INTO card_value_mappings (card_id, mtgjson_uuid) VALUES ('alpha', 'uuid-old')")
    try database?.database.execute("DROP TABLE staging_card_value_mappings")
    try database?.database.execute(
      """
      CREATE TABLE staging_card_value_mappings (
          job_id TEXT NOT NULL REFERENCES value_history_background_jobs(id) ON DELETE CASCADE,
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          mtgjson_uuid TEXT NOT NULL,
          PRIMARY KEY (job_id, card_id),
          UNIQUE (job_id, mtgjson_uuid)
      )
      """)
    database = nil

    let migrated = try CardDatabase(storage: .file(databaseURL))
    try migrated.database.execute(
      "INSERT INTO card_value_mappings (card_id, mtgjson_uuid) VALUES ('alpha', 'uuid-new')")

    XCTAssertEqual(try rowCount(in: migrated, table: "card_value_mappings"), 2)
    XCTAssertEqual(
      try primaryKeyColumns(in: migrated, table: "card_value_mappings"),
      ["mtgjson_uuid"]
    )
    XCTAssertEqual(
      try primaryKeyColumns(in: migrated, table: "staging_card_value_mappings"),
      ["job_id", "mtgjson_uuid"]
    )
  }

  func testGzipAndSHA256RoundTrip() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.bin")
    let compressed = directory.appendingPathComponent("source.bin.gz")
    let expanded = directory.appendingPathComponent("expanded.bin")
    let data = Data((0..<50_000).map { UInt8($0 % 251) })
    try data.write(to: source)

    try GzipArchive.compressFile(at: source, to: compressed)
    try GzipArchive.decompressFile(at: compressed, to: expanded)

    XCTAssertEqual(try Data(contentsOf: expanded), data)
    XCTAssertEqual(try FileSHA256.hash(url: source), try FileSHA256.hash(url: expanded))
  }

  private func createCatalog(at url: URL, cards: [CardRecord]) throws {
    let database = try CardDatabase(storage: .file(url))
    try database.replaceAllCards(cards)
    try database.prepareForCatalogDistribution()
    try database.database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
  }

  private func catalogManifest(version: String, counts: CatalogCounts) -> CatalogManifest {
    CatalogManifest(
      version: version,
      generatedAt: Date(timeIntervalSince1970: 0),
      sources: CatalogSourceVersions(
        scryfallUpdatedAt: "2026-06-14T00:00:00Z",
        mtgjsonDate: "2026-06-14",
        mtgjsonVersion: "5.2.1"
      ),
      artifact: CatalogArtifact(
        downloadURL: URL(string: "https://example.test/v1/catalog/\(version)")!,
        compressedBytes: 0,
        uncompressedBytes: 0,
        sha256: "",
        uncompressedSHA256: ""
      ),
      counts: counts
    )
  }

  private func managedCatalogFixture(
    in directory: URL,
    cards: [CardRecord]
  ) throws -> (manifest: CatalogManifest, manifestData: Data, compressedData: Data) {
    let fixtureDirectory = directory.appendingPathComponent(
      "ManagedFixture-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    let catalogURL = fixtureDirectory.appendingPathComponent("Catalog.sqlite")
    let compressedURL = fixtureDirectory.appendingPathComponent("Catalog.sqlite.gz")
    try createCatalog(at: catalogURL, cards: cards)
    try GzipArchive.compressFile(at: catalogURL, to: compressedURL)
    let counts = try CardDatabase.validateCatalog(at: catalogURL)
    let compressedData = try Data(contentsOf: compressedURL)
    let manifest = CatalogManifest(
      version: "v1-managed-test",
      generatedAt: Date(timeIntervalSince1970: 0),
      sources: CatalogSourceVersions(
        scryfallUpdatedAt: "2026-06-14T00:00:00Z",
        mtgjsonDate: "2026-06-14",
        mtgjsonVersion: "5.3.0"
      ),
      artifact: CatalogArtifact(
        downloadURL: URL(string: "https://example.test/v1/catalog/v1-managed-test")!,
        compressedBytes: Int64(compressedData.count),
        uncompressedBytes: try fileSize(catalogURL),
        sha256: try FileSHA256.hash(url: compressedURL),
        uncompressedSHA256: try FileSHA256.hash(url: catalogURL)
      ),
      counts: counts
    )
    return (
      manifest,
      try CatalogManifest.encoder().encode(manifest),
      compressedData
    )
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("CatalogStorageTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func rowCount(in database: CardDatabase, table: String) throws -> Int {
    let statement = try database.database.prepare("SELECT COUNT(*) FROM \(table)")
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  private func primaryKeyColumns(in database: CardDatabase, table: String) throws -> [String] {
    let statement = try database.database.prepare("PRAGMA table_info(\(table))")
    var columns: [(Int, String)] = []
    while try statement.step() {
      guard let name = statement.string(at: 1),
        let position = statement.int(at: 5),
        position > 0
      else {
        continue
      }
      columns.append((position, name))
    }
    return columns.sorted { $0.0 < $1.0 }.map(\.1)
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let value = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    return value?.int64Value ?? 0
  }
}

private func XCTAssertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {
  }
}
