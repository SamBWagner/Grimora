import GrimoraCore
@testable import GrimoraUI
import XCTest

@MainActor
final class CardFunctionalTagsSectionTests: XCTestCase {
    func testPresentationKeepsLoadingUnavailableEmptyAndFailureDistinct() {
        let key = SemanticCardKey(oracleID: "oracle-card", printingID: "printing-card")

        XCTAssertEqual(CardFunctionalTagsPresentation(state: .idle), .hidden)
        XCTAssertEqual(CardFunctionalTagsPresentation(state: .loading(key)), .loading)
        XCTAssertEqual(CardFunctionalTagsPresentation(state: .unavailable), .unavailable)
        XCTAssertEqual(CardFunctionalTagsPresentation(state: .empty), .empty)
        XCTAssertEqual(
            CardFunctionalTagsPresentation(state: .failed("Could not load.")),
            .failure("Could not load.")
        )
    }

    func testLoadedPresentationPreservesTagAndCommunityProvenanceCopy() {
        let tag = SemanticCardFunctionalTag(
            tagID: "tag-draw-engine",
            slug: "draw-engine",
            label: "Draw Engine",
            description: "Provides repeatable card draw.",
            annotation: "repeatable",
            sources: ["scryfall-oracle-tags@2026-06-14"]
        )

        XCTAssertEqual(CardFunctionalTagsPresentation(state: .loaded([tag])), .tags([tag]))
        XCTAssertEqual(
            CardFunctionalTagsSection.provenanceText(for: [tag]),
            "Community tags from Scryfall"
        )
        XCTAssertEqual(
            CardFunctionalTagsSection.accessibilityLabel(for: tag),
            "Search cards tagged Draw Engine"
        )
    }

    func testProvenanceUsesActualNonScryfallSources() {
        let tag = SemanticCardFunctionalTag(
            tagID: "tag-curated",
            slug: "curated",
            label: "Curated",
            description: nil,
            annotation: nil,
            sources: ["curated-functional-tags"]
        )

        XCTAssertEqual(
            CardFunctionalTagsSection.provenanceText(for: [tag]),
            "Source: curated-functional-tags"
        )
    }
}
