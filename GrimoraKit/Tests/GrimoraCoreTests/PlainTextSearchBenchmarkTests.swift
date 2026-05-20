@testable import GrimoraCore
import XCTest

final class PlainTextSearchBenchmarkTests: XCTestCase {
    func testGoldenPlainTextFixturesProduceValidOfflineQueries() {
        for fixture in PlainTextSearchBenchmarkFixture.goldenFixtures {
            XCTAssertFalse(fixture.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(fixture.acceptedQueries.contains(fixture.expectedQuery), fixture.prompt)

            for query in fixture.acceptedQueries {
                let validation = ScryfallSyntaxValidator.validate(query)
                XCTAssertTrue(validation.isValidScryfall, "\(fixture.prompt) -> \(query)")
                XCTAssertTrue(validation.isSupportedOffline, "\(fixture.prompt) -> \(query)")
                XCTAssertNil(SearchQuery.unsupportedReason(for: query), "\(fixture.prompt) -> \(query)")
            }
        }
    }

    func testGoldenPlainTextFixturesKeepSpecificExpectedOutputs() {
        XCTAssertEqual(
            PlainTextSearchBenchmarkFixture.expectedQuery(for: "red dragons under four mana"),
            "t:dragon c:r mv<4"
        )
        XCTAssertEqual(
            PlainTextSearchBenchmarkFixture.expectedQuery(for: "creates tokens that are creatures"),
            #"o:"creature token""#
        )
        XCTAssertEqual(
            PlainTextSearchBenchmarkFixture.expectedQuery(for: "Lightning Bolt"),
            #"!"Lightning Bolt""#
        )
    }
}

private struct PlainTextSearchBenchmarkFixture {
    var prompt: String
    var expectedQuery: String
    var acceptedAlternatives: [String] = []

    var acceptedQueries: [String] {
        [expectedQuery] + acceptedAlternatives
    }

    static let goldenFixtures: [PlainTextSearchBenchmarkFixture] = [
        PlainTextSearchBenchmarkFixture(
            prompt: "red dragons under four mana",
            expectedQuery: "t:dragon c:r mv<4"
        ),
        PlainTextSearchBenchmarkFixture(
            prompt: "goblins that are red or blue and draw cards",
            expectedQuery: #"t:goblin (c:r or c:u) o:draw"#,
            acceptedAlternatives: [#"t:goblin (c:red or c:blue) o:draw"#]
        ),
        PlainTextSearchBenchmarkFixture(
            prompt: "creates tokens that are creatures",
            expectedQuery: #"o:"creature token""#
        ),
        PlainTextSearchBenchmarkFixture(
            prompt: "cheap green ramp spells legal in commander",
            expectedQuery: "c:g o:ramp mv<4 f:commander"
        ),
        PlainTextSearchBenchmarkFixture(
            prompt: "Lightning Bolt",
            expectedQuery: #"!"Lightning Bolt""#,
            acceptedAlternatives: ["name:Lightning"]
        )
    ]

    static func expectedQuery(for prompt: String) -> String? {
        goldenFixtures.first { $0.prompt == prompt }?.expectedQuery
    }
}
