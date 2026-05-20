import CSQLite
import Foundation

public enum SQLiteError: Error, Equatable, CustomStringConvertible, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case executionFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let message):
            "SQLite open failed: \(message)"
        case .prepareFailed(let message):
            "SQLite prepare failed: \(message)"
        case .stepFailed(let message):
            "SQLite step failed: \(message)"
        case .bindFailed(let message):
            "SQLite bind failed: \(message)"
        case .executionFailed(let message):
            "SQLite execution failed: \(message)"
        }
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    public enum Storage: Equatable, Sendable {
        case inMemory
        case file(URL)
    }

    private var handle: OpaquePointer?

    public init(storage: Storage) throws {
        let path: String
        switch storage {
        case .inMemory:
            path = ":memory:"
        case .file(let url):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            path = url.path
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            throw SQLiteError.openFailed(lastErrorMessage)
        }

        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(handle, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw SQLiteError.executionFailed(message)
        }
    }

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }
        guard let statement else {
            throw SQLiteError.prepareFailed("sqlite3_prepare_v2 returned nil")
        }
        return SQLiteStatement(statement: statement, database: self)
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    fileprivate var lastErrorMessage: String {
        guard let handle else {
            return "database is closed"
        }
        return String(cString: sqlite3_errmsg(handle))
    }
}

public final class SQLiteStatement {
    private let statement: OpaquePointer
    private unowned let database: SQLiteDatabase

    fileprivate init(statement: OpaquePointer, database: SQLiteDatabase) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    public func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try checkBind(result)
    }

    public func bind(_ value: Int?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try checkBind(result)
    }

    public func bind(_ value: Double?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try checkBind(result)
    }

    public func bind(_ value: Bool, at index: Int32) throws {
        try bind(value ? 1 : 0, at: index)
    }

    public func bind(_ value: Data?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try checkBind(result)
    }

    @discardableResult
    public func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SQLiteError.stepFailed(database.lastErrorMessage)
        }
    }

    public func reset() throws {
        if sqlite3_reset(statement) != SQLITE_OK {
            throw SQLiteError.stepFailed(database.lastErrorMessage)
        }
        sqlite3_clear_bindings(statement)
    }

    public func string(at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    public func int(at index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int64(statement, index))
    }

    public func double(at index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    public func bool(at index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    public func data(at index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        guard let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func checkBind(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SQLiteError.bindFailed(database.lastErrorMessage)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
