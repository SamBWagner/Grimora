@testable import GrimoraCore
import XCTest

final class SearchQueryCompilerEdgeCoverageTests: XCTestCase {
    func testAdditionalSupportedAliasesAndMetadataBranches() {
        let queries = [
            "fo:draw",
            "st:expansion",
            "r:common",
            "r:uncommon",
            "b:ravnica",
            "m>x",
            "-name:/storm/",
            "is:bikeland",
            "is:multicolor",
            "unique:cards direction:ascending",
            "unique:cards or direction:ascending"
        ]

        for query in queries {
            guard case .success = SearchQuery.compile(query) else {
                return XCTFail("Expected query to compile: \(query)")
            }
        }
    }

    func testCompilerHelperFallbacks() throws {
        let compiler = Compiler(query: "helpers")

        XCTAssertEqual(compiler.sqlOperator(for: "~", defaultOperator: "="), "=")
        XCTAssertNil(compiler.estimatedManaValue("nope"))
        XCTAssertNil(compiler.estimatedManaValue(""))
        XCTAssertEqual(compiler.estimatedManaValue("{X}"), 0)
        XCTAssertEqual(compiler.conditionFieldName(from: "plain"), "")
        XCTAssertNil(compiler.landShortcutSQL("not-a-land"))
        XCTAssertEqual(
            compiler.landShortcutSQLByName["battlebondland"],
            "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more opponents%'"
        )

        let fallbackName = compiler.compileNameContains(column: "name_key", value: "!!!")
        XCTAssertEqual(fallbackName.sql, "name_key LIKE ?")

        let defaultColor = try compiler.compileColor(
            column: "colors_key",
            countColumn: "color_count",
            op: "~",
            value: "w",
            original: "c~w"
        )
        XCTAssertEqual(defaultColor.sql, "colors_key = ?")

        let unequalMana = compiler.compileMana(op: "!=", value: "", original: "m!=")
        XCTAssertEqual(unequalMana.sql, "mana_cost != ?")
    }

    func testParserBooleanShapeAndSupportFallbacks() throws {
        let orTree = try ScryfallSyntaxParser.parse("lightning or bolt").get()
        guard case .or = orTree.root else {
            return XCTFail("Expected OR syntax tree")
        }

        let andTree = try ScryfallSyntaxParser.parse("lightning bolt").get()
        guard case .and = andTree.root else {
            return XCTFail("Expected AND syntax tree")
        }

        XCTAssertFalse("abc".isReadyToStartScryfallRegex)
        XCTAssertEqual(
            SearchQuery.explicitSyntaxUnsupportedReason(for: "cube:vintage")?.token,
            "cube:vintage"
        )

        var sourceFallbackParser = ScryfallSyntaxTreeParser(
            tokens: [.word(ScryfallWordToken(text: "-source", source: "source"))],
            query: "source"
        )
        XCTAssertEqual(try sourceFallbackParser.parsePrimary(), .not(.term(.bare("source"))))

        let underscoreCondition = sourceFallbackParser.splitCondition(
            ScryfallWordToken(text: "_:value", source: "_:value")
        )
        XCTAssertEqual(underscoreCondition?.field, "_")
    }
}
