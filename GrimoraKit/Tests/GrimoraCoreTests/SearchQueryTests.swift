@testable import GrimoraCore
import XCTest

final class SearchQueryTests: XCTestCase {
    func testPlainTextHasNoUnsupportedReason() {
        XCTAssertNil(SearchQuery.unsupportedReason(for: "lightning bolt"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "Jace, the Mind Sculptor"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "   "))
        XCTAssertNil(SearchQuery.unsupportedReason(for: ":lonely"))
    }

    func testScryfallOperatorsCompile() throws {
        XCTAssertNil(SearchQuery.unsupportedReason(for: "is:commander"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "-is:ub"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "pow>3"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "usd<=1"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "pt>=5"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "b:ravnica"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "ci:rg t:dragon"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "ci=rg t:dragon"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "commander:gruul t:dragon"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "ci<=temur"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "ci>=3"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "legal:commander"))
        XCTAssertNil(SearchQuery.unsupportedReason(for: "legal:pauper"))
    }

    func testBooleanGroupingAndDisplayKeywordsCompile() throws {
        let result = SearchQuery.compile("t:legendary (t:goblin or t:elf) unique:prints order:usd direction:desc")
        guard case .success(let plan) = result else {
            return XCTFail("Expected compiled plan")
        }

        XCTAssertEqual(plan.displayOptions.printingDisplayMode, .all)
        XCTAssertEqual(plan.displayOptions.sortMode, .priceUSD)
        XCTAssertEqual(plan.displayOptions.sortDirection, .descending)
        XCTAssertTrue(plan.whereSQL?.contains(" OR ") == true)
    }

    func testRequestedBooleanGroupingQueryCompilesWithPlayableIdentity() throws {
        guard case .success(let plan) = SearchQuery.compile("(t:creature or t:sorcery) ci:rg mv<5") else {
            return XCTFail("Expected grouped query plan")
        }

        XCTAssertEqual(
            plan.whereSQL,
            "((type_line_key LIKE ?) OR (type_line_key LIKE ?)) AND (color_identity_key NOT LIKE ? AND color_identity_key NOT LIKE ? AND color_identity_key NOT LIKE ?) AND (mana_value < ?)"
        )
        XCTAssertEqual(
            plan.bindings,
            [
                .text("%creature%"),
                .text("%sorcery%"),
                .text("%|w|%"),
                .text("%|u|%"),
                .text("%|b|%"),
                .double(5)
            ]
        )
    }

    func testBooleanGroupingAcceptsMixedCaseOrAndNestedImplicitAnd() throws {
        guard case .success(let mixedCase) = SearchQuery.compile("t:creature Or t:sorcery") else {
            return XCTFail("Expected mixed-case OR to compile")
        }
        XCTAssertEqual(mixedCase.whereSQL, "(type_line_key LIKE ?) OR (type_line_key LIKE ?)")

        guard case .success(let nested) = SearchQuery.compile("t:dragon (o:flying or (o:haste and mv<4))") else {
            return XCTFail("Expected nested boolean query to compile")
        }
        XCTAssertTrue(nested.whereSQL?.contains(" OR ") == true)
        XCTAssertTrue(nested.whereSQL?.contains("mana_value < ?") == true)
        XCTAssertEqual(nested.bindings, [.text("%dragon%"), .text("%flying%"), .text("%haste%"), .double(4)])
    }

    func testBooleanGroupingReportsParenthesisSyntaxFailures() {
        XCTAssertEqual(
            SearchQuery.unsupportedReason(for: "(t:creature")?.detail,
            "The search query has an unclosed parenthesis."
        )
        XCTAssertEqual(
            SearchQuery.unsupportedReason(for: "t:creature)")?.detail,
            "The search query has an unexpected token."
        )
    }

    func testBareTextCompilesAsNameSearch() throws {
        guard case .success(let plan) = SearchQuery.compile("Jace, the Mind Sculptor") else {
            return XCTFail("Expected name-search plan")
        }

        XCTAssertEqual(plan.whereSQL?.components(separatedBy: "cards_name_fts").count, 9)
        XCTAssertEqual(
            plan.bindings,
            [
                .text("jace*"), .text("%jace,%"),
                .text("the*"), .text("%the%"),
                .text("mind*"), .text("%mind%"),
                .text("sculptor*"), .text("%sculptor%")
            ])
    }

    func testBareTextDoesNotCompileStandaloneShortcuts() throws {
        guard case .success(let plan) = SearchQuery.compile("red") else {
            return XCTFail("Expected name-search plan")
        }

        XCTAssertTrue(plan.whereSQL?.contains("cards_name_fts") == true)
        XCTAssertEqual(plan.bindings, [.text("red*"), .text("%red%")])
    }

    func testExplicitSyntaxValidatorAcceptsBareScryfallNameTerms() {
        XCTAssertNil(SearchQuery.explicitSyntaxUnsupportedReason(for: "red goblin blue draw"))
    }

    func testExplicitSyntaxValidatorAcceptsFieldedGeneratedTerms() {
        XCTAssertNil(SearchQuery.explicitSyntaxUnsupportedReason(for: "t:goblin (c:r or c:u) o:draw"))
        XCTAssertNil(SearchQuery.explicitSyntaxUnsupportedReason(for: "name:forest"))
        XCTAssertNil(SearchQuery.explicitSyntaxUnsupportedReason(for: "!\"Lightning Bolt\""))
        XCTAssertEqual(SearchQuery.explicitSyntaxUnsupportedReason(for: "atag:dragon")?.token, "atag:dragon")
    }

    func testColorTokenExplainsColorSyntaxAndTokenCreationAlternative() {
        let reason = SearchQuery.unsupportedReason(for: "c:token")

        XCTAssertEqual(reason?.token, "c:token")
        XCTAssertEqual(
            reason?.detail,
            "`c:` searches card colors and only accepts W/U/B/R/G, colorless, multicolor, or color nicknames. For cards that create creature tokens, use `o:\"creature token\"`."
        )
    }

    func testExactNamesAndRegexCompile() throws {
        guard case .success(let exact) = SearchQuery.compile("!\"Sift Through Sands\"") else {
            return XCTFail("Expected exact-name plan")
        }
        XCTAssertEqual(exact.bindings, [.text("sift through sands")])

        guard case .success(let regex) = SearchQuery.compile("name:/\\bizzet\\b/") else {
            return XCTFail("Expected regex plan")
        }
        XCTAssertEqual(regex.postFilters.count, 1)
    }

    func testExternalOnlySyntaxIsUnsupported() {
        XCTAssertEqual(SearchQuery.unsupportedReason(for: "cube:vintage")?.token, "cube:vintage")
        XCTAssertEqual(SearchQuery.unsupportedReason(for: "atag:squirrel")?.token, "atag:squirrel")
    }

    func testFTSExpressionNormalizesWords() {
        XCTAssertEqual(SearchQuery.ftsExpression(for: " Café Forest! "), "cafe* AND forest*")
        XCTAssertNil(SearchQuery.ftsExpression(for: "   "))
    }
}
