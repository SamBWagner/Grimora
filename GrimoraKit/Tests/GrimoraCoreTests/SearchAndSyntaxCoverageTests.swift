@testable import GrimoraCore
import XCTest

final class SearchAndSyntaxCoverageTests: XCTestCase {
    func testPrintingDisplayModeTitlesAndIDs() {
        XCTAssertEqual(PrintingDisplayMode.preferred.id, "preferred")
        XCTAssertEqual(PrintingDisplayMode.preferred.title, "Preferred Printings")
        XCTAssertEqual(PrintingDisplayMode.all.title, "All Printings")
        XCTAssertEqual(PrintingDisplayMode.art.title, "Unique Art")
    }

    func testParserCoversStandaloneQuotesAndInternalEdges() throws {
        XCTAssertNotNil(try ScryfallSyntaxParser.parse("\"Lightning Bolt\"").get())
        XCTAssertNotNil(try ScryfallSyntaxParser.parse("“Lightning Bolt”").get())
        XCTAssertEqual(
            SearchQuery.unsupportedReason(for: "\"unterminated")?.detail,
            "The search query has an unterminated quoted string."
        )
        XCTAssertEqual(
            SearchQuery.unsupportedReason(for: "o:/draw")?.detail,
            "The search query has an unterminated regular expression."
        )
        XCTAssertEqual(
            SearchQuery.unsupportedReason(for: "!")?.detail,
            "Exact-name searches need a card name after `!`."
        )
        XCTAssertNoThrow(try ScryfallSyntaxParser.parse("- lightning").get())
        XCTAssertEqual(SearchQuery.unsupportedReason(for: "() (")?.token, "(")

        var emptyParser = ScryfallSyntaxTreeParser(tokens: [], query: "")
        XCTAssertEqual(try emptyParser.parseUnary(), .all)
        XCTAssertEqual(try emptyParser.parsePrimary(), .all)

        var rightParenParser = ScryfallSyntaxTreeParser(tokens: [.rightParen], query: ")")
        XCTAssertEqual(try rightParenParser.parsePrimary(), .all)
        XCTAssertEqual(rightParenParser.tokenText(.word(ScryfallWordToken(text: "x", source: "source"))), "source")
        XCTAssertEqual(rightParenParser.tokenText(.leftParen), "(")

        let sourceFallback = rightParenParser.splitCondition(
            ScryfallWordToken(text: "color:red", source: "color red")
        )
        XCTAssertEqual(sourceFallback?.value, .bare("red"))
    }

    func testValidatorCoversGreenAndRedValueRules() {
        XCTAssertTrue(ScryfallSyntaxValidator.validate("").isSupportedOffline)

        let invalidQueries = [
            "c:",
            "rarity:/rare/",
            "direction:sideways",
            "include:art",
            "legal:not-a-format",
            "new:watermark",
            "rarity:mythicrare",
            "produces:token"
        ]

        for query in invalidQueries {
            let validation = ScryfallSyntaxValidator.validate(query)
            XCTAssertFalse(validation.isValidScryfall, query)
            XCTAssertFalse(validation.diagnostics.isEmpty, query)
        }
    }

    func testCompilerCoversSupportedFieldFamilies() {
        let queries = [
            "has:watermark", "has:indicator",
            "new:art", "new:artist", "new:flavor", "new:rarity", "new:frame", "new:language",
            "is:dfc", "is:meldpart", "is:meldresult", "is:spell", "is:permanent", "is:historic",
            "is:party", "is:outlaw", "is:modal", "is:vanilla", "is:frenchvanilla", "is:bear",
            "is:manland", "is:funny", "is:booster", "is:planeswalker_deck", "is:companion",
            "is:gamechanger", "is:newinpauper", "is:reserved", "is:digital", "is:alchemy",
            "is:rebalanced", "is:promo", "is:spotlight", "is:scryfallpreview", "is:full",
            "is:foil", "is:nonfoil", "is:etched", "is:glossy", "is:hires", "is:default",
            "is:new", "is:old", "is:unique", "is:hybrid", "is:phyrexian", "is:colorshifted",
            "is:azorius", "is:white", "is:fetchland",
            "t:/dragon/", "o:/draw/", "flavor:/storm/",
            "c!=wu", "c>wu", "c>=wu", "c<wu", "c<=wubrg", "c:multicolor", "c:2",
            "id>2", "id:wu", "produces:g",
            "m>3", "m!=g", "m:gu",
            "mv:even", "mv:odd", "mv:abc", "pow>tou", "tou<pow",
            "r:special", "cn>12", "cn:007",
            "in:paper", "in:mythic", "in:japanese", "in:core", "in:khm",
            "frame:colorshifted", "frame:future",
            "year:abc", "year:2020", "date:now", "date:2024", "date:khm",
            "lang:japanese", "devotion:gu", "devotion:z",
            "artists>1", "illustrations>1", "prints>1", "sets>1", "paperprints>1", "papersets>1",
            "unique:cards", "unique:art", "unique:unknown", "order:name", "direction:ascending",
            "prefer:oldest", "prefer:newest", "prefer:promo", "prefer:default", "prefer:usd-low",
            "prefer:usd-high", "prefer:unknown", "cheapest:usd", "cheapest:eur", "display:grid",
            "restricted:commander", "eur>1", "tix>1", "settype:expansion"
        ]

        for query in queries {
            guard case .success = SearchQuery.compile(query) else {
                return XCTFail("Expected query to compile: \(query)")
            }
        }
    }

    func testCompilerCoversUnsupportedBranches() {
        let unsupportedQueries = [
            "has:unknown",
            "new:unknown",
            "is:unknown",
            "include:unknown",
            "b:unknown",
            "c:token",
            "produces:token",
            "zz:unknown"
        ]

        for query in unsupportedQueries {
            guard case .failure = SearchQuery.compile(query) else {
                return XCTFail("Expected query to be unsupported: \(query)")
            }
        }

        XCTAssertNil(SearchQuery.explicitSyntaxUnsupportedReason(for: "lightning bolt"))
        XCTAssertEqual(SearchQueryUnsupportedReason(query: "q", token: "token").message, "“token” is Scryfall syntax that Grimora does not support offline yet.")
    }

    func testPostFiltersCoverAllFieldsAndNegation() {
        let card = CardRecord(
            id: "filter",
            name: "Storm Dragon",
            setCode: "tst",
            setName: "Test",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature Dragon",
            oracleText: "Draw a card.",
            flavorText: "Thunder rolls.",
            faces: [
                CardFaceRecord(cardID: "filter", faceIndex: 0, name: "Face", typeLine: "Instant", oracleText: "Scry 1.")
            ]
        )

        XCTAssertTrue(SearchQuery.PostFilter(field: .type, pattern: "instant", negated: false).matches(card))
        XCTAssertTrue(SearchQuery.PostFilter(field: .oracle, pattern: "scry", negated: false).matches(card))
        XCTAssertTrue(SearchQuery.PostFilter(field: .flavor, pattern: "thunder", negated: false).matches(card))
        XCTAssertTrue(SearchQuery.PostFilter(field: .name, pattern: "[", negated: true).matches(card))
        XCTAssertTrue(SearchQuery.PostFilter(field: .flavor, pattern: "^$", negated: false).matches(
            CardRecord(
                id: "no-flavor",
                name: "No Flavor",
                setCode: "tst",
                setName: "Test",
                setType: "expansion",
                collectorNumber: "2",
                rarity: "common",
                colorSortKey: 0,
                layout: "normal",
                typeLine: "Creature",
                oracleText: ""
            )
        ))
    }

    func testCompilerInternalEmptyBareTerm() throws {
        let tree = ScryfallQuerySyntaxTree(query: " ", root: .term(.bare("   ")))
        guard case .success(let plan) = SearchQuery.compileSyntaxTree(tree) else {
            return XCTFail("Expected internal empty term to compile")
        }
        XCTAssertNil(plan.whereSQL)
    }

}
