import XCTest

@testable import GrimoraCore
@testable import GrimoraUI

final class HiddenSearchTermsStoreTests: XCTestCase {
    func testStoreRoundTripsJSONNormalizesIntentAndDeduplicates() throws {
        let suiteName = "HiddenSearchTermsStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = HiddenSearchTermsStore(userDefaults: userDefaults)

        store.save([
            .forKeyword("Devoid"),
            .forKeyword("Devoid", intent: .exclude),
            .forSelectedOracleText("  deals combat damage  "),
        ])

        XCTAssertEqual(
            store.load(),
            [
                .forKeyword("Devoid", intent: .exclude),
                .forSelectedOracleText("deals combat damage", intent: .exclude),
            ]
        )
        XCTAssertNotNil(userDefaults.data(forKey: GrimoraSearchPreferences.hiddenSearchTermsKey))
    }

    func testClearRemovesPersistedTerms() throws {
        let suiteName = "HiddenSearchTermsStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = HiddenSearchTermsStore(userDefaults: userDefaults)
        store.save([.forKeyword("Devoid")])

        store.clear()

        XCTAssertTrue(store.load().isEmpty)
    }
}
