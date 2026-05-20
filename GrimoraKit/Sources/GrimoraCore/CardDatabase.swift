import Foundation

public final class CardDatabase: @unchecked Sendable {
  let database: SQLiteDatabase
  private let lock = NSRecursiveLock()
  public static let currentSearchSchemaVersion = "4"

  public init(storage: SQLiteDatabase.Storage) throws {
    self.database = try SQLiteDatabase(storage: storage)
    try migrate()
  }

  func withDatabaseLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
