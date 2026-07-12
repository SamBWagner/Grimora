import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#elseif canImport(Crypto)
  import Crypto
#endif

/// Per-table SHA-256 digests over the *logical content* of a distributed catalog, plus an
/// `overall` roll-up. These are the anchor for the incremental-update "chain of hashes": the data
/// engine publishes them for every build, and a client that patches its catalog row-by-row
/// re-hashes only the tables a delta touched and compares against the target build's digests.
///
/// The digest deliberately hashes **row values in a canonical order**, never file bytes: the
/// engine runs `VACUUM` and FTS `optimize` (`finalizeStreamingCatalogBuild`), so two builds with
/// identical data still produce byte-different files, and an on-device INSERT/UPDATE/DELETE apply
/// can never reproduce the engine's exact page layout. Hashing values sidesteps all of that.
public struct CatalogContentDigests: Codable, Equatable, Sendable {
  /// Hex SHA-256 over the `cards` table (all columns, `ORDER BY id`).
  public var cards: String
  /// Hex SHA-256 over `card_faces` (all columns **except** the autoincrement `id`, ordered by
  /// `card_id, face_index` — the surrogate key diverges between a fresh build and an on-device
  /// delete+reinsert and must never enter the hash).
  public var cardFaces: String
  /// Hex SHA-256 over `card_value_series` (`ORDER BY card_id, provider, finish`).
  public var series: String
  /// Hex SHA-256 over `card_value_summaries` (`ORDER BY card_id, provider, finish`).
  public var summaries: String
  /// Hex SHA-256 over `card_value_mappings` (`ORDER BY mtgjson_uuid`).
  public var mappings: String
  /// Hex SHA-256 over the five per-table digests, in the fixed order above.
  public var overall: String

  public init(
    cards: String,
    cardFaces: String,
    series: String,
    summaries: String,
    mappings: String,
    overall: String
  ) {
    self.cards = cards
    self.cardFaces = cardFaces
    self.series = series
    self.summaries = summaries
    self.mappings = mappings
    self.overall = overall
  }
}

public enum CatalogContentDigestError: Error, Equatable, Sendable {
  case unavailable
}

/// Computes ``CatalogContentDigests`` identically on the server (engine build) and the client
/// (post-apply verification). The algorithm lives in exactly one place on purpose — any drift
/// between the two sides would silently reject every incremental update.
public enum CatalogContentDigest {
  /// Tables covered by the digest, with the ordering and exclusions each requires. Kept as data so
  /// the same list drives both digesting and the round-trip tests.
  enum Table: CaseIterable {
    case cards
    case cardFaces
    case series
    case summaries
    case mappings

    var name: String {
      switch self {
      case .cards: "cards"
      case .cardFaces: "card_faces"
      case .series: "card_value_series"
      case .summaries: "card_value_summaries"
      case .mappings: "card_value_mappings"
      }
    }

    var orderBy: [String] {
      switch self {
      case .cards: ["id"]
      case .cardFaces: ["card_id", "face_index"]
      case .series, .summaries: ["card_id", "provider", "finish"]
      case .mappings: ["mtgjson_uuid"]
      }
    }

    var excludedColumns: Set<String> {
      switch self {
      case .cardFaces: ["id"]
      default: []
      }
    }
  }

  /// Storage-class-independent encoding of a column value, derived from the column's declared
  /// affinity (identical on both ends because both read the same schema). Reading integer columns
  /// as `Int64` and real columns as the IEEE-754 bit pattern avoids SQLite's integer/real storage
  /// optimizations leaking into the hash.
  private enum Affinity {
    case integer
    case real
    case text
    case blob
  }

  public static func compute(_ database: SQLiteDatabase) throws -> CatalogContentDigests {
    #if canImport(CryptoKit) || canImport(Crypto)
      var perTable: [Table: Data] = [:]
      for table in Table.allCases {
        perTable[table] = try tableDigest(database, table: table)
      }
      var overall = SHA256()
      for table in Table.allCases {
        overall.update(data: perTable[table] ?? Data())
      }
      return CatalogContentDigests(
        cards: perTable[.cards]?.hexString ?? "",
        cardFaces: perTable[.cardFaces]?.hexString ?? "",
        series: perTable[.series]?.hexString ?? "",
        summaries: perTable[.summaries]?.hexString ?? "",
        mappings: perTable[.mappings]?.hexString ?? "",
        overall: Data(overall.finalize()).hexString
      )
    #else
      throw CatalogContentDigestError.unavailable
    #endif
  }

  #if canImport(CryptoKit) || canImport(Crypto)
    private static func tableDigest(_ database: SQLiteDatabase, table: Table) throws -> Data {
      let info = try database.prepare("PRAGMA table_info(\(table.name))")
      var columns: [(name: String, affinity: Affinity)] = []
      while try info.step() {
        guard let name = info.string(at: 1) else { continue }
        if table.excludedColumns.contains(name) { continue }
        columns.append((name, affinity(for: info.string(at: 2) ?? "")))
      }

      let columnList = columns.map { quoted($0.name) }.joined(separator: ", ")
      let orderClause = table.orderBy.map(quoted).joined(separator: ", ")
      let statement = try database.prepare(
        "SELECT \(columnList) FROM \(table.name) ORDER BY \(orderClause)"
      )

      var hasher = SHA256()
      var scratch = Data()
      while try statement.step() {
        for (offset, column) in columns.enumerated() {
          let index = Int32(offset)
          scratch.removeAll(keepingCapacity: true)
          switch column.affinity {
          case .integer:
            if let value = statement.int(at: index) {
              scratch.append(0x01)
              appendLittleEndian(UInt64(bitPattern: Int64(value)), to: &scratch)
            } else {
              scratch.append(0x00)
            }
          case .real:
            if let value = statement.double(at: index) {
              scratch.append(0x02)
              appendLittleEndian(value.bitPattern, to: &scratch)
            } else {
              scratch.append(0x00)
            }
          case .text:
            appendBytesColumn(statement, index, tag: 0x03, into: &scratch)
          case .blob:
            appendBytesColumn(statement, index, tag: 0x04, into: &scratch)
          }
          hasher.update(data: scratch)
        }
      }
      return Data(hasher.finalize())
    }

    private static func appendBytesColumn(
      _ statement: SQLiteStatement,
      _ index: Int32,
      tag: UInt8,
      into scratch: inout Data
    ) {
      if let value = statement.data(at: index) {
        scratch.append(tag)
        appendLittleEndian(UInt64(value.count), to: &scratch)
        scratch.append(value)
      } else {
        scratch.append(0x00)
      }
    }

    private static func appendLittleEndian(_ value: UInt64, to data: inout Data) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
  #endif

  /// SQLite's column-affinity algorithm (datatype3.html §3.1), restricted to the storage classes
  /// the catalog schema actually uses. `NUMERIC`/untyped columns don't exist in the catalog; they
  /// fall through to `text` (raw-byte) handling, which is still deterministic.
  private static func affinity(for declaredType: String) -> Affinity {
    let type = declaredType.uppercased()
    if type.contains("INT") {
      return .integer
    }
    if type.contains("CHAR") || type.contains("CLOB") || type.contains("TEXT") {
      return .text
    }
    if type.contains("BLOB") || type.isEmpty {
      return .blob
    }
    if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB") {
      return .real
    }
    return .text
  }

  private static func quoted(_ identifier: String) -> String {
    "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}

extension Data {
  fileprivate var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
