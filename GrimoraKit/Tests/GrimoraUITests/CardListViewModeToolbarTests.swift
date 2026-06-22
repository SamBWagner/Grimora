import GrimoraCore
import XCTest

@testable import GrimoraUI

/// The iOS/visionOS list-detail toolbar drives its segmented view-mode picker
/// from `CardListViewMode`'s display metadata. These tests lock that metadata so
/// every mode keeps a distinct, non-empty label and SF Symbol — a missing or
/// shared value would render a blank or ambiguous segment in the cluster.
final class CardListViewModeToolbarTests: XCTestCase {
    func testEveryModeHasNonEmptyTitleAndSymbol() {
        for mode in CardListViewMode.allCases {
            XCTAssertFalse(
                mode.toolbarTitle.isEmpty,
                "\(mode) is missing a toolbar title"
            )
            XCTAssertFalse(
                mode.systemImage.isEmpty,
                "\(mode) is missing an SF Symbol"
            )
        }
    }

    func testTitlesAndSymbolsAreUniqueAcrossModes() {
        let titles = CardListViewMode.allCases.map(\.toolbarTitle)
        let symbols = CardListViewMode.allCases.map(\.systemImage)

        XCTAssertEqual(
            Set(titles).count,
            titles.count,
            "Two view modes share a toolbar title"
        )
        XCTAssertEqual(
            Set(symbols).count,
            symbols.count,
            "Two view modes share an SF Symbol"
        )
    }

    func testGridAndListUseExpectedLabels() {
        XCTAssertEqual(CardListViewMode.grid.toolbarTitle, "Gallery")
        XCTAssertEqual(CardListViewMode.list.toolbarTitle, "List")
    }
}
