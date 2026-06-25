@testable import GrimoraCore
import XCTest

final class ScryfallSyntaxHighlighterTests: XCTestCase {
    private func highlights(_ query: String) -> [ScryfallClauseHighlight] {
        ScryfallSyntaxHighlighter.segments(for: query).map(\.highlight)
    }

    func testEmptyQueryHasNoSegments() {
        XCTAssertTrue(ScryfallSyntaxHighlighter.segments(for: "").isEmpty)
        XCTAssertTrue(ScryfallSyntaxHighlighter.segments(for: "   ").isEmpty)
    }

    func testTrailingClauseTurnsGreenAsSoonAsItIsValid() {
        // Valid syntax reads green live — no completing space required.
        XCTAssertEqual(highlights("mv=1"), [.valid])
        XCTAssertEqual(highlights("mv=1 "), [.valid])
    }

    func testTrailingClauseStaysWhiteWhileNotYetValid() {
        // A trailing clause that does not yet parse is held white (not red) so it
        // does not flash while it is still being typed.
        XCTAssertEqual(highlights("mv="), [.pending])
    }

    func testValidClauseReadsGreenRegardlessOfKeywordCase() {
        // The user's example: a valid colour-identity clause is green as typed, even
        // when the keyboard auto-capitalises the field keyword.
        XCTAssertEqual(highlights("ci:b"), [.valid])
        XCTAssertEqual(highlights("Ci:b"), [.valid])
    }

    func testCompletedValidAndInvalidClausesColourGreenAndRed() {
        // `type:creature` is valid; the unrecognized `foo:bar` field is invalid.
        XCTAssertEqual(highlights("type:creature foo:bar "), [.valid, .invalid])
    }

    func testInvalidClauseAheadOfActiveTrailingClause() {
        // The first clause is completed and invalid; the trailing one is still being
        // typed and not yet valid, so it is held white.
        XCTAssertEqual(highlights("foo:bar mv="), [.invalid, .pending])
        // A valid trailing clause reads green even behind a completed invalid one.
        XCTAssertEqual(highlights("foo:bar mv=1"), [.invalid, .valid])
    }

    func testUnfinishedGroupIsYellowUntilClosed() {
        // The brief's worked example: a multi-stage clause mid-typing.
        XCTAssertEqual(highlights("(mv=1 or mv"), [.incomplete])
        // Once the group closes it validates as a single valid clause.
        XCTAssertEqual(highlights("(mv=1 or mv=2)"), [.valid])
    }

    func testUnfinishedQuoteIsYellow() {
        XCTAssertEqual(highlights("o:\"draw a"), [.incomplete])
        XCTAssertEqual(highlights("o:\"draw a card\" "), [.valid])
    }

    func testSegmentRangesMapBackToOriginalText() {
        let query = "type:creature foo:bar"
        let segments = ScryfallSyntaxHighlighter.segments(for: query)
        XCTAssertEqual(segments.map { String(query[$0.range]) }, ["type:creature", "foo:bar"])
        XCTAssertEqual(segments.map(\.text), ["type:creature", "foo:bar"])
    }

    func testInvalidClauseCountTracksRedClauses() {
        XCTAssertEqual(ScryfallSyntaxHighlighter.invalidClauseCount(for: "type:creature "), 0)
        XCTAssertEqual(ScryfallSyntaxHighlighter.invalidClauseCount(for: "foo:bar "), 1)
        XCTAssertEqual(ScryfallSyntaxHighlighter.invalidClauseCount(for: "foo:bar baz:qux "), 2)
        // A pending trailing clause is not yet counted as invalid.
        XCTAssertEqual(ScryfallSyntaxHighlighter.invalidClauseCount(for: "foo:bar"), 0)
    }
}
