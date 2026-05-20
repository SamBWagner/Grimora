import GrimoraCore
import XCTest

@testable import GrimoraUI

final class CardListEntrySectionBuilderTests: XCTestCase {
  func testBuildsCategorizedSectionsPreservingEntryOrder() {
    let categories = [
      category(id: "core", name: "Core", position: 0),
      category(id: "land", name: "Land", position: 1),
      category(id: "empty", name: "Empty", position: 2),
    ]
    let entries = [
      entry(id: "uncategorized-0", categoryID: nil, position: 0),
      entry(id: "core-0", categoryID: "core", position: 1),
      entry(id: "land-0", categoryID: "land", position: 2),
      entry(id: "core-1", categoryID: "core", position: 3),
      entry(id: "missing-category", categoryID: "deleted", position: 4),
    ]

    let sections = CardListEntrySectionBuilder.sections(entries: entries, categories: categories)

    XCTAssertEqual(sections.map(\.id), ["mainboard-uncategorized", "core", "land", "empty"])
    XCTAssertEqual(sections.map(\.zone), [.mainboard, .mainboard, .mainboard, .mainboard])
    XCTAssertEqual(sections[0].entries.map(\.id), ["uncategorized-0"])
    XCTAssertEqual(sections[1].entries.map(\.id), ["core-0", "core-1"])
    XCTAssertEqual(sections[2].entries.map(\.id), ["land-0"])
    XCTAssertTrue(sections[3].entries.isEmpty)
    XCTAssertEqual(sections[1].categoryIndex, 0)
    XCTAssertEqual(sections[1].categoryCount, 3)
    XCTAssertEqual(sections.map(\.title), ["Uncategorized", "Core", "Land", "Empty"])
  }

  func testSortsEntriesInsideEachCategoryByEDHRECRank() {
    let categories = [
      category(id: "core", name: "Core", position: 0),
      category(id: "land", name: "Land", position: 1),
    ]
    let entries = [
      entry(id: "core-high", categoryID: "core", position: 0, card: card(id: "core-high", edhrecRank: 40)),
      entry(id: "land-high", categoryID: "land", position: 1, card: card(id: "land-high", edhrecRank: 30)),
      entry(id: "core-low", categoryID: "core", position: 2, card: card(id: "core-low", edhrecRank: 5)),
      entry(id: "land-low", categoryID: "land", position: 3, card: card(id: "land-low", edhrecRank: 1)),
    ]

    let sections = CardListEntrySectionBuilder.sections(
      entries: entries,
      categories: categories,
      displaySortMode: .edhrecRank,
      displaySortDirection: .ascending
    )

    XCTAssertEqual(sections.map(\.id), ["core", "land"])
    XCTAssertEqual(sections[0].entries.map(\.id), ["core-low", "core-high"])
    XCTAssertEqual(sections[1].entries.map(\.id), ["land-low", "land-high"])
  }

  func testReleaseDateAscendingShowsNewestFirstInsideSection() {
    let entries = [
      entry(id: "old", categoryID: nil, position: 0, card: card(id: "old", releasedAt: "2020-01-01")),
      entry(id: "new", categoryID: nil, position: 1, card: card(id: "new", releasedAt: "2024-01-01")),
    ]

    let newestFirst = CardListEntrySectionBuilder.sections(
      entries: entries,
      categories: [],
      displaySortMode: .releaseDate,
      displaySortDirection: .ascending
    )
    let oldestFirst = CardListEntrySectionBuilder.sections(
      entries: entries,
      categories: [],
      displaySortMode: .releaseDate,
      displaySortDirection: .descending
    )

    XCTAssertEqual(newestFirst.first?.entries.map(\.id), ["new", "old"])
    XCTAssertEqual(oldestFirst.first?.entries.map(\.id), ["old", "new"])
  }

  func testMissingCardsAndNilSortValuesSortLastInsideSection() {
    let entries = [
      entry(id: "nil-rank", categoryID: nil, position: 0, card: card(id: "nil-rank", edhrecRank: nil)),
      entry(id: "missing-card", categoryID: nil, position: 1, card: nil),
      entry(id: "ranked", categoryID: nil, position: 2, card: card(id: "ranked", edhrecRank: 10)),
    ]

    let sections = CardListEntrySectionBuilder.sections(
      entries: entries,
      categories: [],
      displaySortMode: .edhrecRank,
      displaySortDirection: .ascending
    )

    XCTAssertEqual(sections.first?.entries.map(\.id), ["ranked", "nil-rank", "missing-card"])
  }

  func testOmitsUncategorizedSectionWhenNoUncategorizedEntriesExist() {
    let categories = [
      category(id: "core", name: "Core", position: 0),
    ]
    let entries = [
      entry(id: "core-0", categoryID: "core", position: 0),
    ]

    let sections = CardListEntrySectionBuilder.sections(entries: entries, categories: categories)

    XCTAssertEqual(sections.map(\.id), ["core"])
    XCTAssertEqual(sections.first?.entries.map(\.id), ["core-0"])
  }

  func testCommanderSectionsUseCommanderMainboardAndMaybeboardZones() {
    let categories = [
      category(id: "side", name: "Side", position: 0, zone: .sideboard),
      category(id: "maybe", name: "Maybe", position: 0, zone: .maybeboard),
    ]
    let entries = [
      entry(id: "commander-0", categoryID: nil, position: 0, zone: .commander),
      entry(id: "side-0", categoryID: "side", position: 0, zone: .sideboard),
      entry(id: "maybe-0", categoryID: nil, position: 0, zone: .maybeboard),
    ]

    let sections = CardListEntrySectionBuilder.sections(
      entries: entries,
      categories: categories,
      ruleset: .commander
    )

    XCTAssertEqual(
      sections.map(\.id),
      ["commander-uncategorized", "mainboard-uncategorized", "maybeboard-uncategorized", "maybe"]
    )
    XCTAssertEqual(sections.map(\.zone), [.commander, .mainboard, .maybeboard, .maybeboard])
    XCTAssertEqual(sections.map(\.title), [
      "Commander - Uncategorized",
      "Uncategorized",
      "Maybeboard - Uncategorized",
      "Maybeboard - Maybe",
    ])
    XCTAssertEqual(sections[1].entries.map(\.id), [])
    XCTAssertEqual(sections[2].entries.map(\.id), ["maybe-0"])
  }

  func testConstructedSectionsUseMainboardSideboardAndMaybeboardZones() {
    let categories = [
      category(id: "side", name: "Side", position: 0, zone: .sideboard),
      category(id: "maybe", name: "Maybe", position: 0, zone: .maybeboard),
    ]
    let entries = [
      entry(id: "commander-0", categoryID: nil, position: 0, zone: .commander),
      entry(id: "side-0", categoryID: "side", position: 0, zone: .sideboard),
      entry(id: "maybe-0", categoryID: nil, position: 0, zone: .maybeboard),
    ]

    let sections = CardListEntrySectionBuilder.sections(
      entries: entries,
      categories: categories,
      ruleset: .modern
    )

    XCTAssertEqual(
      sections.map(\.id),
      ["mainboard-uncategorized", "side", "maybeboard-uncategorized", "maybe"]
    )
    XCTAssertEqual(sections.map(\.zone), [.mainboard, .sideboard, .maybeboard, .maybeboard])
    XCTAssertEqual(sections.map(\.title), [
      "Uncategorized",
      "Sideboard - Side",
      "Maybeboard - Uncategorized",
      "Maybeboard - Maybe",
    ])
    XCTAssertEqual(sections[0].entries.map(\.id), [])
    XCTAssertEqual(sections[1].entries.map(\.id), ["side-0"])
    XCTAssertEqual(sections[2].entries.map(\.id), ["maybe-0"])
  }

  private func category(
    id: CardListCategoryRecord.ID,
    name: String,
    position: Int,
    zone: CardListZone = .mainboard
  ) -> CardListCategoryRecord {
    CardListCategoryRecord(
      id: id,
      listID: "list",
      zone: zone,
      name: name,
      position: position,
      createdAt: .init(timeIntervalSince1970: TimeInterval(position)),
      updatedAt: .init(timeIntervalSince1970: TimeInterval(position))
    )
  }

  private func entry(
    id: CardListEntryRecord.ID,
    categoryID: CardListCategoryRecord.ID?,
    position: Int,
    zone: CardListZone = .mainboard,
    card: CardRecord? = nil
  ) -> CardListEntryRecord {
    CardListEntryRecord(
      id: id,
      listID: "list",
      zone: zone,
      categoryID: categoryID,
      cardID: "card-\(position)",
      position: position,
      createdAt: .init(timeIntervalSince1970: TimeInterval(position)),
      card: card
    )
  }

  private func card(
    id: CardRecord.ID,
    releasedAt: String? = "2024-01-01",
    edhrecRank: Int? = nil
  ) -> CardRecord {
    CardRecord(
      id: id,
      name: id,
      releasedAt: releasedAt,
      setCode: "tst",
      setName: "Test Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "common",
      edhrecRank: edhrecRank,
      colorSortKey: 0,
      layout: "normal",
      typeLine: "Creature",
      oracleText: ""
    )
  }
}
