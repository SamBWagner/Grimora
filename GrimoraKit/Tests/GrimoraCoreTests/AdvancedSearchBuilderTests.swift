import XCTest

@testable import GrimoraCore

final class AdvancedSearchBuilderTests: XCTestCase {
    func testEmptyBuilderProducesEmptyQuery() {
        let builder = AdvancedSearchBuilder()
        XCTAssertEqual(builder.scryfallQuery, "")
        XCTAssertTrue(builder.isEmpty)
    }

    func testTextCriteriaQuoteAndNegate() {
        var builder = AdvancedSearchBuilder()
        builder.name = .init(text: "Lightning Bolt")
        builder.typeLine = .init(text: "Creature")
        builder.oracleText = .init(text: "draw a card", isNegated: true)

        XCTAssertEqual(
            builder.scryfallQuery,
            #"name:"Lightning Bolt" t:Creature -o:"draw a card""#
        )
        assertValid(builder)
    }

    func testColorMatchModesUseExpectedOperators() {
        var including = AdvancedSearchBuilder()
        including.colors = .init(colors: [.red, .white], match: .including)
        XCTAssertEqual(including.scryfallQuery, "c>=WR")

        var exactly = AdvancedSearchBuilder()
        exactly.colors = .init(colors: [.blue, .white], match: .exactly)
        XCTAssertEqual(exactly.scryfallQuery, "c=WU")

        var atMostNegated = AdvancedSearchBuilder()
        atMostNegated.colors = .init(colors: [.green], match: .atMost, isNegated: true)
        XCTAssertEqual(atMostNegated.scryfallQuery, "-c<=G")

        assertValid(including)
        assertValid(exactly)
        assertValid(atMostNegated)
    }

    func testColorsOrderedCanonicallyRegardlessOfInsertionOrder() {
        var builder = AdvancedSearchBuilder()
        builder.colorIdentity = .init(colors: [.green, .black, .white], match: .atMost)
        XCTAssertEqual(builder.scryfallQuery, "id<=WBG")
        assertValid(builder)
    }

    func testStatConstraintsSupportRangesAndNegation() {
        var builder = AdvancedSearchBuilder()
        builder.stats = [
            .init(stat: .manaValue, comparison: .greaterThanOrEqual, value: "2"),
            .init(stat: .manaValue, comparison: .lessThanOrEqual, value: "5"),
            .init(stat: .power, comparison: .notEqual, value: "3", isNegated: true),
        ]

        XCTAssertEqual(builder.scryfallQuery, "mv>=2 mv<=5 -pow!=3")
        assertValid(builder)
    }

    func testBlankStatRowsAreOmitted() {
        var builder = AdvancedSearchBuilder()
        builder.addStat()
        builder.stats[0].value = "  "
        XCTAssertEqual(builder.scryfallQuery, "")
        XCTAssertTrue(builder.isEmpty)
    }

    func testSingleRarityEmitsBareClause() {
        var builder = AdvancedSearchBuilder()
        builder.rarities = [.mythic]
        XCTAssertEqual(builder.scryfallQuery, "r:mythic")
        assertValid(builder)
    }

    func testMultipleRaritiesGroupAsParenthesisedOr() {
        var builder = AdvancedSearchBuilder()
        builder.rarities = [.rare, .common, .uncommon]
        XCTAssertEqual(builder.scryfallQuery, "(r:common or r:uncommon or r:rare)")
        assertValid(builder)
    }

    func testFormatStatusSelectsCorrectField() {
        var legal = AdvancedSearchBuilder()
        legal.format = .commander
        XCTAssertEqual(legal.scryfallQuery, "f:commander")

        var banned = AdvancedSearchBuilder()
        banned.format = .modern
        banned.formatStatus = .banned
        XCTAssertEqual(banned.scryfallQuery, "banned:modern")

        assertValid(legal)
        assertValid(banned)
    }

    func testFullFormCompilesToValidSupportedQuery() {
        var builder = AdvancedSearchBuilder()
        builder.name = .init(text: "Dragon")
        builder.typeLine = .init(text: "Creature")
        builder.oracleText = .init(text: "flying")
        builder.colors = .init(colors: [.red], match: .including)
        builder.colorIdentity = .init(colors: [.red, .green], match: .atMost)
        builder.rarities = [.rare, .mythic]
        builder.format = .commander
        builder.stats = [.init(stat: .power, comparison: .greaterThanOrEqual, value: "4")]

        XCTAssertEqual(
            builder.scryfallQuery,
            "name:Dragon c>=R id<=RG t:Creature o:flying pow>=4 (r:rare or r:mythic) f:commander"
        )
        assertValid(builder)
    }

    func testResetClearsAllCriteria() {
        var builder = AdvancedSearchBuilder()
        builder.name = .init(text: "Bolt")
        builder.rarities = [.rare]
        builder.reset()
        XCTAssertEqual(builder, AdvancedSearchBuilder())
        XCTAssertTrue(builder.isEmpty)
    }

    func testBuilderRoundTripsThroughCodable() throws {
        var builder = AdvancedSearchBuilder()
        builder.colors = .init(colors: [.white, .blue], match: .exactly)
        builder.stats = [.init(stat: .toughness, comparison: .lessThan, value: "2")]
        builder.format = .legacy

        let data = try JSONEncoder().encode(builder)
        let decoded = try JSONDecoder().decode(AdvancedSearchBuilder.self, from: data)
        XCTAssertEqual(decoded, builder)
        XCTAssertEqual(decoded.scryfallQuery, builder.scryfallQuery)
    }

    /// Every query the builder emits must parse, validate, and compile offline,
    /// so the S1 submit path can run it locally.
    private func assertValid(
        _ builder: AdvancedSearchBuilder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let validation = ScryfallSyntaxValidator.validate(builder.scryfallQuery)
        XCTAssertTrue(
            validation.isValidScryfall,
            "Expected valid Scryfall syntax for “\(builder.scryfallQuery)”",
            file: file,
            line: line
        )
        XCTAssertTrue(
            validation.isSupportedOffline,
            "Expected offline-supported query for “\(builder.scryfallQuery)”",
            file: file,
            line: line
        )
    }
}
