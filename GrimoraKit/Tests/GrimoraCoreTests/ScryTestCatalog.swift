#if canImport(Vision)
@testable import GrimoraCore
import Foundation
import XCTest

/// A realistic, independently-sourced card catalog for the Scry corpus tests.
///
/// Built from `ScryCorpus/catalog.json.gz` — a real Scryfall snapshot of every
/// printing of each corpus card's name plus the full involved sets (~1,200 real
/// cards). The point is **black-box honesty**: the target cards are present
/// because they are real Magic cards surrounded by their real, confusable
/// set-mates and reprints (Izzet Boilerworks alone has 24 printings here), *not*
/// because the test inserted exactly the expected answers. The recognition
/// pipeline only ever sees an image and this catalog; it has no idea which card
/// any image is "supposed" to be.
enum ScryTestCatalog {
  /// Built once, shared across tests (read-only).
  static let shared: CardDatabase? = try? build()

  /// The shared catalog, or a test SKIP on checkouts without the corpus assets
  /// (images, scenes, and catalog.json.gz are gitignored local-only data — see
  /// ScryCorpus/README.md). A catalog that exists but fails to build is still a
  /// hard failure, not a skip.
  static func requireShared() throws -> CardDatabase {
    if let shared { return shared }
    if let url = Bundle.module.resourceURL?
      .appendingPathComponent("ScryCorpus", isDirectory: true)
      .appendingPathComponent("catalog.json.gz"),
      FileManager.default.fileExists(atPath: url.path) {
      return try build()  // present but broken — surface the real error
    }
    throw XCTSkip(
      "ScryCorpus/catalog.json.gz not on this checkout — the corpus is a local-only asset store (ScryCorpus/README.md)"
    )
  }

  static func build() throws -> CardDatabase {
    guard let url = Bundle.module.resourceURL?
      .appendingPathComponent("ScryCorpus", isDirectory: true)
      .appendingPathComponent("catalog.json.gz"),
      FileManager.default.fileExists(atPath: url.path) else {
      throw CocoaError(.fileNoSuchFile)
    }

    let unzipped = FileManager.default.temporaryDirectory
      .appendingPathComponent("scry-catalog-\(UUID().uuidString).json")
    try GzipArchive.decompressFile(at: url, to: unzipped)
    defer { try? FileManager.default.removeItem(at: unzipped) }

    let data = try Data(contentsOf: unzipped)
    // Decode resiliently — skip any single card Scryfall shapes oddly.
    let wrapped = try JSONDecoder().decode([FailableCard].self, from: data)
    let records = wrapped.compactMap { $0.card.map { ScryfallCardNormalizer.normalize($0) } }

    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(records)
    return database
  }

  private struct FailableCard: Decodable {
    let card: ScryfallCardDTO?
    init(from decoder: Decoder) throws {
      card = try? ScryfallCardDTO(from: decoder)
    }
  }
}
#endif
