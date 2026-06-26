import Foundation
import GrimoraCore

extension GrimoraAppModel {
  func addCardID(_ cardID: CardRecord.ID, named cardName: String?, toListID listID: CardCollectionRecord.ID) {
    do {
      let resolvedCard = try database.card(id: cardID)
      guard resolvedCard != nil else {
        statusMessage = "That card is no longer in the local library."
        return
      }

      try performListMutation {
        try database.appendCard(cardID, toList: listID)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      if let list = cardCollections.first(where: { $0.id == listID }) {
        let name = cardName ?? resolvedCard?.name ?? "Card"
        statusMessage = "Added \(name) to \(list.name)."
      }
    } catch {
      statusMessage = "Collection update failed."
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
    intoListID listID: CardCollectionRecord.ID,
    fallbackListName: String,
    sourceName: String?
  ) throws -> CardCollectionImportSummary {
    guard let list = try database.cardCollection(id: listID) else {
      throw CardCollectionDatabaseError.listNotFound
    }

    var categoriesByName = try database.cardCollectionCategories(forListID: listID)
      .reduce(into: [ArchidektImportCategoryKey: CardCollectionCategoryRecord]()) { result, category in
        result[ArchidektImportCategoryKey(zone: category.zone, nameKey: Self.normalizedCategoryKey(category.name))] = category
      }
    var usedCategoryKeys = Set<ArchidektImportCategoryKey>()
    var skippedLines = importDeck.skippedLines.map {
      CardCollectionImportSkippedLine(lineNumber: $0.lineNumber, text: $0.text, reason: $0.reason)
    }
    var importedEntryCount = 0

    for reference in importDeck.cards {
      guard let cardID = try resolvedCardID(for: reference) else {
        skippedLines.append(
          CardCollectionImportSkippedLine(
            text: reference.sourceDescription,
            reason: "No matching local print was found."
          ))
        continue
      }

      let destination = Self.archidektImportDestination(
        for: reference.categories,
        ruleset: list.ruleset
      )
      let categoryID: CardCollectionCategoryRecord.ID?
      if let categoryName = destination.categoryName {
        let categoryKey = Self.normalizedCategoryKey(categoryName)
        let importCategoryKey = ArchidektImportCategoryKey(
          zone: destination.zone,
          nameKey: categoryKey
        )
        if let existingCategory = categoriesByName[importCategoryKey] {
          categoryID = existingCategory.id
        } else {
          let createdCategory = try database.createCardCollectionCategory(
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

      reloadCardCollections(selecting: listID, activatingSelection: true)
    let listName = cardCollections.first { $0.id == listID }?.name ?? fallbackListName
    let summary = CardCollectionImportSummary(
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

  func importStatusMessage(for summary: CardCollectionImportSummary) -> String {
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
    pauseCloudSyncMonitoringForLocalMutation()
    defer { resumeCloudSyncMonitoringAfterLocalMutation() }
    let undoState = try CardCollectionUndoState(
      snapshot: database.cardCollectionLibrarySnapshot(),
      sidebarSelection: sidebarSelection,
      selectedCollectionID: selectedCollectionID
    )
    let result = try body()
    pushListUndoState(undoState)
    try? database.recordLocalSyncSnapshotChange(reason: "list-mutation")
    pushCloudSyncChangesIfNeeded()
    return result
  }

  func pushListUndoState(_ state: CardCollectionUndoState) {
    listUndoStack.append(state)
    if listUndoStack.count > Self.maximumListUndoDepth {
      listUndoStack.removeFirst(listUndoStack.count - Self.maximumListUndoDepth)
    }
    canUndoListAction = true
  }

  func restoredListSelection(from state: CardCollectionUndoState)
    -> (selectedCollectionID: CardCollectionRecord.ID?, sidebarSelection: GrimoraSidebarSelection, activatesSelection: Bool)
  {
    switch state.sidebarSelection {
    case .list(let listID) where state.snapshot.lists.contains(where: { $0.id == listID }):
      return (listID, .list(listID), true)
    case .listsOverview:
      return (nil, .listsOverview, false)
    case .newList:
      return (nil, .newList, false)
    case .search, .list:
      return (state.selectedCollectionID, .search, false)
    }
  }

  @discardableResult
  func ensureFavouritesList() throws -> CardCollectionRecord {
    let lists = try database.cardCollections()
    if let favourites = lists.first(where: { Self.isCanonicalFavouritesListName($0.name) }) {
      return favourites
    }

    if let alias = lists.first(where: { Self.isFavouritesListName($0.name) }) {
      return try database.renameCardCollection(id: alias.id, to: Self.favouritesListName)
    }

    return try database.createCardCollection(named: Self.favouritesListName)
  }

  func orderedCardCollectionsForDisplay(_ lists: [CardCollectionRecord]) -> [CardCollectionRecord] {
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
      + sortedCardCollections(userLists.filter(\.isPinned))
      + sortedCardCollections(userLists.filter { !$0.isPinned })
  }

  func refreshListOverviewItems() {
    cardCollectionOverviewItems = cardCollections.map { list in
      let topEntry = topOverviewEntry(for: list)
      return CardCollectionOverviewItem(
        list: list,
        topEntry: topEntry,
        topCard: topEntry?.card
      )
    }
    reloadDashboardSearch()
  }

  private func topOverviewEntry(for list: CardCollectionRecord) -> CardCollectionEntryRecord? {
    do {
      let entries = try database.cardCollectionEntries(forListID: list.id)
      let categories = try database.cardCollectionCategories(forListID: list.id)
      return CardCollectionEntrySectionBuilder.sections(
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

  func reloadCardCollections(
    selecting requestedSelection: CardCollectionRecord.ID? = nil,
    activatingSelection: Bool = false
  ) {
    do {
      try ensureFavouritesList()
      let lists = orderedCardCollectionsForDisplay(try database.cardCollections())
      cardCollections = lists
      refreshFavouriteCardIDs()
      if let requestedSelection,
        lists.contains(where: { $0.id == requestedSelection })
      {
        selectedCollectionID = requestedSelection
      } else if let selectedCollectionID, lists.contains(where: { $0.id == selectedCollectionID }) {
        self.selectedCollectionID = selectedCollectionID
      } else {
        selectedCollectionID = nil
      }
      reconcileSidebarSelection(availableLists: lists, activatingSelection: activatingSelection)
      loadSelectedListState()
    } catch {
      cardCollections = []
      cardCollectionOverviewItems = []
      selectedCollectionID = nil
      selectedCollectionCategories = []
      selectedCollectionEntries = []
      selectedCollectionRulesetWarnings = []
      resetSelectedListSearchResults()
      sidebarSelection = .search
      favouriteCardIDs = []
    }
  }

  /// Re-derives the per-list card counts (and favourite card IDs) from the database without
  /// disturbing the current selection, loaded entries, search results, or image trackers.
  ///
  /// The sidebar shows counts for every list but only keeps the selected list's entries in
  /// memory, so it relies on the denormalized `CardCollectionRecord.entryCount`. That cache can go
  /// stale relative to the entries table when an out-of-band write (e.g. a cloud-sync apply
  /// whose follow-up reload was skipped) lands without a full `reloadCardCollections()`. This is a
  /// cheap, idempotent re-sync (one grouped `SUM` query) used to self-heal those counts.
  func refreshCardCollectionCounts() {
    guard let lists = try? database.cardCollections() else {
      return
    }
    cardCollections = orderedCardCollectionsForDisplay(lists)
    refreshFavouriteCardIDs()
    refreshListOverviewItems()
  }

  func refreshFavouriteCardIDs() {
    guard let favouritesList else {
      favouriteCardIDs = []
      return
    }

    do {
      favouriteCardIDs = Set(
        try database.cardCollectionEntries(forListID: favouritesList.id).map(\.cardID)
      )
    } catch {
      favouriteCardIDs = []
    }
  }

  func reconcileSidebarSelection(
    availableLists: [CardCollectionRecord],
    activatingSelection: Bool
  ) {
    if activatingSelection, let selectedCollectionID {
      sidebarSelection = .list(selectedCollectionID)
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
    guard let selectedCollectionID else {
      selectedCollectionCategories = []
      selectedCollectionEntries = []
      selectedCollectionRulesetWarnings = []
      resetSelectedListSearchResults()
      refreshListOverviewItems()
      return
    }

    do {
      selectedCollectionCategories = try database.cardCollectionCategories(forListID: selectedCollectionID)
      selectedCollectionEntries = try database.cardCollectionEntries(forListID: selectedCollectionID)
      if let selectedCollection {
        selectedCollectionRulesetWarnings = CardCollectionRulesetValidator.warnings(
          for: selectedCollection,
          entries: selectedCollectionEntries
        )
      } else {
        selectedCollectionRulesetWarnings = []
      }
      reloadSelectedListSearch()
      refreshListOverviewItems()
    } catch {
      selectedCollectionCategories = []
      selectedCollectionEntries = []
      selectedCollectionRulesetWarnings = []
      resetSelectedListSearchResults()
      refreshListOverviewItems()
      statusMessage = "Collection update failed."
    }
  }

  static func archidektImportDestination(
    for categories: [String],
    ruleset: CardCollectionRuleset
  ) -> ArchidektImportDestination {
    var zone = CardCollectionZone.mainboard
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
  var zone: CardCollectionZone
  var categoryName: String?
}

private struct ArchidektImportCategoryKey: Hashable {
  var zone: CardCollectionZone
  var nameKey: String
}
