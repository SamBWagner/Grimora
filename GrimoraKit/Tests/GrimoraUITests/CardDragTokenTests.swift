import XCTest

@testable import GrimoraUI

final class CardDragTokenTests: XCTestCase {
  func testParsesLegacySingleCardPayload() {
    XCTAssertEqual(CardDragToken.cardIDs(from: "alpha"), ["alpha"])
  }

  func testBulkCardPayloadRoundTripsAndDeduplicatesInOrder() {
    let token = CardDragToken.token(for: ["alpha", "beta", "alpha", "gamma"])

    XCTAssertEqual(CardDragToken.cardIDs(from: token), ["alpha", "beta", "gamma"])
  }

  func testParsesMultiplePayloadsAndSkipsNonCardDragTokens() {
    let cardToken = CardDragToken.token(for: ["alpha", "beta"])
    let listToken = CardListDragToken.token(for: "drafts")
    let entryToken = CardListEntryDragToken.token(for: ["entry-1", "entry-2"])

    XCTAssertEqual(
      CardDragToken.cardIDs(from: [cardToken, "gamma", listToken, entryToken]),
      ["alpha", "beta", "gamma"]
    )
  }

  func testRejectsEmptyAndInvalidCardPayloads() {
    XCTAssertEqual(CardDragToken.cardIDs(from: ""), [])
    XCTAssertEqual(CardDragToken.cardIDs(from: "grimora-card:"), [])
    XCTAssertEqual(CardDragToken.cardIDs(from: "grimora-card:,,,"), [])
    XCTAssertEqual(CardDragToken.cardIDs(from: "alpha,beta"), [])
  }

  func testListEntryDragTokenParsesBulkEntriesAndDeduplicatesInOrder() {
    let token = CardListEntryDragToken.token(for: ["entry-1", "entry-2", "entry-1"])

    XCTAssertEqual(CardListEntryDragToken.entryIDs(from: token), ["entry-1", "entry-2"])
  }
}
