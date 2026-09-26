import Foundation
import Testing
@testable import GrimoraCore

struct CatalogManifestCompatibilityTests {
  @Test
  func semanticCountsRemainBackwardCompatible() throws {
    let legacyData = Data(
      """
      {
        "artifact": {
          "compressedBytes": 10,
          "downloadURL": "https://example.test/catalog",
          "sha256": "compressed",
          "uncompressedBytes": 20,
          "uncompressedSHA256": "expanded"
        },
        "catalogSchemaVersion": 1,
        "counts": {
          "cards": 3,
          "priceSeries": 2
        },
        "enrichments": [],
        "generatedAt": "2026-09-25T00:00:00Z",
        "sources": {
          "mtgjsonDate": "2026-09-25",
          "mtgjsonVersion": "5.3.0",
          "scryfallUpdatedAt": "2026-09-25T00:00:00Z"
        },
        "version": "legacy"
      }
      """.utf8
    )

    let legacy = try CatalogManifest.decoder().decode(CatalogManifest.self, from: legacyData)
    #expect(legacy.counts.semantic == nil)

    let manifest = CatalogManifest(
      version: "semantic",
      generatedAt: Date(timeIntervalSince1970: 0),
      sources: CatalogSourceVersions(
        scryfallUpdatedAt: "2026-09-25T00:00:00Z",
        mtgjsonDate: "2026-09-25",
        mtgjsonVersion: "5.3.0"
      ),
      artifact: CatalogArtifact(
        downloadURL: URL(string: "https://example.test/catalog")!,
        compressedBytes: 10,
        uncompressedBytes: 20,
        sha256: "compressed",
        uncompressedSHA256: "expanded"
      ),
      counts: CatalogCounts(
        cards: 3,
        priceSeries: 2,
        semantic: CatalogSemanticCounts(
          tags: 5,
          aliases: 4,
          edges: 3,
          cardTags: 2,
          tagStats: 5
        )
      )
    )

    let encoded = try CatalogManifest.encoder().encode(manifest)
    let decoded = try CatalogManifest.decoder().decode(CatalogManifest.self, from: encoded)
    #expect(decoded == manifest)

    let legacyProjection = try JSONDecoder().decode(LegacyManifestProjection.self, from: encoded)
    #expect(legacyProjection.counts.cards == 3)
    #expect(legacyProjection.counts.priceSeries == 2)
  }
}

private struct LegacyManifestProjection: Decodable {
  var counts: LegacyCountsProjection
}

private struct LegacyCountsProjection: Decodable {
  var cards: Int
  var priceSeries: Int
}
