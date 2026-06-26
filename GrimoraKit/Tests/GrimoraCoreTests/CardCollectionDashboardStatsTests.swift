@testable import GrimoraCore
import XCTest

final class CardCollectionDashboardStatsTests: XCTestCase {
    func testDashboardStatsAreQuantityWeightedAndSkipUnavailablePriceData() {
        let entries = [
            entry(card: card(id: "bolt", name: "Lightning Bolt", colorIdentity: ["R"], typeLine: "Instant", priceUSD: 1.50), quantity: 2, position: 0),
            entry(card: card(id: "pool", name: "Breeding Pool", colorIdentity: ["G", "U"], typeLine: "Land", priceUSD: 10), quantity: 1, position: 1),
            entry(card: card(id: "thopter", name: "Ornithopter", typeLine: "Artifact Creature", priceUSD: nil), quantity: 3, position: 2),
            entry(card: mdfc(), quantity: 1, position: 3),
            entry(card: card(id: "aura", name: "Quiet Mantle", colorIdentity: ["W"], typeLine: "Enchantment", priceUSD: 2), quantity: 1, position: 4),
            entry(card: nil, quantity: 2, position: 5),
        ]

        let stats = CardCollectionDashboardStats.make(entries: entries, includeLandsInTypes: false)

        XCTAssertEqual(stats.totalQuantity, 10)
        XCTAssertEqual(stats.pricedQuantity, 5)
        XCTAssertEqual(stats.unpricedQuantity, 3)
        XCTAssertEqual(stats.unavailableQuantity, 2)
        XCTAssertEqual(stats.totalPriceUSD, 19, accuracy: 0.0001)
        XCTAssertEqual(stats.colorDistribution.map(\.bucket), [.white, .red, .multicolor, .colorless])
        XCTAssertEqual(colorQuantity(.white, in: stats), 1)
        XCTAssertEqual(colorQuantity(.red, in: stats), 2)
        XCTAssertEqual(colorQuantity(.multicolor, in: stats), 2)
        XCTAssertEqual(colorQuantity(.colorless, in: stats), 3)
        XCTAssertEqual(colorPercentage(.colorless, in: stats), 3.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(stats.topTypes.map(\.name), ["Artifact", "Creature", "Instant", "Enchantment", "Sorcery"])
        XCTAssertEqual(stats.topTypes.map(\.quantity), [3, 3, 3, 1, 1])
        XCTAssertEqual(typePercentage("Instant", in: stats), 3.0 / 11.0, accuracy: 0.0001)

        let statsWithLands = CardCollectionDashboardStats.make(entries: entries, includeLandsInTypes: true)

        XCTAssertEqual(statsWithLands.topTypes.map(\.name), ["Artifact", "Creature", "Instant", "Enchantment", "Land"])
        XCTAssertEqual(statsWithLands.topTypes.map(\.quantity), [3, 3, 3, 1, 1])
        XCTAssertNil(statsWithLands.topTypes.first { $0.name == "Sorcery" })
    }

    func testColorBucketsNormalizeLowercaseSymbolsAndFallbackToColors() {
        let entries = [
            entry(card: card(id: "red", name: "Red Spell", colorIdentity: ["r"], typeLine: "Instant", priceUSD: 1), quantity: 2, position: 0),
            entry(card: card(id: "blue", name: "Blue Spell", colorIdentity: ["u"], typeLine: "Instant", priceUSD: 1), quantity: 3, position: 1),
            entry(card: card(id: "izzet", name: "Izzet Spell", colorIdentity: ["r", "u"], typeLine: "Sorcery", priceUSD: 1), quantity: 4, position: 2),
            entry(card: card(id: "printed", name: "Printed Color", colors: ["g"], typeLine: "Creature", priceUSD: 1), quantity: 5, position: 3),
            entry(card: card(id: "rock", name: "Colorless Rock", typeLine: "Artifact", priceUSD: 1), quantity: 6, position: 4),
        ]

        let stats = CardCollectionDashboardStats.make(entries: entries, includeLandsInTypes: false)

        XCTAssertEqual(stats.colorDistribution.map(\.bucket), [.blue, .red, .green, .multicolor, .colorless])
        XCTAssertEqual(colorQuantity(.red, in: stats), 2)
        XCTAssertEqual(colorQuantity(.blue, in: stats), 3)
        XCTAssertEqual(colorQuantity(.green, in: stats), 5)
        XCTAssertEqual(colorQuantity(.multicolor, in: stats), 4)
        XCTAssertEqual(colorQuantity(.colorless, in: stats), 6)
    }

    private func colorQuantity(_ bucket: CardCollectionColorBucket, in stats: CardCollectionDashboardStats) -> Int? {
        stats.colorDistribution.first { $0.bucket == bucket }?.quantity
    }

    private func colorPercentage(_ bucket: CardCollectionColorBucket, in stats: CardCollectionDashboardStats) -> Double {
        stats.colorDistribution.first { $0.bucket == bucket }?.percentage ?? 0
    }

    private func typePercentage(_ name: String, in stats: CardCollectionDashboardStats) -> Double {
        stats.topTypes.first { $0.name == name }?.percentage ?? 0
    }

    private func entry(card: CardRecord?, quantity: Int, position: Int) -> CardCollectionEntryRecord {
        CardCollectionEntryRecord(
            id: "entry-\(position)",
            listID: "list",
            cardID: card?.id ?? "missing-\(position)",
            position: position,
            quantity: quantity,
            createdAt: Date(timeIntervalSince1970: Double(position)),
            card: card
        )
    }

    private func card(
        id: String,
        name: String,
        colors: [String] = [],
        colorIdentity: [String] = [],
        typeLine: String,
        priceUSD: Double?
    ) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "common",
            priceUSD: priceUSD,
            colorSortKey: 0,
            colors: colors,
            colorIdentity: colorIdentity,
            layout: "normal",
            typeLine: typeLine,
            oracleText: "Test text."
        )
    }

    private func mdfc() -> CardRecord {
        CardRecord(
            id: "mdfc",
            name: "Dawn // Dusk",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "2",
            rarity: "rare",
            priceUSD: 4,
            colorSortKey: 5,
            colorIdentity: ["W", "B"],
            layout: "modal_dfc",
            typeLine: "",
            oracleText: "",
            faces: [
                CardFaceRecord(cardID: "mdfc", faceIndex: 0, name: "Dawn", typeLine: "Sorcery", oracleText: "Return a card."),
                CardFaceRecord(cardID: "mdfc", faceIndex: 1, name: "Dusk", typeLine: "Instant", oracleText: "Destroy a card."),
            ]
        )
    }
}
