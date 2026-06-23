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

    func testArtistFragmentQuotesMultiWordNamesAndTrims() {
        XCTAssertEqual(
            SearchRefinement.forArtist("Johannes Voss").queryFragment,
            #"artist:"Johannes Voss""#
        )
        // A single bare token needs no quotes.
        XCTAssertEqual(SearchRefinement.forArtist("Rebecca").queryFragment, "artist:Rebecca")
        // Surrounding whitespace is trimmed before quoting.
        XCTAssertEqual(
            SearchRefinement.forArtist("  Seb McKinnon  ").queryFragment,
            #"artist:"Seb McKinnon""#
        )
        XCTAssertEqual(SearchRefinement.forArtist("   ").queryFragment, #"artist:"""#)
        // The generated clause is valid Scryfall syntax.
        XCTAssertNil(
            SearchQuery.unsupportedReason(for: SearchRefinement.forArtist("Johannes Voss").queryFragment)
        )
    }

    func testArtistUniqueArtSearchReturnsEachArtworkOnce() throws {
        // D3: tapping an artist runs `artist:"…" unique:art`, which must surface
        // each distinct illustration once even when prints reuse the same art.
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            artistCard(id: "voss-a1", artist: "Johannes Voss", illustration: "art-1"),
            artistCard(id: "voss-a2", artist: "Johannes Voss", illustration: "art-1"),
            artistCard(id: "voss-b", artist: "Johannes Voss", illustration: "art-2"),
            artistCard(id: "other", artist: "Amy Artist", illustration: "art-9"),
        ])

        // Casing differs from the stored name to exercise normalized matching.
        let query = #"artist:"johannes voss" unique:art"#
        let response = try database.search(CardSearchRequest(text: query))
        guard case .results(let results, _) = response else {
            return XCTFail("Expected search results.")
        }

        // Only Voss's cards, with the duplicated illustration collapsed to one.
        XCTAssertEqual(Set(results.map(\.illustrationID)), ["art-1", "art-2"])
        XCTAssertFalse(results.contains { $0.id == "other" })
        XCTAssertEqual(results.count, 2)
        // Exactly one of the two prints that share art-1 survives.
        XCTAssertEqual(results.filter { $0.illustrationID == "art-1" }.count, 1)
    }

    private func artistCard(id: String, artist: String, illustration: String) -> CardRecord {
        CardRecord(
            id: id,
            name: id,
            releasedAt: "2020-01-01",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: id,
            collectorNumberNumber: 1,
            rarity: "common",
            rarityRank: 0,
            artist: artist,
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature",
            oracleText: "",
            illustrationID: illustration,
            isRealCard: true
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
