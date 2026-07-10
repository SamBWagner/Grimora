import GrimoraCore
import XCTest

@testable import GrimoraUI

final class CardCollectionEntrySectionBuilderTests: XCTestCase {
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

    let sections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

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

    let sections = CardCollectionEntrySectionBuilder.sections(
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

    let newestFirst = CardCollectionEntrySectionBuilder.sections(
      entries: entries,
      categories: [],
      displaySortMode: .releaseDate,
      displaySortDirection: .ascending
    )
    let oldestFirst = CardCollectionEntrySectionBuilder.sections(
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

    let sections = CardCollectionEntrySectionBuilder.sections(
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

    let sections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

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

    let sections = CardCollectionEntrySectionBuilder.sections(
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

  func testDetailSnapshotExcludesCollapsedEntriesFromExpandedSequence() {
    let categories = [
      category(id: "core", name: "Core", position: 0),
      category(id: "land", name: "Land", position: 1),
    ]
    let entries = [
      entry(id: "core-0", categoryID: "core", position: 0),
      entry(id: "land-0", categoryID: "land", position: 1),
      entry(id: "core-1", categoryID: "core", position: 2),
    ]

    let builtSections = CardCollectionEntrySectionBuilder.sections(
      entries: entries,
      categories: categories,
      ruleset: .none,
      displaySortMode: nil,
      displaySortDirection: .ascending
    )
    let snapshot = CardCollectionDetailSnapshot(
      visibleEntries: entries,
      builtSections: builtSections,
      collapsedSectionIDs: ["core"],
      isSearchActive: false,
      totalEntryCount: 3
    )

    XCTAssertEqual(snapshot.sections.map(\.id), ["core", "land"])
    XCTAssertEqual(snapshot.visibleEntries.map(\.id), ["core-0", "land-0", "core-1"])
    XCTAssertEqual(snapshot.expandedEntries.map(\.id), ["land-0"])
    XCTAssertEqual(snapshot.expandedEntryIDs, ["land-0"])
    XCTAssertEqual(snapshot.entryCountText, "3 cards")
  }

  func testBuildsProductionSizedCategorizedInputWithoutChangingStableSectionIDs() {
    let categories = (0..<12).map { index in
      category(id: "category-\(index)", name: "Category \(index)", position: index)
    }
    let entries = (0..<240).map { index in
      entry(
        id: "entry-\(index)",
        categoryID: categories[index % categories.count].id,
        position: index
      )
    }

    let sections = CardCollectionEntrySectionBuilder.sections(
      entries: entries,
      categories: categories
    )

    XCTAssertEqual(sections.map(\.id), categories.map(\.id))
    XCTAssertEqual(sections.flatMap(\.entries).count, entries.count)
    XCTAssertEqual(sections.map(\.entries.count), Array(repeating: 20, count: 12))
  }

  // MARK: - Multi-category ghosts and shadowed categories

  func testSecondaryTagsBecomeGhostEntriesWithoutLeavingTheirPrimarySection() {
    let categories = [
      category(id: "creatures", name: "Creatures", position: 0),
      category(id: "walkers", name: "Planeswalkers", position: 1),
    ]
    let entries = [
      entry(id: "bear", categoryID: "creatures", secondaryCategoryIDs: ["walkers"], position: 0),
      entry(id: "elf", categoryID: "creatures", position: 1),
    ]

    let sections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

    XCTAssertEqual(sections.map(\.id), ["creatures", "walkers"])
    XCTAssertEqual(sections[0].entries.map(\.id), ["bear", "elf"])
    XCTAssertTrue(sections[0].ghostEntries.isEmpty)
    XCTAssertTrue(sections[1].entries.isEmpty)
    XCTAssertEqual(sections[1].ghostEntries.map(\.id), ["bear"])
    XCTAssertTrue(sections[1].isGhost(entries[0]))
    XCTAssertFalse(sections[0].isGhost(entries[0]))
  }

  /// The reported bug: a category holding nothing but tagged cards used to render an empty
  /// heading. It should stay hidden until the collection opts into showing multi-category cards.
  func testCategoryHoldingOnlyTaggedCardsIsHiddenUntilGhostsAreShown() {
    let categories = [
      category(id: "creatures", name: "Creatures", position: 0),
      category(id: "walkers", name: "Planeswalkers", position: 1),
    ]
    let entries = [
      entry(id: "bear", categoryID: "creatures", secondaryCategoryIDs: ["walkers"], position: 0)
    ]
    let builtSections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

    let hidden = makeSnapshot(entries: entries, builtSections: builtSections)
    XCTAssertEqual(hidden.sections.map(\.id), ["creatures"])

    let shown = makeSnapshot(entries: entries, builtSections: builtSections, showsMultiCategoryCards: true)
    XCTAssertEqual(shown.sections.map(\.id), ["creatures", "walkers"])
    XCTAssertEqual(shown.sections[1].displayedEntries(showingGhosts: true).map(\.id), ["bear"])
  }

  func testCategoryWithNoCardsAtAllIsHiddenButReappearsWhileDragging() {
    let categories = [
      category(id: "creatures", name: "Creatures", position: 0),
      category(id: "empty", name: "Artifacts", position: 1),
    ]
    let entries = [entry(id: "bear", categoryID: "creatures", position: 0)]
    let builtSections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

    let resting = makeSnapshot(entries: entries, builtSections: builtSections)
    XCTAssertEqual(resting.sections.map(\.id), ["creatures"])

    // An empty category is only reachable by drag while a drag is in flight, so it comes back.
    let dragging = makeSnapshot(entries: entries, builtSections: builtSections, revealsShadowedCategories: true)
    XCTAssertEqual(dragging.sections.map(\.id), ["creatures", "empty"])

    // Turning ghosts on doesn't resurrect a category that has no ghosts either.
    let ghosting = makeSnapshot(entries: entries, builtSections: builtSections, showsMultiCategoryCards: true)
    XCTAssertEqual(ghosting.sections.map(\.id), ["creatures"])
  }

  func testGhostsAreExcludedFromExpandedEntriesAndSectionCounts() {
    let categories = [
      category(id: "creatures", name: "Creatures", position: 0),
      category(id: "walkers", name: "Planeswalkers", position: 1),
    ]
    let entries = [
      entry(id: "bear", categoryID: "creatures", secondaryCategoryIDs: ["walkers"], position: 0),
      entry(id: "jace", categoryID: "walkers", position: 1),
    ]
    let builtSections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

    let snapshot = makeSnapshot(entries: entries, builtSections: builtSections, showsMultiCategoryCards: true)

    // "bear" is drawn twice, but it is one card: it appears once in the expanded set (which
    // drives selection and image prefetch) and doesn't inflate the Planeswalkers count.
    XCTAssertEqual(snapshot.expandedEntryIDs, ["bear", "jace"])
    XCTAssertEqual(snapshot.sections[1].entryCountText, "1 card")
    XCTAssertEqual(snapshot.sections[1].displayedEntries(showingGhosts: true).map(\.id), ["jace", "bear"])
  }

  func testSectionHeaderNamesTheGhostsItDrawsBeyondItsOwnCards() {
    let categories = [
      category(id: "creatures", name: "Creatures", position: 0),
      category(id: "walkers", name: "Planeswalkers", position: 1),
    ]
    let entries = [
      entry(id: "bear", categoryID: "creatures", secondaryCategoryIDs: ["walkers"], position: 0),
      entry(id: "jace", categoryID: "walkers", position: 1),
    ]

    let sections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: categories)

    XCTAssertEqual(sections[1].entryCountText(showingGhosts: false), "1 card")
    XCTAssertEqual(sections[1].entryCountText(showingGhosts: true), "1 card · 1 tagged")
    // A section with no ghosts reads the same either way.
    XCTAssertEqual(sections[0].entryCountText(showingGhosts: true), "1 card")
  }

  func testUncategorizedSectionIsNeverShadowed() {
    let entries = [entry(id: "loose", categoryID: nil, position: 0)]
    let builtSections = CardCollectionEntrySectionBuilder.sections(entries: entries, categories: [])

    let snapshot = makeSnapshot(entries: entries, builtSections: builtSections)

    XCTAssertEqual(snapshot.sections.map(\.id), ["mainboard-uncategorized"])
  }

  func testGhostsSortAlongsideTheirSectionsSortMode() {
    let categories = [
      category(id: "creatures", name: "Creatures", position: 0),
      category(id: "walkers", name: "Planeswalkers", position: 1),
    ]
    let entries = [
      entry(
        id: "high",
        categoryID: "creatures",
        secondaryCategoryIDs: ["walkers"],
        position: 0,
        card: card(id: "high", edhrecRank: 40)
      ),
      entry(
        id: "low",
        categoryID: "creatures",
        secondaryCategoryIDs: ["walkers"],
        position: 1,
        card: card(id: "low", edhrecRank: 5)
      ),
    ]

    let sections = CardCollectionEntrySectionBuilder.sections(
      entries: entries,
      categories: categories,
      displaySortMode: .edhrecRank,
      displaySortDirection: .ascending
    )

    XCTAssertEqual(sections[1].ghostEntries.map(\.id), ["low", "high"])
  }

  private func makeSnapshot(
    entries: [CardCollectionEntryRecord],
    builtSections: [CardCollectionEntrySection],
    showsMultiCategoryCards: Bool = false,
    revealsShadowedCategories: Bool = false
  ) -> CardCollectionDetailSnapshot {
    CardCollectionDetailSnapshot(
      visibleEntries: entries,
      builtSections: builtSections,
      collapsedSectionIDs: [],
      isSearchActive: false,
      totalEntryCount: entries.count,
      showsMultiCategoryCards: showsMultiCategoryCards,
      revealsShadowedCategories: revealsShadowedCategories
    )
  }

  private func category(
    id: CardCollectionCategoryRecord.ID,
    name: String,
    position: Int,
    zone: CardCollectionZone = .mainboard
  ) -> CardCollectionCategoryRecord {
    CardCollectionCategoryRecord(
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
    id: CardCollectionEntryRecord.ID,
    categoryID: CardCollectionCategoryRecord.ID?,
    secondaryCategoryIDs: [CardCollectionCategoryRecord.ID] = [],
    position: Int,
    zone: CardCollectionZone = .mainboard,
    card: CardRecord? = nil
  ) -> CardCollectionEntryRecord {
    CardCollectionEntryRecord(
      id: id,
      listID: "list",
      zone: zone,
      categoryID: categoryID,
      secondaryCategoryIDs: secondaryCategoryIDs,
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
