import XCTest

@testable import GrimoraUI

/// The advanced-search builder ships enabled by default and is persisted under a
/// stable key, so the on-screen affordance appears until a user opts out in
/// Settings (S7c).
final class AdvancedSearchPreferencesTests: XCTestCase {
    func testAdvancedSearchIsEnabledByDefault() {
        XCTAssertTrue(GrimoraSearchPreferences.defaultAdvancedSearchEnabled)
    }

    func testAdvancedSearchPreferenceKeyIsStable() {
        // Changing this string silently resets every user's preference.
        XCTAssertEqual(
            GrimoraSearchPreferences.advancedSearchEnabledKey,
            "Grimora.search.advancedFormEnabled"
        )
    }
}
