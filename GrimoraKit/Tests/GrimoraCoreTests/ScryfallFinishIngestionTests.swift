@testable import GrimoraCore
import XCTest

/// Proves the catalog ingestion path retains the finish + promo-type data the foil-treatment
/// feature depends on, using the real `ScryfallCatalogDecoder` (DTO decode → normalize) on
/// hand-built JSON for the two cards that motivated the work. No network.
final class ScryfallFinishIngestionTests: XCTestCase {
    private func record(fromJSON json: String) throws -> CardRecord {
        try ScryfallCatalogDecoder.decodeRecord(from: Data(json.utf8))
    }

    /// MH2 #271 Wonder: etched is a third finish on the *same* card object, alongside the normal
    /// and foil versions — the case the app previously couldn't surface.
    func testEtchedFinishSurvivesIngestion() throws {
        let card = try record(fromJSON: """
        {
          "id": "mh2-271-wonder",
          "name": "Wonder",
          "set": "mh2",
          "set_name": "Modern Horizons 2",
          "collector_number": "271",
          "rarity": "rare",
          "layout": "normal",
          "type_line": "Creature — Incarnation",
          "oracle_text": "Flying",
          "finishes": ["nonfoil", "foil", "etched"],
          "promo_types": []
        }
        """)

        XCTAssertTrue(card.finishes.contains("etched"))
        XCTAssertTrue(card.supportsEtched)
        XCTAssertEqual(card.availableFinishes, [.normal, .foil, .etched])
        XCTAssertNil(card.specialFoilTreatment)
        XCTAssertEqual(card.foilTreatment(for: .etched), .etched)
    }

    /// SLD #1273 Utvara Hellkite: the halo-foil treatment lives in `promo_types`, not `finishes`.
    func testHaloFoilPromoTypeSurvivesIngestion() throws {
        let card = try record(fromJSON: """
        {
          "id": "sld-1273-utvara",
          "name": "Utvara Hellkite",
          "set": "sld",
          "set_name": "Secret Lair Drop",
          "collector_number": "1273",
          "rarity": "mythic",
          "layout": "normal",
          "type_line": "Creature — Dragon",
          "oracle_text": "Flying",
          "finishes": ["foil"],
          "promo_types": ["halofoil"],
          "frame_effects": ["showcase"]
        }
        """)

        XCTAssertTrue(card.promoTypes.contains("halofoil"))
        XCTAssertEqual(card.specialFoilTreatment, .halo)
        XCTAssertTrue(card.isFoilOnly)
        XCTAssertEqual(card.defaultFinish, .foil)
        XCTAssertEqual(card.foilTreatment(for: .foil), .halo)
    }
}
