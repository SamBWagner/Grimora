import XCTest

@testable import GrimoraUI

final class CardGridSelectionStateTests: XCTestCase {
  func testPlainClickReplacesSelection() {
    var selection = CardGridSelectionState<String>()
    selection.setVisibleIDs(["a", "b", "c"])
    selection.select("a", interaction: .replace)
    selection.select("c", interaction: .replace)

    XCTAssertEqual(selection.selectedIDs, ["c"])
    XCTAssertEqual(selection.lastSelectedID, "c")
  }

  func testCommandClickTogglesSelection() {
    var selection = CardGridSelectionState<String>()
    selection.setVisibleIDs(["a", "b", "c"])
    selection.select("a", interaction: .replace)
    selection.select("b", interaction: .toggle)
    selection.select("a", interaction: .toggle)

    XCTAssertEqual(selection.selectedIDs, ["b"])
    XCTAssertEqual(selection.lastSelectedID, "a")
  }

  func testShiftClickRangeSelectsUsingVisibleOrder() {
    var selection = CardGridSelectionState<String>()
    selection.setVisibleIDs(["a", "b", "c", "d"])
    selection.select("b", interaction: .replace)
    selection.select("d", interaction: .range)

    XCTAssertEqual(selection.selectedIDs, ["b", "c", "d"])
    XCTAssertEqual(selection.selectedOrderedIDs, ["b", "c", "d"])
    XCTAssertEqual(selection.lastSelectedID, "d")
  }

  func testShiftClickWithoutAnchorFallsBackToSingleSelection() {
    var selection = CardGridSelectionState<String>()
    selection.setVisibleIDs(["a", "b", "c"])
    selection.select("c", interaction: .range)

    XCTAssertEqual(selection.selectedIDs, ["c"])
    XCTAssertEqual(selection.lastSelectedID, "c")
  }

  func testPruningRemovesHiddenIDsAndResetsStaleAnchor() {
    var selection = CardGridSelectionState<String>()
    selection.setVisibleIDs(["a", "b", "c", "d"])
    selection.select("b", interaction: .replace)
    selection.select("d", interaction: .range)

    selection.setVisibleIDs(["a", "c"])

    XCTAssertEqual(selection.selectedIDs, ["c"])
    XCTAssertNil(selection.lastSelectedID)
    XCTAssertEqual(selection.selectedOrderedIDs, ["c"])
  }
}
