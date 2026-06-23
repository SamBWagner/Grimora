import GrimoraCore
import XCTest

@testable import GrimoraUI

/// `AdvancedSearchFormView` drives its pickers, segmented controls, and colour
/// pips entirely from the builder enums' display metadata. These tests lock that
/// metadata so every option renders a distinct, non-empty label — a missing or
/// shared value would show a blank or ambiguous control — and confirm the
/// mutation helpers the form exposes produce the expected Scryfall query.
final class AdvancedSearchFormMetadataTests: XCTestCase {
    func testEveryPickerOptionHasANonEmptyLabel() {
        assertNonEmpty(AdvancedSearchStat.allCases, \.displayName)
        assertNonEmpty(AdvancedSearchComparison.allCases, \.displayName)
        assertNonEmpty(AdvancedSearchColorMatch.allCases, \.displayName)
        assertNonEmpty(AdvancedSearchRarity.allCases, \.displayName)
        assertNonEmpty(AdvancedSearchFormat.allCases, \.displayName)
        assertNonEmpty(AdvancedSearchFormatStatus.allCases, \.displayName)
        assertNonEmpty(ScryfallColor.allCases, \.displayName)
    }

    func testPickerLabelsAreUniqueWithinEachControl() {
        assertUnique(AdvancedSearchStat.allCases, \.displayName)
        assertUnique(AdvancedSearchComparison.allCases, \.displayName)
        assertUnique(AdvancedSearchColorMatch.allCases, \.displayName)
        assertUnique(AdvancedSearchRarity.allCases, \.displayName)
        assertUnique(AdvancedSearchFormat.allCases, \.displayName)
        assertUnique(AdvancedSearchFormatStatus.allCases, \.displayName)
    }

    func testColorPipsCoverWubrgWithDistinctSymbols() {
        let symbols = ScryfallColor.allCases.map(\.symbol)
        XCTAssertEqual(symbols, ["W", "U", "B", "R", "G"])
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    func testFormatPickerOptionsAreAllRecognisedByTheValidator() {
        // The "Any" row maps to nil; every concrete format must produce a query
        // the validator accepts so the form can never emit an unknown format.
        for format in AdvancedSearchFormat.allCases {
            var builder = AdvancedSearchBuilder()
            builder.format = format
            XCTAssertTrue(
                ScryfallSyntaxValidator.validate(builder.scryfallQuery).isValidScryfall,
                "Format \(format) produced an invalid query: \(builder.scryfallQuery)"
            )
        }
    }

    /// Mirrors the mutations the form performs (add-another stat rows, colour and
    /// rarity toggles, format + status selection) and verifies the composed query.
    func testFormDrivenMutationsComposeExpectedQuery() {
        var builder = AdvancedSearchBuilder()

        builder.name.text = "Bolt"
        builder.colors.colors.insert(.red)
        builder.colors.match = .including

        builder.addStat()
        builder.stats[0].stat = .manaValue
        builder.stats[0].comparison = .lessThanOrEqual
        builder.stats[0].value = "3"

        builder.rarities.insert(.rare)
        builder.rarities.insert(.mythic)

        builder.format = .modern
        builder.formatStatus = .legal

        XCTAssertEqual(
            builder.scryfallQuery,
            "name:Bolt c>=R mv<=3 (r:rare or r:mythic) f:modern"
        )
        XCTAssertTrue(
            ScryfallSyntaxValidator.validate(builder.scryfallQuery).isSupportedOffline
        )
    }

    func testRemovingTheLastStatRowClearsItsClause() {
        var builder = AdvancedSearchBuilder()
        builder.addStat()
        builder.stats[0].value = "4"
        XCTAssertEqual(builder.scryfallQuery, "mv=4")

        let rowID = builder.stats[0].id
        builder.stats.removeAll { $0.id == rowID }
        XCTAssertTrue(builder.isEmpty)
    }

    private func assertNonEmpty<T>(
        _ items: [T],
        _ label: (T) -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for item in items {
            XCTAssertFalse(
                label(item).trimmingCharacters(in: .whitespaces).isEmpty,
                "\(item) has an empty label",
                file: file,
                line: line
            )
        }
    }

    private func assertUnique<T>(
        _ items: [T],
        _ label: (T) -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let labels = items.map(label)
        XCTAssertEqual(
            Set(labels).count,
            labels.count,
            "Duplicate labels: \(labels)",
            file: file,
            line: line
        )
    }
}
