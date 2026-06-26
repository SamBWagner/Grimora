import XCTest

@testable import GrimoraUI

final class CardCollectionCategoryReorderTests: XCTestCase {
  func testDestinationPositionMapsRepresentativeMoves() {
    // SwiftUI `.onMove` offsets are expressed in pre-removal indices; the model expects the
    // post-removal insertion index.
    XCTAssertEqual(CardCollectionCategoryReorder.destinationPosition(forMoveFrom: IndexSet(integer: 1), to: 0), 0)
    XCTAssertEqual(CardCollectionCategoryReorder.destinationPosition(forMoveFrom: IndexSet(integer: 0), to: 3), 2)
    XCTAssertEqual(CardCollectionCategoryReorder.destinationPosition(forMoveFrom: IndexSet(integer: 2), to: 0), 0)
    XCTAssertEqual(CardCollectionCategoryReorder.destinationPosition(forMoveFrom: IndexSet(integer: 0), to: 2), 1)
    XCTAssertEqual(CardCollectionCategoryReorder.destinationPosition(forMoveFrom: IndexSet(integer: 2), to: 2), 2)
  }

  func testDestinationPositionReturnsNilForEmptySource() {
    XCTAssertNil(CardCollectionCategoryReorder.destinationPosition(forMoveFrom: IndexSet(), to: 1))
  }

  /// The mapping must land the moved element at exactly the index a native `Array.move` (the same
  /// operation SwiftUI's `List.onMove` performs) would, across every single-row move for small
  /// collections. This guards the reorder overlay against off-by-one drift versus the database.
  func testDestinationPositionMatchesArrayMoveForAllSingleRowMoves() {
    for count in 1...6 {
      let base = Array(0..<count)
      for from in 0..<count {
        for offset in 0...count where offset != from && offset != from + 1 {
          var reordered = base
          reordered.move(fromOffsets: IndexSet(integer: from), toOffset: offset)
          let expectedIndex = try? XCTUnwrap(reordered.firstIndex(of: from))

          let destination = CardCollectionCategoryReorder.destinationPosition(
            forMoveFrom: IndexSet(integer: from),
            to: offset
          )

          XCTAssertEqual(
            destination,
            expectedIndex,
            "from \(from) to \(offset) in count \(count) should resolve to the Array.move index"
          )
        }
      }
    }
  }
}
