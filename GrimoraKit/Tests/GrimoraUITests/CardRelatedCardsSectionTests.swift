import GrimoraCore
@testable import GrimoraUI
import XCTest

@MainActor
final class CardRelatedCardsSectionTests: XCTestCase {
    func testPresentationKeepsLoadingUnavailableEmptyAndFailureDistinct() {
        let key = SemanticCardKey(oracleID: "source", printingID: "source-print")

        XCTAssertEqual(CardRelatedCardsPresentation(state: .idle), .hidden)
        XCTAssertEqual(CardRelatedCardsPresentation(state: .loading(key)), .loading)
        XCTAssertEqual(CardRelatedCardsPresentation(state: .unavailable), .unavailable)
        XCTAssertEqual(CardRelatedCardsPresentation(state: .empty), .empty)
        XCTAssertEqual(
            CardRelatedCardsPresentation(state: .failed("Related cards could not be loaded.")),
            .failure("Related cards could not be loaded.")
        )
    }

    func testEmptyPresentationUsesAnExplicitMessage() {
        XCTAssertEqual(
            CardRelatedCardsSection.emptyMessage,
            "No functionally related cards were found."
        )
    }

    func testLoadedPresentationPreservesExplanationsAndProvenance() throws {
        let related = relatedCard()
        let presentation = CardRelatedCardsPresentation(state: .loaded([related]))

        guard case .cards(let cards) = presentation else {
            XCTFail("Expected related cards presentation")
            return
        }

        XCTAssertEqual(cards, [related])
        XCTAssertEqual(
            CardRelatedCardsSection.explanationText(for: related),
            "Shared: Draw Engine, Enchantment Engine"
        )
        XCTAssertEqual(CardRelatedCardsSection.provenanceText(for: related), "Community tags from Scryfall")
        XCTAssertEqual(
            CardRelatedCardsSection.accessibilityLabel(for: related),
            "Open Related Card, related by Draw Engine and Enchantment Engine. Community tags from Scryfall"
        )
    }

    private func relatedCard() -> SemanticRelatedCard {
        SemanticRelatedCard(
            card: CardRecord(
                id: "related-print",
                oracleID: "related-oracle",
                name: "Related Card",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "1",
                rarity: "rare",
                colorSortKey: 6,
                layout: "normal",
                typeLine: "Enchantment",
                oracleText: "Test text."
            ),
            score: 0.75,
            sharedConcepts: [
                SemanticRelatedCardConcept(
                    tagID: "draw",
                    slug: "draw-engine",
                    label: "Draw Engine",
                    contribution: 2,
                    sources: ["scryfall-oracle-tags@2026-09-22"]
                ),
                SemanticRelatedCardConcept(
                    tagID: "enchantment",
                    slug: "enchantment-engine",
                    label: "Enchantment Engine",
                    contribution: 1,
                    sources: ["scryfall-oracle-tags@2026-09-22"]
                ),
            ]
        )
    }
}
