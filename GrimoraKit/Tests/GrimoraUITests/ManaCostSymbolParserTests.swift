@testable import GrimoraUI
import XCTest

final class ManaCostSymbolParserTests: XCTestCase {
    func testParsesScryfallManaCostTokensInOrder() {
        XCTAssertEqual(
            ManaCostSymbolParser.symbols(in: "{1}{G}{W/U}{X}"),
            [
                ManaCostSymbol(rawValue: "1"),
                ManaCostSymbol(rawValue: "G"),
                ManaCostSymbol(rawValue: "W/U"),
                ManaCostSymbol(rawValue: "X")
            ]
        )
    }

    func testAccessibilityTextNamesManaSymbols() {
        XCTAssertEqual(
            ManaCostSymbolParser.accessibilityText(for: "{1}{G}{W/U}{G/P}{C}"),
            "1 green white blue green phyrexian colorless"
        )
    }

    func testEmptyCostReportsNone() {
        XCTAssertEqual(ManaCostSymbolParser.accessibilityText(for: ""), "none")
    }

    func testMemoizedSymbolsMatchFreshParseAcrossRepeatedCalls() {
        for cost in ["{2}{W}{U}", "{X}{R/P}", "{G/U}", "{S}", "{C}", ""] {
            XCTAssertEqual(
                ManaCostSymbolParser.symbols(in: cost),
                ManaCostSymbolParser.symbols(in: cost))
        }
        XCTAssertEqual(
            ManaCostSymbolParser.symbols(in: "{2}{W}{U}"),
            [
                ManaCostSymbol(rawValue: "2"),
                ManaCostSymbol(rawValue: "W"),
                ManaCostSymbol(rawValue: "U")
            ])
    }

    func testMemoizedAccessibilityTextMatchesAcrossRepeatedCalls() {
        XCTAssertEqual(
            ManaCostSymbolParser.accessibilityText(for: "{1}{G}{W/U}{G/P}{C}"),
            ManaCostSymbolParser.accessibilityText(for: "{1}{G}{W/U}{G/P}{C}"))
        XCTAssertEqual(
            ManaCostSymbolParser.accessibilityText(for: "{1}{G}{W/U}{G/P}{C}"),
            "1 green white blue green phyrexian colorless")
    }
}
