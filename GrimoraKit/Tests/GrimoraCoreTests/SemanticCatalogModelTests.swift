import Foundation
import GrimoraCore
import Testing

struct SemanticCatalogModelTests {
  @Test
  func cardKeyPrefersOracleIdentityAcrossPrintings() {
    let firstPrinting = SemanticCardKey(
      oracleID: "87f6c8b4-7f09-4f4e-9a34-6a7e80e50d49",
      printingID: "printing-a"
    )
    let secondPrinting = SemanticCardKey(
      oracleID: "87f6c8b4-7f09-4f4e-9a34-6a7e80e50d49",
      printingID: "printing-b"
    )

    #expect(firstPrinting == secondPrinting)
    #expect(firstPrinting.rawValue == "o:87f6c8b4-7f09-4f4e-9a34-6a7e80e50d49")
    #expect(firstPrinting.oracleID == "87f6c8b4-7f09-4f4e-9a34-6a7e80e50d49")
    #expect(firstPrinting.printingID == nil)
  }

  @Test
  func cardKeyFallsBackToPrintingIdentityWithoutOracleIdentity() {
    let key = SemanticCardKey(oracleID: nil, printingID: "printing-a")

    #expect(key.rawValue == "p:printing-a")
    #expect(key.oracleID == nil)
    #expect(key.printingID == "printing-a")
  }

  @Test
  func aliasKeysAreDeterministicAndSearchNormalized() {
    #expect(SemanticTagAliasRecord.normalizedKey(for: "  Réanimation  ") == "reanimation")
    #expect(SemanticTagAliasRecord.normalizedKey(for: "CARD DRAW") == "card draw")
  }

  @Test
  func semanticCatalogRecordsRoundTripThroughCodable() throws {
    let records = SemanticCatalogRecordFixture(
      tag: SemanticTagRecord(
        id: "tag-card-draw",
        namespace: "oracle",
        slug: "card-draw",
        label: "Card Draw",
        description: "Moves cards from a library into a hand.",
        similarityEnabled: true,
        source: "scryfall-oracle-tags"
      ),
      alias: SemanticTagAliasRecord(
        tagID: "tag-card-draw",
        alias: "Draw cards",
        aliasKey: SemanticTagAliasRecord.normalizedKey(for: "Draw cards")
      ),
      edge: SemanticTagEdgeRecord(parentTagID: "tag-card-advantage", childTagID: "tag-card-draw"),
      membership: SemanticCardTagRecord(
        cardKey: SemanticCardKey(oracleID: "oracle-card", printingID: "printing-card"),
        tagID: "tag-card-draw",
        weightMillis: 1_500,
        annotation: "repeatable",
        source: "scryfall-oracle-tags"
      ),
      stats: SemanticTagStatsRecord(
        tagID: "tag-card-draw",
        directCardCount: 42,
        effectiveCardCount: 57,
        inverseFrequencyMillis: 2_125
      )
    )

    let data = try JSONEncoder().encode(records)
    let decoded = try JSONDecoder().decode(SemanticCatalogRecordFixture.self, from: data)

    #expect(decoded == records)
  }
}

private struct SemanticCatalogRecordFixture: Codable, Equatable {
  var tag: SemanticTagRecord
  var alias: SemanticTagAliasRecord
  var edge: SemanticTagEdgeRecord
  var membership: SemanticCardTagRecord
  var stats: SemanticTagStatsRecord
}
