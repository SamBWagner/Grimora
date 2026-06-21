import XCTest

@testable import GrimoraCore

final class SearchRefinementTests: XCTestCase {
    func testQueryFragmentsCoverSupportedCardFacets() {
        XCTAssertEqual(SearchRefinement.forKeyword("Devoid").queryFragment, "keyword:Devoid")
        XCTAssertEqual(SearchRefinement.forTypeWord("Legendary").queryFragment, "t:Legendary")
        XCTAssertEqual(SearchRefinement.forColorIdentity(["R", "U"]).queryFragment, "ci:UR")
        XCTAssertEqual(SearchRefinement.forColorIdentity([]).queryFragment, "ci:C")
        XCTAssertEqual(SearchRefinement.forManaValue(3).queryFragment, "mv:3")
        XCTAssertEqual(SearchRefinement.forRarity("mythic").queryFragment, "r:mythic")
        XCTAssertEqual(
            SearchRefinement.forSet(code: "mh3", name: "Modern Horizons 3").queryFragment,
            "set:mh3"
        )
    }

    func testOracleFragmentQuotesAndEscapesSpecialCharacters() {
        let refinement = SearchRefinement.forSelectedOracleText(#"deals "combat" damage \ twice"#)

        XCTAssertEqual(refinement.queryFragment, #"o:"deals \"combat\" damage \\ twice""#)
        XCTAssertNil(SearchQuery.unsupportedReason(for: refinement.queryFragment))
    }

    func testSelectedOracleTextNormalizesRepeatedAndSurroundingWhitespace() {
        let refinement = SearchRefinement.forSelectedOracleText(
            " \n reveal\t a   card. \r\n"
        )

        XCTAssertEqual(refinement.value, "reveal a card.")
        XCTAssertEqual(refinement.queryFragment, #"o:"reveal a card.""#)
    }

    func testExcludedFragmentUsesLeadingNegation() {
        XCTAssertEqual(
            SearchRefinement.forKeyword("Devoid", intent: .exclude).queryFragment,
            "-keyword:Devoid"
        )
    }

    func testAppendingDeduplicatesCanonicalAliasesAndIntent() {
        let excluded = SearchRefinement.forKeyword("Devoid", intent: .exclude)

        XCTAssertTrue(SearchQuery.contains(excluded, in: "-kw:devoid"))
        XCTAssertEqual(
            SearchQuery.appending(excluded, to: "ci:izzet -kw:devoid"),
            "ci:izzet -kw:devoid"
        )
        XCTAssertEqual(
            SearchQuery.appending(excluded.withIntent(.include), to: "-kw:devoid"),
            "-kw:devoid keyword:Devoid"
        )
    }

    func testRefinementStateHydratesAliasesAndCyclesAllStates() {
        let keyword = SearchRefinement.forKeyword("Devoid")
        let oracle = SearchRefinement.forSelectedOracleText("reveal a card")

        XCTAssertEqual(SearchQuery.state(for: keyword, in: "kw:devoid"), .include)
        XCTAssertEqual(SearchQuery.state(for: oracle, in: #"-oracle:"reveal a card""#), .exclude)
        XCTAssertEqual(SearchRefinementState.neutral.next, .include)
        XCTAssertEqual(SearchRefinementState.include.next, .exclude)
        XCTAssertEqual(SearchRefinementState.exclude.next, .neutral)
    }

    func testBatchApplyingReplacesAliasesAndOppositeIntents() {
        let query = "ci:B -kw:devoid oracle:\"draw a card\""
        let result = SearchQuery.applying(
            [
                SearchRefinementUpdate(
                    refinement: .forKeyword("Devoid"),
                    state: .include
                ),
                SearchRefinementUpdate(
                    refinement: .forSelectedOracleText("draw a card"),
                    state: .exclude
                ),
            ],
            to: query
        )

        XCTAssertEqual(result, #"ci:B keyword:Devoid -o:"draw a card""#)
    }

    func testBatchApplyingNeutralRemovesEquivalentTopLevelConditionsAndCleansAnd() {
        let result = SearchQuery.applying(
            [
                SearchRefinementUpdate(
                    refinement: .forKeyword("Devoid"),
                    state: .neutral
                ),
            ],
            to: "ci:B AND kw:devoid AND r:rare"
        )

        XCTAssertEqual(result, "ci:B AND r:rare")
    }

    func testBatchApplyingLeavesComplexExpressionsUntouched() {
        let keyword = SearchRefinement.forKeyword("Devoid")

        XCTAssertEqual(
            SearchQuery.applying(
                [SearchRefinementUpdate(refinement: keyword, state: .exclude)],
                to: "kw:devoid OR t:creature"
            ),
            "kw:devoid OR t:creature -keyword:Devoid"
        )
        XCTAssertEqual(
            SearchQuery.applying(
                [SearchRefinementUpdate(refinement: keyword, state: .exclude)],
                to: "(kw:devoid t:creature) ci:B"
            ),
            "(kw:devoid t:creature) ci:B -keyword:Devoid"
        )
    }

    func testComposedHiddenTermExcludesMatchingCards() throws {
        let database = try CardDatabase(storage: .inMemory)
        var cards = Fixtures.records()
        cards[0].keywords = ["Devoid"]
        cards[1].keywords = ["Flying"]
        try database.replaceAllCards(cards)

        let query = SearchQuery.appending(
            .forKeyword("Devoid", intent: .exclude),
            to: ""
        )
        let response = try database.search(CardSearchRequest(text: query))

        guard case .results(let results, _) = response else {
            return XCTFail("Expected search results.")
        }
        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(results.contains { $0.keywords.contains("Devoid") })
    }
}
