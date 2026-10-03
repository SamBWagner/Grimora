import Foundation

public final class CardDatabase: @unchecked Sendable {
  let database: SQLiteDatabase
  private let lock = NSRecursiveLock()
  var catalogContentGeneration: UInt64 = 0
  var attachedCatalogURL: URL?
  public static let currentSearchSchemaVersion = "4"

  public init(storage: SQLiteDatabase.Storage) throws {
    self.database = try SQLiteDatabase(storage: storage)
    try migrate()
  }

  public init(userDatabaseURL: URL, catalogURL: URL) throws {
    try Self.createEmptyCatalogIfNeeded(at: catalogURL)
    self.database = try SQLiteDatabase(storage: .file(userDatabaseURL))
    self.attachedCatalogURL = catalogURL
    try migrate()
    try prepareMainDatabaseForAttachedCatalog()
    try database.attachReadOnlyDatabase(at: catalogURL, as: Self.catalogSchemaName)
    try createCatalogOverlayViews()
  }

  public var usesExternalCatalog: Bool {
    attachedCatalogURL != nil
  }

  func withDatabaseLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  func withCancellableDatabaseLock<T>(_ body: () throws -> T) async throws -> T {
    while !tryDatabaseLock() {
      try Task.checkCancellation()
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    defer { unlockDatabase() }
    try Task.checkCancellation()
    return try body()
  }

  func markCatalogContentChangedUnlocked() {
    catalogContentGeneration &+= 1
  }

  private func tryDatabaseLock() -> Bool {
    lock.try()
  }

  private func unlockDatabase() {
    lock.unlock()
  }
}
