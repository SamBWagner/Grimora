import Foundation
import GrimoraCore

extension GrimoraAppModel {
  func addCardID(_ cardID: CardRecord.ID, named cardName: String?, toListID listID: CardListRecord.ID) {
    do {
      let resolvedCard = try database.card(id: cardID)
      guard resolvedCard != nil else {
        statusMessage = "That card is no longer in the local library."
        return
      }

      try performListMutation {
        try database.appendCard(cardID, toList: listID)
      }
      reloadCardLists(selecting: selectedListID)
      if let list = cardLists.first(where: { $0.id == listID }) {
        let name = cardName ?? resolvedCard?.name ?? "Card"
        statusMessage = "Added \(name) to \(list.name)."
      }
    } catch {
      statusMessage = "List update failed."
    }
  }

  func archidektImportDeck(from source: String) async throws -> ArchidektDeckImport {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if ArchidektListParser.deckID(from: trimmed) != nil {
      return try await archidektDeckClient.fetchDeck(from: trimmed)
    }

    return ArchidektListParser.parse(trimmed)
  }

  func importArchidektDeck(
    _ importDeck: ArchidektDeckImport,
    intoListID listID: CardListRecord.ID,
    fallbackListName: String,
    sourceName: String?
  ) throws -> CardListImportSummary {
    guard let list = try database.cardList(id: listID) else {
      throw CardListDatabaseError.listNotFound
    }

    var categoriesByName = try database.cardListCategories(forListID: listID)
      .reduce(into: [ArchidektImportCategoryKey: CardListCategoryRecord]()) { result, category in
        result[ArchidektImportCategoryKey(zone: category.zone, nameKey: Self.normalizedCategoryKey(category.name))] = category
      }
    var usedCategoryKeys = Set<ArchidektImportCategoryKey>()
    var skippedLines = importDeck.skippedLines.map {
      CardListImportSkippedLine(lineNumber: $0.lineNumber, text: $0.text, reason: $0.reason)
    }
    var importedEntryCount = 0

    for reference in importDeck.cards {
      guard let cardID = try resolvedCardID(for: reference) else {
        skippedLines.append(
          CardListImportSkippedLine(
            text: reference.sourceDescription,
            reason: "No matching local print was found."
          ))
        continue
      }

      let destination = Self.archidektImportDestination(
        for: reference.categories,
        ruleset: list.ruleset
      )
      let categoryID: CardListCategoryRecord.ID?
      if let categoryName = destination.categoryName {
        let categoryKey = Self.normalizedCategoryKey(categoryName)
        let importCategoryKey = ArchidektImportCategoryKey(
          zone: destination.zone,
          nameKey: categoryKey
        )
        if let existingCategory = categoriesByName[importCategoryKey] {
          categoryID = existingCategory.id
        } else {
          let createdCategory = try database.createCardListCategory(
            inList: listID,
            zone: destination.zone,
            named: categoryName
          )
          categoriesByName[importCategoryKey] = createdCategory
          categoryID = createdCategory.id
        }
        usedCategoryKeys.insert(importCategoryKey)
      } else {
        categoryID = nil
      }

      try database.appendCard(
        cardID,
        toList: listID,
        zone: destination.zone,
        categoryID: categoryID,
        quantity: reference.quantity
      )
      importedEntryCount += reference.quantity
    }

      reloadCardLists(selecting: listID, activatingSelection: true)
    let listName = cardLists.first { $0.id == listID }?.name ?? fallbackListName
    let summary = CardListImportSummary(
      listName: listName,
      cardCount: importedEntryCount,
      categoryCount: usedCategoryKeys.count,
      missingCardIDs: [],
      sourceName: sourceName,
      skippedLines: skippedLines
    )
    statusMessage = importStatusMessage(for: summary)
    return summary
  }

  func resolvedCardID(for reference: ArchidektCardReference) throws -> CardRecord.ID? {
    if let scryfallID = reference.scryfallID,
      let card = try database.card(id: scryfallID)
    {
      return card.id
    }

    if let setCode = reference.setCode,
      let collectorNumber = reference.collectorNumber,
      let card = try database.card(setCode: setCode, collectorNumber: collectorNumber)
    {
      return card.id
    }

    return nil
  }

  func importStatusMessage(for summary: CardListImportSummary) -> String {
    let skippedSuffix = summary.skippedLines.isEmpty
      ? ""
      : " \(summary.skippedLines.count) skipped."
    if summary.cardCount == 0 {
      return "No importable cards found.\(skippedSuffix)"
    }

    let noun = summary.cardCount == 1 ? "card" : "cards"
    return "Imported \(formatted(summary.cardCount)) \(noun) into \(summary.listName).\(skippedSuffix)"
  }

  @discardableResult
  func performListMutation<T>(_ body: () throws -> T) throws -> T {
    let undoState = try CardListUndoState(
      snapshot: database.cardListLibrarySnapshot(),
      sidebarSelection: sidebarSelection,
      selectedListID: selectedListID
    )
    let result = try body()
    pushListUndoState(undoState)
    try? database.recordLocalSyncSnapshotChange(reason: "list-mutation")
    pushCloudSyncChangesIfNeeded()
    return result
  }

  func pushListUndoState(_ state: CardListUndoState) {
    listUndoStack.append(state)
    if listUndoStack.count > Self.maximumListUndoDepth {
      listUndoStack.removeFirst(listUndoStack.count - Self.maximumListUndoDepth)
    }
    canUndoListAction = true
  }

  func restoredListSelection(from state: CardListUndoState)
    -> (selectedListID: CardListRecord.ID?, sidebarSelection: GrimoraSidebarSelection, activatesSelection: Bool)
  {
    switch state.sidebarSelection {
    case .list(let listID) where state.snapshot.lists.contains(where: { $0.id == listID }):
      return (listID, .list(listID), true)
    case .listsOverview:
      return (nil, .listsOverview, false)
    case .newList:
      return (nil, .newList, false)
    case .search, .list:
      return (state.selectedListID, .search, false)
    }
  }

  @discardableResult
  func ensureFavouritesList() throws -> CardListRecord {
    let lists = try database.cardLists()
    if let favourites = lists.first(where: { Self.isCanonicalFavouritesListName($0.name) }) {
      return favourites
    }

    if let alias = lists.first(where: { Self.isFavouritesListName($0.name) }) {
      return try database.renameCardList(id: alias.id, to: Self.favouritesListName)
    }

    return try database.createCardList(named: Self.favouritesListName)
  }

  func orderedCardListsForDisplay(_ lists: [CardListRecord]) -> [CardListRecord] {
    let favouritesLists = lists
      .filter { Self.isFavouritesListName($0.name) }
      .sorted { lhs, rhs in
        let lhsCanonical = Self.isCanonicalFavouritesListName(lhs.name)
        let rhsCanonical = Self.isCanonicalFavouritesListName(rhs.name)
        if lhsCanonical != rhsCanonical {
          return lhsCanonical
        }
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
      }

    let userLists = lists.filter { !Self.isFavouritesListName($0.name) }
    return favouritesLists
      + sortedCardLists(userLists.filter(\.isPinned))
      + sortedCardLists(userLists.filter { !$0.isPinned })
  }

  func refreshListOverviewItems() {
    cardListOverviewItems = cardLists.map { list in
      let topEntry = topOverviewEntry(for: list)
      return CardListOverviewItem(
        list: list,
        topEntry: topEntry,
        topCard: topEntry?.card
      )
    }
  }

  private func topOverviewEntry(for list: CardListRecord) -> CardListEntryRecord? {
    do {
      let entries = try database.cardListEntries(forListID: list.id)
      let categories = try database.cardListCategories(forListID: list.id)
      return CardListEntrySectionBuilder.sections(
        entries: entries,
        categories: categories,
        ruleset: list.ruleset,
        displaySortMode: list.displaySortMode,
        displaySortDirection: list.displaySortDirection
      )
      .flatMap(\.entries)
      .first
    } catch {
      return nil
    }
  }

  func reloadCardLists(
    selecting requestedSelection: CardListRecord.ID? = nil,
    activatingSelection: Bool = false
  ) {
    do {
      try ensureFavouritesList()
      let lists = orderedCardListsForDisplay(try database.cardLists())
      cardLists = lists
      if let requestedSelection,
        lists.contains(where: { $0.id == requestedSelection })
      {
        selectedListID = requestedSelection
      } else if let selectedListID, lists.contains(where: { $0.id == selectedListID }) {
        self.selectedListID = selectedListID
      } else {
        selectedListID = nil
      }
      reconcileSidebarSelection(availableLists: lists, activatingSelection: activatingSelection)
      loadSelectedListState()
    } catch {
      cardLists = []
      cardListOverviewItems = []
      selectedListID = nil
      selectedListCategories = []
      selectedListEntries = []
      selectedListRulesetWarnings = []
      resetSelectedListSearchResults()
      sidebarSelection = .search
    }
  }

  func reconcileSidebarSelection(
    availableLists: [CardListRecord],
    activatingSelection: Bool
  ) {
    if activatingSelection, let selectedListID {
      sidebarSelection = .list(selectedListID)
      return
    }

    if case .list(let listID) = sidebarSelection,
      !availableLists.contains(where: { $0.id == listID })
    {
      sidebarSelection = .listsOverview
    }
  }

  func loadSelectedListState() {
    listVisibleImageWindowTracker.reset()
    resetListVisibleImageRequests()
    guard let selectedListID else {
      selectedListCategories = []
      selectedListEntries = []
      selectedListRulesetWarnings = []
      resetSelectedListSearchResults()
      refreshListOverviewItems()
      return
    }

    do {
      selectedListCategories = try database.cardListCategories(forListID: selectedListID)
      selectedListEntries = try database.cardListEntries(forListID: selectedListID)
      if let selectedList {
        selectedListRulesetWarnings = CardListRulesetValidator.warnings(
          for: selectedList,
          entries: selectedListEntries
        )
      } else {
        selectedListRulesetWarnings = []
      }
      reloadSelectedListSearch()
      refreshListOverviewItems()
    } catch {
      selectedListCategories = []
      selectedListEntries = []
      selectedListRulesetWarnings = []
      resetSelectedListSearchResults()
      refreshListOverviewItems()
      statusMessage = "List update failed."
    }
  }

  static func archidektImportDestination(
    for categories: [String],
    ruleset: CardListRuleset
  ) -> ArchidektImportDestination {
    var zone = CardListZone.mainboard
    var regularCategoryName: String?

    for category in categories {
      let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedCategory.isEmpty else {
        continue
      }

      switch normalizedCategoryKey(trimmedCategory) {
      case "commander":
        zone = .commander
      case "mainboard":
        zone = .mainboard
      case "sideboard":
        zone = .sideboard
      case "maybeboard":
        zone = .maybeboard
      default:
        if regularCategoryName == nil {
          regularCategoryName = trimmedCategory
        }
      }
    }

    return ArchidektImportDestination(
      zone: ruleset.normalizedZone(zone),
      categoryName: regularCategoryName
    )
  }
}

struct ArchidektImportDestination: Equatable {
  var zone: CardListZone
  var categoryName: String?
}

private struct ArchidektImportCategoryKey: Hashable {
  var zone: CardListZone
  var nameKey: String
}
