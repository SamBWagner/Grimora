import Foundation

public enum ManagedCatalogMigrationStatus: Equatable, Sendable {
  case checking
  case downloading(completedBytes: Int64, totalBytes: Int64?)
  case validating
  case restartRequired(version: String)
  case failed(String)
}

public enum ManagedCatalogMigrationError: Error, Equatable, Sendable {
  case invalidManifest
  case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
}

public struct ManagedCatalogBootstrap: Sendable {
  public var database: CardDatabase
  public var migrationService: ManagedCatalogMigrationService?
  public var initialMigrationStatus: ManagedCatalogMigrationStatus?
  public var databaseAlreadyExists: Bool

  public init(
    database: CardDatabase,
    migrationService: ManagedCatalogMigrationService?,
    initialMigrationStatus: ManagedCatalogMigrationStatus?,
    databaseAlreadyExists: Bool
  ) {
    self.database = database
    self.migrationService = migrationService
    self.initialMigrationStatus = initialMigrationStatus
    self.databaseAlreadyExists = databaseAlreadyExists
  }
}

public final class ManagedCatalogMigrationService: @unchecked Sendable {
  public typealias AvailableCapacity = @Sendable (URL) throws -> Int64
  public typealias Now = @Sendable () -> Date

  public static let activeDirectoryName = "Database-v2"
  public static let rollbackRetention: TimeInterval = 7 * 24 * 60 * 60

  private let layout: Layout
  private let bulkDataClient: BulkDataClient
  private let fileManager: FileManager
  private let availableCapacity: AvailableCapacity
  private let now: Now

  public init(
    supportDirectory: URL,
    bulkDataClient: BulkDataClient,
    fileManager: FileManager = .default,
    availableCapacity: @escaping AvailableCapacity =
      ManagedCatalogMigrationService.defaultAvailableCapacity,
    now: @escaping Now = Date.init
  ) {
    layout = Layout(supportDirectory: supportDirectory)
    self.bulkDataClient = bulkDataClient
    self.fileManager = fileManager
    self.availableCapacity = availableCapacity
    self.now = now
  }

  public static func bootstrap(
    supportDirectory: URL,
    bulkDataClient: BulkDataClient,
    fileManager: FileManager = .default,
    availableCapacity: @escaping AvailableCapacity =
      ManagedCatalogMigrationService.defaultAvailableCapacity,
    now: @escaping Now = Date.init
  ) throws -> ManagedCatalogBootstrap {
    let service = ManagedCatalogMigrationService(
      supportDirectory: supportDirectory,
      bulkDataClient: bulkDataClient,
      fileManager: fileManager,
      availableCapacity: availableCapacity,
      now: now
    )
    try service.cleanupInterruptedActivation()

    if fileManager.fileExists(atPath: service.layout.activeDirectory.path) {
      do {
        let database = try service.openValidatedManagedDatabase()
        try service.recordHealthyManagedLaunch()
        return ManagedCatalogBootstrap(
          database: database,
          migrationService: nil,
          initialMigrationStatus: nil,
          databaseAlreadyExists: true
        )
      } catch {
        if fileManager.fileExists(atPath: service.layout.legacyDatabase.path) {
          let managedError = error
          try? fileManager.removeItem(at: service.layout.activeDirectory)
          let legacyDatabase: CardDatabase
          do {
            legacyDatabase = try CardDatabase(storage: .file(service.layout.legacyDatabase))
          } catch {
            throw CatalogStorageError.invalidCatalog(
              "Managed open failed: \(managedError); legacy fallback failed: \(error)"
            )
          }
          return ManagedCatalogBootstrap(
            database: legacyDatabase,
            migrationService: service,
            initialMigrationStatus: .failed(
              "The managed catalog could not be opened. Grimora kept the previous library."
            ),
            databaseAlreadyExists: true
          )
        }
        if let database = try? service.openInitialSetupDatabase() {
          return ManagedCatalogBootstrap(
            database: database,
            migrationService: nil,
            initialMigrationStatus: nil,
            databaseAlreadyExists: false
          )
        }
        throw error
      }
    }

    if fileManager.fileExists(atPath: service.layout.legacyDatabase.path) {
      if fileManager.fileExists(atPath: service.layout.readyDirectory.path) {
        do {
          try service.activateReadyMigration()
          let database = try service.openValidatedManagedDatabase()
          try service.recordHealthyManagedLaunch()
          return ManagedCatalogBootstrap(
            database: database,
            migrationService: nil,
            initialMigrationStatus: nil,
            databaseAlreadyExists: true
          )
        } catch {
          let activationError = error
          try service.cleanupInterruptedActivation()
          let legacyDatabase: CardDatabase
          do {
            legacyDatabase = try CardDatabase(storage: .file(service.layout.legacyDatabase))
          } catch {
            throw CatalogStorageError.invalidCatalog(
              "Catalog activation failed: \(activationError); legacy fallback failed: \(error)"
            )
          }
          return ManagedCatalogBootstrap(
            database: legacyDatabase,
            migrationService: service,
            initialMigrationStatus: .failed(
              "The catalog upgrade could not be activated. Grimora kept the previous library."
            ),
            databaseAlreadyExists: true
          )
        }
      }

      return ManagedCatalogBootstrap(
        database: try CardDatabase(storage: .file(service.layout.legacyDatabase)),
        migrationService: service,
        initialMigrationStatus: .checking,
        databaseAlreadyExists: true
      )
    }

    try fileManager.createDirectory(
      at: service.layout.activeDirectory,
      withIntermediateDirectories: true
    )
    let database = try CardDatabase(
      userDatabaseURL: service.layout.activeUserDatabase,
      catalogURL: service.layout.activeCatalog
    )
    return ManagedCatalogBootstrap(
      database: database,
      migrationService: nil,
      initialMigrationStatus: nil,
      databaseAlreadyExists: false
    )
  }

  public func stageLatestCatalog(
    manual: Bool,
    progress: (@Sendable (ManagedCatalogMigrationStatus) async -> Void)? = nil
  ) async throws -> CatalogManifest {
    try cleanupInterruptedStaging()
    if let ready = try readyManifest() {
      await progress?(.restartRequired(version: ready.version))
      return ready
    }

    await progress?(.checking)
    let bulkManifest = try await bulkDataClient.fetchDefaultCardsManifest()
    guard bulkManifest.type == BulkDataManifest.grimoraCatalogType,
      let catalog = bulkManifest.catalog
    else {
      throw ManagedCatalogMigrationError.invalidManifest
    }

    // Prefer a small incremental delta; any failure falls through to the full download below.
    if let staged = try? await stageIncrementally(target: catalog, manual: manual, progress: progress) {
      return staged
    }

    let requiredBytes =
      catalog.artifact.compressedBytes
      + catalog.artifact.uncompressedBytes
      + max(512 * 1024 * 1024, catalog.artifact.uncompressedBytes / 4)
    try requireAvailableCapacity(requiredBytes)

    let buildingDirectory = layout.supportDirectory.appendingPathComponent(
      ".CatalogMigrationBuilding-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: buildingDirectory, withIntermediateDirectories: true)
    defer {
      try? fileManager.removeItem(at: buildingDirectory)
    }

    let compressedURL = buildingDirectory.appendingPathComponent("Catalog.sqlite.gz")
    let catalogURL = buildingDirectory.appendingPathComponent("Catalog.sqlite")
    try await bulkDataClient.downloadDefaultCards(
      manifest: bulkManifest,
      to: compressedURL,
      purpose: manual ? .bulkDownload : .automaticCatalogDownload
    ) { downloadProgress in
      await progress?(
        .downloading(
          completedBytes: downloadProgress.completedBytes,
          totalBytes: downloadProgress.totalBytes ?? catalog.artifact.compressedBytes
        )
      )
    }

    guard try FileSHA256.hash(url: compressedURL) == catalog.artifact.sha256 else {
      throw CatalogStorageError.invalidCatalog("Downloaded catalog SHA-256 does not match")
    }
    await progress?(.validating)
    do {
      try GzipArchive.decompressFile(at: compressedURL, to: catalogURL)
    } catch {
      throw CatalogStorageError.invalidCatalog("Catalog decompression failed: \(error)")
    }
    guard try FileSHA256.hash(url: catalogURL) == catalog.artifact.uncompressedSHA256 else {
      throw CatalogStorageError.invalidCatalog("Expanded catalog SHA-256 does not match")
    }
    do {
      _ = try CardDatabase.validateCatalog(at: catalogURL, expectedManifest: catalog)
    } catch {
      throw CatalogStorageError.invalidCatalog("Staged catalog validation failed: \(error)")
    }
    try CatalogManifest.encoder(prettyPrinted: true).encode(catalog)
      .write(to: buildingDirectory.appendingPathComponent("manifest.json"), options: .atomic)

    if fileManager.fileExists(atPath: layout.readyDirectory.path) {
      try fileManager.removeItem(at: layout.readyDirectory)
    }
    try fileManager.moveItem(at: buildingDirectory, to: layout.readyDirectory)
    await progress?(.restartRequired(version: catalog.version))
    return catalog
  }

  /// Attempts a single-step incremental update: patch a copy of the installed catalog with one delta
  /// and stage the result, instead of downloading the full artifact. Returns the target manifest on
  /// success; throws (→ caller falls back to a full download) on any mismatch, missing base, or a
  /// multi-build gap. Phase 1 handles exactly one build behind.
  private func stageIncrementally(
    target: CatalogManifest,
    manual: Bool,
    progress: (@Sendable (ManagedCatalogMigrationStatus) async -> Void)?
  ) async throws -> CatalogManifest {
    guard let installed = try activeManifest(),
      installed.version != target.version,
      installed.catalogSchemaVersion == target.catalogSchemaVersion,
      let targetDigests = target.contentDigests,
      fileManager.fileExists(atPath: layout.activeCatalog.path)
    else {
      throw ManagedCatalogMigrationError.invalidManifest
    }

    let chain = try await bulkDataClient.fetchCatalogChain()
    guard chain.current == target.version,
      let path = chain.deltaPath(from: installed.version),
      path.count == 1
    else {
      throw ManagedCatalogMigrationError.invalidManifest
    }
    let delta = path[0]

    // Working copy of the catalog + the (small) delta, with headroom.
    let requiredBytes =
      target.artifact.uncompressedBytes
      + delta.bytes
      + max(256 * 1024 * 1024, target.artifact.uncompressedBytes / 8)
    try requireAvailableCapacity(requiredBytes)

    let buildingDirectory = layout.supportDirectory.appendingPathComponent(
      ".CatalogMigrationBuilding-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: buildingDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: buildingDirectory) }

    let workingCatalog = buildingDirectory.appendingPathComponent("Catalog.sqlite")
    try fileManager.copyItem(at: layout.activeCatalog, to: workingCatalog)

    let deltaGz = buildingDirectory.appendingPathComponent("delta.sqlite.gz")
    try await bulkDataClient.downloadCatalogDelta(
      from: delta.url,
      to: deltaGz,
      purpose: manual ? .bulkDownload : .automaticCatalogDownload
    ) { downloadProgress in
      await progress?(
        .downloading(
          completedBytes: downloadProgress.completedBytes,
          totalBytes: downloadProgress.totalBytes ?? delta.bytes
        )
      )
    }
    guard try FileSHA256.hash(url: deltaGz) == delta.sha256 else {
      throw CatalogStorageError.invalidCatalog("Downloaded delta SHA-256 does not match")
    }

    await progress?(.validating)
    let deltaSQLite = buildingDirectory.appendingPathComponent("delta.sqlite")
    try GzipArchive.decompressFile(at: deltaGz, to: deltaSQLite)
    try CatalogDeltaApplier().apply(deltaURL: deltaSQLite, toWorkingCatalog: workingCatalog)

    // The chained-hash check: the patched catalog must be logically identical to a fresh build of
    // `target` (byte layout differs, but the content digests must match exactly).
    let workingDigests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(workingCatalog))
    )
    guard workingDigests == targetDigests else {
      throw CatalogStorageError.invalidCatalog("Patched catalog digests do not match target")
    }
    _ = try CardDatabase.validateCatalog(at: workingCatalog, expectedManifest: target)

    try CatalogManifest.encoder(prettyPrinted: true).encode(target)
      .write(to: buildingDirectory.appendingPathComponent("manifest.json"), options: .atomic)
    try? fileManager.removeItem(at: deltaGz)
    try? fileManager.removeItem(at: deltaSQLite)

    if fileManager.fileExists(atPath: layout.readyDirectory.path) {
      try fileManager.removeItem(at: layout.readyDirectory)
    }
    try fileManager.moveItem(at: buildingDirectory, to: layout.readyDirectory)
    await progress?(.restartRequired(version: target.version))
    return target
  }

  private func activeManifest() throws -> CatalogManifest? {
    guard fileManager.fileExists(atPath: layout.activeManifest.path) else {
      return nil
    }
    return try CatalogManifest.decoder().decode(
      CatalogManifest.self,
      from: Data(contentsOf: layout.activeManifest)
    )
  }

  public func readyManifest() throws -> CatalogManifest? {
    let manifestURL = layout.readyDirectory.appendingPathComponent("manifest.json")
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      return nil
    }
    return try CatalogManifest.decoder().decode(
      CatalogManifest.self,
      from: Data(contentsOf: manifestURL)
    )
  }

  private func activateReadyMigration() throws {
    let manifest = try requiredReadyManifest()
    let stagedCatalog = layout.readyDirectory.appendingPathComponent("Catalog.sqlite")
    _ = try CardDatabase.validateCatalog(at: stagedCatalog, expectedManifest: manifest)
    let requiredBytes =
      manifest.artifact.uncompressedBytes
      + max(512 * 1024 * 1024, manifest.artifact.uncompressedBytes / 4)
    try requireAvailableCapacity(requiredBytes)

    let pendingDirectory = layout.supportDirectory.appendingPathComponent(
      "Database.pending-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
    do {
      let pendingCatalog = pendingDirectory.appendingPathComponent("Catalog.sqlite")
      let pendingUser = pendingDirectory.appendingPathComponent("User.sqlite")
      try fileManager.copyItem(at: stagedCatalog, to: pendingCatalog)
      _ = try CardDatabase.migrateLegacyUserDatabase(
        legacyURL: layout.legacyDatabase,
        userDatabaseURL: pendingUser
      )
      do {
        let database = try CardDatabase(
          userDatabaseURL: pendingUser,
          catalogURL: pendingCatalog
        )
        try database.recordInstalledCatalogManifest(manifest)
        guard try database.isLibraryReady() else {
          throw CatalogStorageError.invalidCatalog("Activated library is not ready")
        }
      }

      // Persist the installed manifest (with digests) so the next update can go incremental.
      try? CatalogManifest.encoder(prettyPrinted: true).encode(manifest)
        .write(to: pendingDirectory.appendingPathComponent("manifest.json"), options: .atomic)

      try fileManager.moveItem(at: pendingDirectory, to: layout.activeDirectory)
      let lifecycle = LifecycleState(activatedAt: now(), healthyLaunches: 0)
      try saveLifecycle(lifecycle)
      try fileManager.removeItem(at: layout.readyDirectory)
    } catch {
      try? fileManager.removeItem(at: pendingDirectory)
      throw error
    }
  }

  private func openValidatedManagedDatabase() throws -> CardDatabase {
    _ = try CardDatabase.validateCatalog(at: layout.activeCatalog)
    let database = try CardDatabase(
      userDatabaseURL: layout.activeUserDatabase,
      catalogURL: layout.activeCatalog
    )
    guard try database.isLibraryReady() else {
      throw CatalogStorageError.invalidCatalog("Managed library is not ready")
    }
    return database
  }

  private func openInitialSetupDatabase() throws -> CardDatabase {
    let database = try CardDatabase(
      userDatabaseURL: layout.activeUserDatabase,
      catalogURL: layout.activeCatalog
    )
    guard try database.cardCount() == 0,
      try database.metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue) == nil
    else {
      throw CatalogStorageError.invalidCatalog("Managed catalog is not awaiting initial setup")
    }
    return database
  }

  private func recordHealthyManagedLaunch() throws {
    var lifecycle = try loadLifecycle()
      ?? LifecycleState(activatedAt: now(), healthyLaunches: 0)
    lifecycle.healthyLaunches += 1
    if lifecycle.healthyLaunches >= 2,
      now().timeIntervalSince(lifecycle.activatedAt) >= Self.rollbackRetention,
      fileManager.fileExists(atPath: layout.legacyDatabase.path)
    {
      try fileManager.removeItem(at: layout.legacyDatabase)
      for suffix in ["-wal", "-shm"] {
        let sidecar = URL(fileURLWithPath: layout.legacyDatabase.path + suffix)
        try? fileManager.removeItem(at: sidecar)
      }
    }
    try saveLifecycle(lifecycle)
  }

  private func cleanupInterruptedStaging() throws {
    for url in try fileManager.contentsOfDirectory(
      at: layout.supportDirectory,
      includingPropertiesForKeys: nil
    ) where url.lastPathComponent.hasPrefix(".CatalogMigrationBuilding-") {
      try fileManager.removeItem(at: url)
    }
  }

  private func cleanupInterruptedActivation() throws {
    for url in try fileManager.contentsOfDirectory(
      at: layout.supportDirectory,
      includingPropertiesForKeys: nil
    ) where url.lastPathComponent.hasPrefix("Database.pending-") {
      try fileManager.removeItem(at: url)
    }
  }

  private func requireAvailableCapacity(_ requiredBytes: Int64) throws {
    let available = try availableCapacity(layout.supportDirectory)
    guard available >= requiredBytes else {
      throw ManagedCatalogMigrationError.insufficientDiskSpace(
        requiredBytes: requiredBytes,
        availableBytes: available
      )
    }
  }

  private func requiredReadyManifest() throws -> CatalogManifest {
    guard let manifest = try readyManifest() else {
      throw ManagedCatalogMigrationError.invalidManifest
    }
    return manifest
  }

  private func loadLifecycle() throws -> LifecycleState? {
    guard fileManager.fileExists(atPath: layout.lifecycleState.path) else {
      return nil
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      LifecycleState.self,
      from: Data(contentsOf: layout.lifecycleState)
    )
  }

  private func saveLifecycle(_ lifecycle: LifecycleState) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(lifecycle).write(to: layout.lifecycleState, options: .atomic)
  }

  public static func defaultAvailableCapacity(_ url: URL) throws -> Int64 {
    #if canImport(Darwin)
    let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values.volumeAvailableCapacityForImportantUsage ?? 0
    #else
    let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
    return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    #endif
  }
}

private struct Layout {
  var supportDirectory: URL

  var legacyDatabase: URL {
    supportDirectory.appendingPathComponent("Grimora.sqlite")
  }

  var activeDirectory: URL {
    supportDirectory.appendingPathComponent(
      ManagedCatalogMigrationService.activeDirectoryName,
      isDirectory: true
    )
  }

  var activeUserDatabase: URL {
    activeDirectory.appendingPathComponent("User.sqlite")
  }

  var activeCatalog: URL {
    activeDirectory.appendingPathComponent("Catalog.sqlite")
  }

  /// The installed build's manifest (with content digests), persisted so an incremental update knows
  /// its base version + digests without opening the 464 MB catalog.
  var activeManifest: URL {
    activeDirectory.appendingPathComponent("manifest.json")
  }

  var readyDirectory: URL {
    supportDirectory.appendingPathComponent(".CatalogMigrationReady", isDirectory: true)
  }

  var lifecycleState: URL {
    supportDirectory.appendingPathComponent("CatalogMigrationState.json")
  }
}

private struct LifecycleState: Codable {
  var activatedAt: Date
  var healthyLaunches: Int
}
