@testable import GrimoraCore
import XCTest

final class ScryfallSyntaxParserTests: XCTestCase {
    func testParserModelsQuotedRegexExactNamesBooleanAndNegation() throws {
        let query = #"t:legendary (o:"draw a card" or name:/\bizzet\b/) -is:funny !"Lightning Bolt""#
        guard case .success(let tree) = ScryfallSyntaxParser.parse(query) else {
            return XCTFail("Expected syntax tree")
        }

        let conditions = tree.root.conditions
        XCTAssertEqual(conditions.map(\.canonicalField), ["type", "oracle", "name", "is"])
        XCTAssertEqual(conditions[1].value, .quoted("draw a card"))
        XCTAssertEqual(conditions[2].value, .regularExpression(#"\bizzet\b"#))
        XCTAssertEqual(tree.root.exactNames, ["Lightning Bolt"])

        let validation = ScryfallSyntaxValidator.validate(query)
        XCTAssertTrue(validation.isValidScryfall)
        XCTAssertFalse(validation.isSupportedOffline)
        XCTAssertEqual(validation.unsupportedTerms.first?.token, "OR")
    }

    func testParserTreatsSmartQuotesAsQuotedValues() throws {
        let query = "o:\u{201C}creatures you control have haste\u{201D} !\u{201C}Lightning Bolt\u{201D}"
        guard case .success(let tree) = ScryfallSyntaxParser.parse(query) else {
            return XCTFail("Expected syntax tree")
        }

        let conditions = tree.root.conditions
        XCTAssertEqual(conditions.map(\.canonicalField), ["oracle"])
        XCTAssertEqual(conditions.first?.value, .quoted("creatures you control have haste"))
        XCTAssertEqual(tree.root.exactNames, ["Lightning Bolt"])

        let validation = ScryfallSyntaxValidator.validate(query)
        XCTAssertTrue(validation.isValidScryfall)
        XCTAssertTrue(validation.isSupportedOffline)
    }

    func testOfficialSyntaxFamiliesValidateAsScryfallQueries() {
        let queries = [
            "c:rg",
            "color>=uw -c:red",
            "id<=esper t:instant",
            "id:c t:land",
            "c=2 is:bear",
            #"o:"~ enters tapped""#,
            "kw:flying -t:creature",
            "m:{R/P}",
            "manavalue:even",
            "mv=odd",
            "devotion:{u/b}{u/b}{u/b}",
            "produces=wu",
            "pow>tou c:w t:creature",
            "t:planeswalker loy=3",
            "is:split",
            "is:permanent t:rebel",
            "include:extras t:scheme",
            "r>=r",
            "e:war is:booster",
            "f:modern order:rarity direction:asc",
            "banned:legacy",
            "usd>=0.50 e:ema",
            #"a:"proce""#,
            "ft:mishra",
            "wm:orzhov",
            "border:white t:creature",
            "frame:2003 new:frame in:fut is:reprint",
            "stamp:acorn",
            "game:arena",
            "year<=1994",
            "date>ori",
            "lang:any t:planeswalker unique:prints",
            "is:fetchland",
            "not:reprint e:c16",
            "t:fish or t:bird",
            "t:legendary (t:goblin or t:elf)",
            "through (depths or sands or mists)",
            #"!"sift through sands""#,
            #"name:/\bizzet\b/"#,
            "display:text",
            "prefer:notub"
        ]

        for query in queries {
            let validation = ScryfallSyntaxValidator.validate(query)
            XCTAssertTrue(validation.isValidScryfall, query)
            XCTAssertTrue(validation.diagnostics.isEmpty, query)
        }
    }

    func testValidScryfallSyntaxCanBeUnsupportedOffline() {
        let queries = [
            "cube:vintage",
            "art:squirrel",
            "atag:squirrel",
            "function:removal",
            "otag:dies"
        ]

        for query in queries {
            let validation = ScryfallSyntaxValidator.validate(query)
            XCTAssertTrue(validation.isValidScryfall, query)
            XCTAssertFalse(validation.isSupportedOffline, query)
            XCTAssertEqual(validation.unsupportedTerms.first?.token, query)
        }
    }

    func testMalformedOrUnknownSyntaxIsInvalidScryfall() {
        let expectations: [(query: String, token: String)] = [
            ("(t:creature", "("),
            ("t:creature)", ")"),
            ("c:token", "c:token"),
            ("unknown:thing", "unknown:thing"),
            (#"o:"draw"#, "o:draw")
        ]

        for expectation in expectations {
            let validation = ScryfallSyntaxValidator.validate(expectation.query)
            XCTAssertFalse(validation.isValidScryfall, expectation.query)
            XCTAssertEqual(validation.diagnostics.first?.token, expectation.token, expectation.query)
        }
    }

    func testSeededFuzzQueriesHaveStableValidationResults() {
        var generator = SeededGenerator(seed: 0x51C0_FA11)
        let validConditions = [
            "t:creature",
            "o:draw",
            "kw:flying",
            "c:rg",
            "id:esper",
            "mv<4",
            "pow>2",
            "tou<=3",
            "r:rare",
            "s:war",
            "f:modern",
            "usd>=0.50",
            "year=2025"
        ]

        for index in 0..<120 {
            let first = validConditions[index % validConditions.count]
            let second = validConditions[Int.random(in: 0..<validConditions.count, using: &generator)]
            let query = index.isMultiple(of: 3) ? "(\(first) or \(second))" : "\(first) \(second)"

            let validation = ScryfallSyntaxValidator.validate(query)
            XCTAssertTrue(validation.isValidScryfall, query)
        }

        for index in 0..<40 {
            let query = index.isMultiple(of: 2) ? "(t:creature" : "bogus\(index):value"
            XCTAssertFalse(ScryfallSyntaxValidator.validate(query).isValidScryfall, query)
        }
    }
}

private extension ScryfallQueryNode {
    var conditions: [ScryfallSyntaxCondition] {
        switch self {
        case .all:
            []
        case .term(.condition(let condition)):
            [condition]
        case .term:
            []
        case .and(let nodes), .or(let nodes):
            nodes.flatMap(\.conditions)
        case .not(let node):
            node.conditions
        }
    }

    var exactNames: [String] {
        switch self {
        case .all:
            []
        case .term(.exactName(let name)):
            [name]
        case .term:
            []
        case .and(let nodes), .or(let nodes):
            nodes.flatMap(\.exactNames)
        case .not(let node):
            node.exactNames
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
