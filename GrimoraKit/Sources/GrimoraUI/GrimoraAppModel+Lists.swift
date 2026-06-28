import Foundation
import GrimoraCore

extension GrimoraAppModel {
  public static let favouritesListName = "Favourites"

  public static func isCanonicalFavouritesListName(_ name: String) -> Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(favouritesListName)
      == .orderedSame
  }

  public static func isFavouritesListName(_ name: String) -> Bool {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedName == "favourites" || normalizedName == "favorites"
  }

  public func isFavouritesList(_ list: CardCollectionRecord) -> Bool {
    Self.isFavouritesListName(list.name)
  }

  public func isProtectedFavouritesList(_ list: CardCollectionRecord) -> Bool {
    Self.isFavouritesListName(list.name)
  }

  public func selectListsOverview() {
    cancelSelectedListLoad()
    selectedCollectionID = nil
    selectedCollectionCategories = []
    selectedCollectionEntries = []
    selectedCollectionRulesetWarnings = []
    resetSelectedListSearchResults()
    listLoadPhase = .idle
    sidebarSelection = .listsOverview
    closeSelectedCard()
  }

  public func selectSearch() {
    cancelSelectedListLoad()
    sidebarSelection = .search
    closeSelectedCard()
  }

  public func selectNewList() {
    sidebarSelection = .newList
    closeSelectedCard()
  }

  public func cancelNewListCreation(returningTo previousSelection: GrimoraSidebarSelection?) {
    switch previousSelection {
    case .list(let id) where cardCollections.contains(where: { $0.id == id }):
      selectCardCollection(id: id)
    case .listsOverview:
      selectListsOverview()
    case .list, .search, .newList, nil:
      selectSearch()
    }
  }

  public func selectCardCollection(id: CardCollectionRecord.ID) {
    guard cardCollections.contains(where: { $0.id == id }) else {
      if selectedCollectionID == id {
        cancelSelectedListLoad()
        selectedCollectionID = nil
        selectedCollectionCategories = []
        selectedCollectionEntries = []
        selectedCollectionRulesetWarnings = []
        resetSelectedListSearchResults()
        listLoadPhase = .idle
      }
      if sidebarSelection == .list(id) {
        sidebarSelection = .search
      }
      return
    }

    selectedCollectionID = id
    sidebarSelection = .list(id)
    closeSelectedCard()
    beginLoadingSelectedListState()
  }

  public func closeSelectedList() {
    cancelSelectedListLoad()
    selectedCollectionID = nil
    selectedCollectionCategories = []
    selectedCollectionEntries = []
    selectedCollectionRulesetWarnings = []
    resetSelectedListSearchResults()
    listLoadPhase = .idle
    sidebarSelection = .listsOverview
    closeSelectedCard()
  }

  public func setSelectedListSearchDraft(_ text: String) {
    guard selectedCollectionSearchText != text else {
      return
    }

    selectedCollectionSearchText = text
    reloadSelectedListSearch()
  }

  public func clearSelectedListSearch() {
    setSelectedListSearchDraft("")
  }

  func reloadSelectedListSearch() {
    let query = GrimoraSearchHistoryStore.normalizedQuery(selectedCollectionSearchText)
    selectedCollectionSearchUnsupportedMessage = nil
    guard let selectedCollectionID, !query.isEmpty else {
      searchedSelectedListEntries = nil
      return
    }

    do {
      switch try database.searchCardCollectionEntries(forListID: selectedCollectionID, text: query) {
      case .results(let entries):
        searchedSelectedListEntries = entries
      case .unsupported(let reason):
        searchedSelectedListEntries = []
        selectedCollectionSearchUnsupportedMessage = reason.message
      }
    } catch {
      searchedSelectedListEntries = []
      statusMessage = "Collection search failed."
    }
  }

  func resetSelectedListSearchResults() {
    searchedSelectedListEntries = nil
    selectedCollectionSearchUnsupportedMessage = nil
  }

  /// Runs a Scryfall query across every list, returning the lists whose cards match together with
  /// the matching entries. The query is compiled once in the database layer. An empty query yields
  /// no matches so the dashboard can treat it as "show everything".
  public func searchAllLists(query: String) -> CrossListSearchResponse {
    let normalizedQuery = GrimoraSearchHistoryStore.normalizedQuery(query)
    guard !normalizedQuery.isEmpty else {
      return .results([])
    }

    do {
      return try database.searchAllCardCollectionEntries(text: normalizedQuery)
    } catch {
      statusMessage = "Collection search failed."
      return .results([])
    }
  }

  /// Whether the dashboard is currently filtering its tiles by a cross-list search query.
  public var hasActiveDashboardSearch: Bool {
    !GrimoraSearchHistoryStore.normalizedQuery(dashboardSearchText).isEmpty
  }

  /// The dashboard overview items narrowed to the lists matching the active cross-list search.
  /// Returns every item when no filter is active (or when the query can't be compiled).
  public var filteredCardCollectionOverviewItems: [CardCollectionOverviewItem] {
    guard let dashboardListMatchIDs else {
      return cardCollectionOverviewItems
    }
    return cardCollectionOverviewItems.filter { dashboardListMatchIDs.contains($0.list.id) }
  }

  public func setDashboardSearchDraft(_ text: String) {
    guard dashboardSearchText != text else {
      return
    }

    dashboardSearchText = text
    reloadDashboardSearch()
  }

  public func clearDashboardSearch() {
    setDashboardSearchDraft("")
  }

  /// Recomputes which lists match the dashboard cross-list query. A `nil` match set means "no
  /// filter" (show every tile); an empty set means the query was valid but matched nothing.
  func reloadDashboardSearch() {
    let query = GrimoraSearchHistoryStore.normalizedQuery(dashboardSearchText)
    dashboardSearchUnsupportedMessage = nil
    guard !query.isEmpty else {
      dashboardListMatchIDs = nil
      dashboardListMatches = [:]
      return
    }

    switch searchAllLists(query: query) {
    case .results(let matches):
      dashboardListMatchIDs = Set(matches.map(\.listID))
      dashboardListMatches = Dictionary(uniqueKeysWithValues: matches.map { ($0.listID, $0) })
    case .unsupported(let reason):
      dashboardListMatchIDs = nil
      dashboardListMatches = [:]
      dashboardSearchUnsupportedMessage = reason.message
    }
  }

  public func undoLastListAction() {
    guard let undoState = listUndoStack.popLast() else {
      canUndoListAction = false
      return
    }

    do {
      try database.restoreCardCollectionLibrarySnapshot(undoState.snapshot)
      try? database.recordLocalSyncSnapshotChange(reason: "undo-list-action")
      canUndoListAction = !listUndoStack.isEmpty
      let restoredSelection = restoredListSelection(from: undoState)
      reloadCardCollections(
        selecting: restoredSelection.selectedCollectionID,
        activatingSelection: restoredSelection.activatesSelection
      )
      sidebarSelection = restoredSelection.sidebarSelection
      if case .list(let listID) = sidebarSelection {
        selectedCollectionID = listID
        loadSelectedListState()
      } else if sidebarSelection != .list(selectedCollectionID ?? "") {
        selectedCollectionID = nil
        selectedCollectionCategories = []
        selectedCollectionEntries = []
        selectedCollectionRulesetWarnings = []
        resetSelectedListSearchResults()
      }
      statusMessage = "Undid collection action."
      pushCloudSyncChangesIfNeeded()
    } catch {
      canUndoListAction = !listUndoStack.isEmpty
      statusMessage = "Undo failed."
    }
  }

  @discardableResult
  public func createCardCollection(
    named name: String,
    adding card: CardRecord? = nil,
    selectAfterCreate: Bool = false
  ) -> CardCollectionRecord? {
    if Self.isFavouritesListName(name) {
      return useFavouritesList(
        adding: card.map { [$0.id] } ?? [],
        primaryCard: card,
        selectAfterCreate: selectAfterCreate
      )
    }

    do {
      let list = try performListMutation {
        let list = try database.createCardCollection(named: name)
        if let card {
          try database.appendCard(card.id, toList: list.id)
        }
        return list
      }
      reloadCardCollections(
        selecting: selectAfterCreate ? list.id : selectedCollectionID,
        activatingSelection: selectAfterCreate
      )
      statusMessage = card.map { "Added \($0.name) to \(list.name)." } ?? "Created \(list.name)."
      return cardCollections.first { $0.id == list.id } ?? list
    } catch CardCollectionDatabaseError.emptyName {
      return nil
    } catch {
      statusMessage = "Collection update failed."
      return nil
    }
  }

  @discardableResult
  public func createCardCollection(
    named name: String,
    addingCardIDs cardIDs: [CardRecord.ID],
    selectAfterCreate: Bool = false
  ) -> CardCollectionRecord? {
    if Self.isFavouritesListName(name) {
      return useFavouritesList(
        adding: cardIDs,
        primaryCard: nil,
        selectAfterCreate: selectAfterCreate
      )
    }

    let requestedCardIDs = cardIDs
    do {
      let list = try performListMutation {
        let list = try database.createCardCollection(named: name)
        for cardID in requestedCardIDs {
          try database.appendCard(cardID, toList: list.id)
        }
        return list
      }
      reloadCardCollections(
        selecting: selectAfterCreate ? list.id : selectedCollectionID,
        activatingSelection: selectAfterCreate
      )
      if requestedCardIDs.isEmpty {
        statusMessage = "Created \(list.name)."
      } else {
        let noun = requestedCardIDs.count == 1 ? "card" : "cards"
        statusMessage = "Created \(list.name) with \(formatted(requestedCardIDs.count)) \(noun)."
      }
      return cardCollections.first { $0.id == list.id } ?? list
    } catch CardCollectionDatabaseError.emptyName {
      return nil
    } catch {
      statusMessage = "Collection update failed."
      return nil
    }
  }

  @discardableResult
  public func createCardCollectionFromCurrentSearch(named name: String) async -> CardCollectionRecord? {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      return nil
    }
    guard hasLibrary,
      unsupportedSearchMessage == nil,
      searchResultTotal > 0,
      !isSearchingCards,
      !isLoadingMoreCards,
      !isCreatingListFromSearch
    else {
      statusMessage = "No search results to add."
      return nil
    }

    let generation = searchGeneration
    let totalCount = searchResultTotal
    let database = database
    let resolvedSearch = resolvedSearchConfiguration()
    let request = CardSearchRequest(
      text: resolvedSearch.text,
      sortMode: resolvedSearch.sortMode,
      sortDirection: resolvedSearch.sortDirection,
      printingDisplayMode: printingDisplayMode,
      limit: totalCount
    )
    let undoState: CardCollectionUndoState
    do {
      undoState = try CardCollectionUndoState(
        snapshot: database.cardCollectionLibrarySnapshot(),
        sidebarSelection: sidebarSelection,
        selectedCollectionID: selectedCollectionID
      )
    } catch {
      statusMessage = "Collection update failed."
      return nil
    }

    isCreatingListFromSearch = true
    defer { isCreatingListFromSearch = false }

    let result = await Task.detached(priority: .userInitiated) {
      do {
        switch try database.search(request) {
        case .results(let cards, _):
          guard !cards.isEmpty else {
            return SearchListCreationResult.empty
          }
          let list = try database.createCardCollection(named: normalizedName)
          for card in cards {
            try database.appendCard(card.id, toList: list.id)
          }
          return SearchListCreationResult.success(listID: list.id, cardCount: cards.count)
        case .unsupported:
          return SearchListCreationResult.unsupported
        }
      } catch CardCollectionDatabaseError.emptyName {
        return SearchListCreationResult.emptyName
      } catch {
        return SearchListCreationResult.failure
      }
    }.value

    guard generation == searchGeneration else {
      statusMessage = "Search changed before the collection could be created."
      return nil
    }

    switch result {
    case .success(let listID, let cardCount):
      pushListUndoState(undoState)
      try? database.recordLocalSyncSnapshotChange(reason: "search-list-created")
      reloadCardCollections(selecting: listID, activatingSelection: true)
      pushCloudSyncChangesIfNeeded()
      guard let list = selectedCollection else {
        statusMessage = "Collection update failed."
        return nil
      }
      let noun = cardCount == 1 ? "card" : "cards"
      statusMessage = "Created \(list.name) with \(formatted(cardCount)) \(noun)."
      return list
    case .empty, .unsupported:
      statusMessage = "No search results to add."
      return nil
    case .emptyName:
      return nil
    case .failure:
      statusMessage = "Collection update failed."
      return nil
    }
  }

  public func renameCardCollection(id: CardCollectionRecord.ID, to name: String) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) is managed by Grimora."
      return
    }

    do {
      let list = try performListMutation {
        try database.renameCardCollection(id: id, to: name)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Renamed collection to \(list.name)."
    } catch CardCollectionDatabaseError.emptyName {
      return
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func setCardCollectionPinned(
    id: CardCollectionRecord.ID,
    isPinned: Bool,
    now: Date = Date()
  ) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) stays at the top."
      return
    }

    do {
      let list = try performListMutation {
        try database.setCardCollectionPinned(id: id, isPinned: isPinned, now: now)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = isPinned ? "Pinned \(list.name)." : "Unpinned \(list.name)."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func moveCardCollection(id: CardCollectionRecord.ID, by offset: Int) {
    guard let list = cardCollections.first(where: { $0.id == id }) else {
      return
    }
    guard !isProtectedFavouritesList(list) else {
      statusMessage = "\(Self.favouritesListName) stays at the top."
      return
    }
    let sectionLists = list.isPinned ? pinnedCardCollections : unpinnedCardCollections
    guard let index = sectionLists.firstIndex(where: { $0.id == id }) else {
      return
    }

    moveCardCollection(id: id, toPosition: index + offset, isPinned: list.isPinned)
  }

  public func moveCardCollection(
    id: CardCollectionRecord.ID,
    toPosition position: Int,
    isPinned: Bool? = nil
  ) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) stays at the top."
      return
    }

    do {
      let moved = try performListMutation {
        try database.moveCardCollection(id: id, toPosition: position, isPinned: isPinned)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Moved \(moved.name)."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func saveCardCollectionDescription(
    forListID listID: CardCollectionRecord.ID,
    rtfdData: Data?,
    plainText: String
  ) {
    do {
      try database.updateCardCollectionDescription(id: listID, rtfdData: rtfdData, plainText: plainText)
      try? database.recordLocalSyncSnapshotChange(reason: "list-description")
      reloadCardCollections(selecting: selectedCollectionID)
      pushCloudSyncChangesIfNeeded()
    } catch {
      statusMessage = "Description save failed."
    }
  }

  public func setCardCollectionDashboardVisibility(
    id: CardCollectionRecord.ID,
    showsDashboard: Bool
  ) {
    do {
      try performListMutation {
        try database.setCardCollectionDashboardVisibility(id: id, showsDashboard: showsDashboard)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = showsDashboard ? "Showing collection stats." : "Hid collection stats."
    } catch {
      statusMessage = "Collection stats update failed."
    }
  }

  public func setCardCollectionDashboardIncludesLands(
    id: CardCollectionRecord.ID,
    includesLands: Bool
  ) {
    do {
      try performListMutation {
        try database.setCardCollectionDashboardIncludesLands(id: id, includesLands: includesLands)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = includesLands ? "Type stats include lands." : "Type stats exclude lands."
    } catch {
      statusMessage = "Collection stats update failed."
    }
  }

  public func setCardCollectionDisplaySort(
    id: CardCollectionRecord.ID,
    mode: SortMode?,
    direction: SearchSortDirection
  ) {
    do {
      let list = try database.setCardCollectionDisplaySort(id: id, mode: mode, direction: direction)
      try? database.recordLocalSyncSnapshotChange(reason: "list-display-sort")
      reloadCardCollections(selecting: selectedCollectionID)
      pushCloudSyncChangesIfNeeded()
      if let mode {
        statusMessage =
          "Sorted \(list.name) by \(GrimoraSearchPreferences.sortDescription(sortMode: mode, sortDirection: direction))."
      } else {
        statusMessage = "Showing \(list.name) in collection order."
      }
    } catch {
      statusMessage = "Collection sort update failed."
    }
  }

  public func setCardCollectionViewMode(
    id: CardCollectionRecord.ID,
    mode: CardCollectionViewMode
  ) {
    do {
      let list = try database.setCardCollectionViewMode(id: id, viewMode: mode)
      try? database.recordLocalSyncSnapshotChange(reason: "list-view-mode")
      reloadCardCollections(selecting: selectedCollectionID)
      pushCloudSyncChangesIfNeeded()
      statusMessage = "Showing \(list.name) as \(mode == .grid ? "grid" : "list")."
    } catch {
      statusMessage = "Collection view update failed."
    }
  }

  public func setCardCollectionRuleset(
    id: CardCollectionRecord.ID,
    ruleset: CardCollectionRuleset
  ) {
    do {
      let list = try performListMutation {
        try database.setCardCollectionRuleset(id: id, ruleset: ruleset)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Set \(list.name) ruleset to \(ruleset.title)."
    } catch {
      statusMessage = "Ruleset update failed."
    }
  }

  @discardableResult
  public func importCardCollectionArchive(data: Data) -> CardCollectionImportSummary? {
    do {
      let archive = try CardCollectionArchiveCoder.decode(data)
      let listName = Self.normalizedImportListName(archive.list.name)
      let importResult = try performListMutation { () -> (listID: CardCollectionRecord.ID, summary: CardCollectionImportSummary) in
        let list = try database.createCardCollection(named: listName)
        try database.setCardCollectionRuleset(id: list.id, ruleset: archive.list.ruleset)

        let sortedCategories = archive.categories.sorted { lhs, rhs in
          if lhs.zone != rhs.zone {
            return lhs.zone.rawValue < rhs.zone.rawValue
          }
          if lhs.position != rhs.position {
            return lhs.position < rhs.position
          }
          return lhs.id < rhs.id
        }
        var categoryIDMap: [String: CardCollectionCategoryRecord.ID] = [:]
        for category in sortedCategories {
          let createdCategory = try database.createCardCollectionCategory(
            inList: list.id,
            zone: category.zone,
            named: category.name
          )
          categoryIDMap[category.id] = createdCategory.id
        }

        var missingCardIDs: [String] = []
        let sortedEntries = archive.entries.sorted { lhs, rhs in
          if lhs.position != rhs.position {
            return lhs.position < rhs.position
          }
          return lhs.id < rhs.id
        }
        for entry in sortedEntries {
          if try database.card(id: entry.cardID) == nil {
            missingCardIDs.append(entry.cardID)
          }
          try database.appendCard(
            entry.cardID,
            toList: list.id,
            zone: entry.zone,
            categoryID: entry.categoryID.flatMap { categoryIDMap[$0] },
            quantity: entry.quantity
          )
        }

        try database.updateCardCollectionDescription(
          id: list.id,
          rtfdData: archive.list.descriptionRTFDData,
          plainText: archive.list.descriptionPlainText
        )
        try database.setCardCollectionDashboardVisibility(
          id: list.id,
          showsDashboard: archive.list.showsDashboard
        )
        try database.setCardCollectionDashboardIncludesLands(
          id: list.id,
          includesLands: archive.list.dashboardIncludesLands
        )
        try database.setCardCollectionDisplaySort(
          id: list.id,
          mode: archive.list.displaySortMode,
          direction: archive.list.displaySortDirection
        )
        try database.setCardCollectionViewMode(
          id: list.id,
          viewMode: archive.list.viewMode
        )

        let uniqueMissingCardIDs = Array(Set(missingCardIDs)).sorted()
        let summary = CardCollectionImportSummary(
          listName: listName,
          cardCount: sortedEntries.reduce(0) { $0 + $1.quantity },
          categoryCount: sortedCategories.count,
          missingCardIDs: uniqueMissingCardIDs
        )
        return (list.id, summary)
      }

      reloadCardCollections(selecting: importResult.listID, activatingSelection: true)
      if importResult.summary.missingCardIDs.isEmpty {
        statusMessage = "Imported \(listName)."
      } else {
        statusMessage =
          "Imported \(listName). \(importResult.summary.missingCardIDs.count) unavailable print IDs were preserved."
      }
      return importResult.summary
    } catch {
      statusMessage = "Collection import failed."
      return nil
    }
  }

  @discardableResult
  public func createCardCollectionFromArchidektSource(
    _ source: String,
    named requestedName: String? = nil
  ) async -> CardCollectionImportSummary? {
    do {
      let importDeck = try await archidektImportDeck(from: source)
      let listName = Self.normalizedImportListName(requestedName ?? importDeck.name ?? "")
      return try performListMutation {
        let list = try database.createCardCollection(named: listName)
        return try importArchidektDeck(
          importDeck,
          intoListID: list.id,
          fallbackListName: list.name,
          sourceName: importDeck.name ?? list.name
        )
      }
    } catch {
      statusMessage = "Collection import failed."
      return nil
    }
  }

  @discardableResult
  public func importArchidektCards(
    from source: String,
    intoListID listID: CardCollectionRecord.ID
  ) async -> CardCollectionImportSummary? {
    do {
      let importDeck = try await archidektImportDeck(from: source)
      let listName = try database.cardCollection(id: listID)?.name ?? "Collection"
      return try performListMutation {
        try importArchidektDeck(
          importDeck,
          intoListID: listID,
          fallbackListName: listName,
          sourceName: importDeck.name
        )
      }
    } catch {
      statusMessage = "Collection import failed."
      return nil
    }
  }

  public func deleteCardCollection(id: CardCollectionRecord.ID) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) is managed by Grimora."
      return
    }

    do {
      try performListMutation {
        try database.deleteCardCollection(id: id)
      }
      reloadCardCollections(selecting: selectedCollectionID == id ? nil : selectedCollectionID)
      statusMessage = "Deleted collection."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  @discardableResult
  public func createCardCollectionCategory(
    named name: String,
    inListID listID: CardCollectionRecord.ID? = nil,
    zone: CardCollectionZone = .mainboard
  ) -> CardCollectionCategoryRecord? {
    guard let listID = listID ?? selectedCollectionID else {
      return nil
    }

    do {
      let category = try performListMutation {
        try database.createCardCollectionCategory(inList: listID, zone: zone, named: name)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Created \(category.name)."
      return selectedCollectionCategories.first { $0.id == category.id } ?? category
    } catch CardCollectionDatabaseError.emptyName {
      return nil
    } catch CardCollectionDatabaseError.duplicateName {
      statusMessage = "Category already exists."
      return nil
    } catch {
      statusMessage = "Category update failed."
      return nil
    }
  }

  public func renameCardCollectionCategory(id: CardCollectionCategoryRecord.ID, to name: String) {
    do {
      let category = try performListMutation {
        try database.renameCardCollectionCategory(id: id, to: name)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Renamed category to \(category.name)."
    } catch CardCollectionDatabaseError.emptyName {
      return
    } catch CardCollectionDatabaseError.duplicateName {
      statusMessage = "Category already exists."
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func deleteCardCollectionCategory(id: CardCollectionCategoryRecord.ID) {
    do {
      try performListMutation {
        try database.deleteCardCollectionCategory(id: id)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Deleted category."
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func moveCardCollectionCategory(id: CardCollectionCategoryRecord.ID, by offset: Int) {
    guard let index = selectedCollectionCategories.firstIndex(where: { $0.id == id }) else {
      return
    }

    moveCardCollectionCategory(id: id, toPosition: index + offset)
  }

  public func moveCardCollectionCategory(id: CardCollectionCategoryRecord.ID, toPosition position: Int) {
    do {
      try performListMutation {
        try database.moveCardCollectionCategory(id: id, toPosition: position)
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage = "Moved category."
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func addCard(_ card: CardRecord, toListID listID: CardCollectionRecord.ID) {
    addCardID(card.id, named: card.name, toListID: listID)
  }

  public func addCardToFavourites(_ card: CardRecord) {
    addCardsToFavourites([card.id], primaryCard: card)
  }

  public func isFavourite(_ card: CardRecord) -> Bool {
    favouriteCardIDs.contains(card.id)
  }

  /// Adds the card to Favourites if it isn't there yet, otherwise removes it.
  /// Backs the star button on search result cards.
  public func toggleFavourite(_ card: CardRecord) {
    if favouriteCardIDs.contains(card.id) {
      removeCardFromFavourites(card)
    } else {
      addCardToFavourites(card)
    }
  }

  public func removeCardFromFavourites(_ card: CardRecord) {
    guard let favouritesList else {
      return
    }

    do {
      let entryIDs = try database.cardCollectionEntries(forListID: favouritesList.id)
        .filter { $0.cardID == card.id }
        .map(\.id)
      guard !entryIDs.isEmpty else {
        return
      }

      try performListMutation {
        for id in entryIDs {
          try database.removeCardCollectionEntryCompletely(id: id)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      let listName = currentFavouriteListName(fallback: favouritesList.name)
      statusMessage = "Removed \(card.name) from \(listName)."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func addCardsToFavourites(
    _ cardIDs: [CardRecord.ID],
    primaryCard: CardRecord? = nil
  ) {
    let requestedCardIDs = uniqueCardIDs(cardIDs)
    guard !requestedCardIDs.isEmpty else {
      return
    }

    do {
      for cardID in requestedCardIDs {
        guard try database.card(id: cardID) != nil else {
          statusMessage = "One of those cards is no longer in the local library."
          return
        }
      }

      let currentLists = try database.cardCollections()
      let favouritesList =
        currentLists.first(where: { Self.isCanonicalFavouritesListName($0.name) })
        ?? currentLists.first(where: { Self.isFavouritesListName($0.name) })
      let existingFavouriteCardIDs: Set<CardRecord.ID>
      if let favouritesList {
        existingFavouriteCardIDs = Set(
          try database.cardCollectionEntries(forListID: favouritesList.id).map(\.cardID)
        )
      } else {
        existingFavouriteCardIDs = []
      }

      let cardIDsToAdd = requestedCardIDs.filter { !existingFavouriteCardIDs.contains($0) }
      guard !cardIDsToAdd.isEmpty else {
        statusMessage =
          requestedCardIDs.count == 1
          ? "Already in \(Self.favouritesListName)."
          : "Those cards are already in \(Self.favouritesListName)."
        return
      }

      let updatedList = try performListMutation {
        let list: CardCollectionRecord
        if let favouritesList {
          list = favouritesList
        } else {
          list = try database.createCardCollection(named: Self.favouritesListName)
        }
        for cardID in cardIDsToAdd {
          try database.appendCard(cardID, toList: list.id)
        }
        return list
      }

      reloadCardCollections(selecting: selectedCollectionID)
      let listName = currentFavouriteListName(fallback: updatedList.name)
      if cardIDsToAdd.count == 1,
        requestedCardIDs.count == 1,
        requestedCardIDs.first == primaryCard?.id,
        let primaryCard
      {
        statusMessage = "Added \(primaryCard.name) to \(listName)."
      } else {
        let noun = cardIDsToAdd.count == 1 ? "card" : "cards"
        statusMessage = "Added \(formatted(cardIDsToAdd.count)) \(noun) to \(listName)."
      }
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func addCardID(_ cardID: CardRecord.ID, toListID listID: CardCollectionRecord.ID) {
    addCardID(cardID, named: nil, toListID: listID)
  }

  public func addCards(_ cardIDs: [CardRecord.ID], toListID listID: CardCollectionRecord.ID) {
    let requestedCardIDs = cardIDs
    guard !requestedCardIDs.isEmpty else {
      return
    }

    do {
      for cardID in requestedCardIDs {
        guard try database.card(id: cardID) != nil else {
          statusMessage = "One of those cards is no longer in the local library."
          return
        }
      }

      try performListMutation {
        for cardID in requestedCardIDs {
          try database.appendCard(cardID, toList: listID)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      if let list = cardCollections.first(where: { $0.id == listID }) {
        let noun = requestedCardIDs.count == 1 ? "card" : "cards"
        statusMessage =
          "Added \(formatted(requestedCardIDs.count)) \(noun) to \(list.name)."
      }
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func removeCardCollectionEntry(id: CardCollectionEntryRecord.ID) {
    removeCardCollectionEntries(ids: [id])
  }

  public func incrementCardCollectionEntryQuantity(id: CardCollectionEntryRecord.ID) {
    incrementCardCollectionEntryQuantities(ids: [id])
  }

  public func incrementCardCollectionEntryQuantities(ids: [CardCollectionEntryRecord.ID]) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.incrementCardCollectionEntryQuantity(id: id)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage =
        uniqueIDs.count == 1
        ? "Increased card quantity."
        : "Increased \(formatted(uniqueIDs.count)) card quantities."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func setCardCollectionEntryQuantities(
    ids: [CardCollectionEntryRecord.ID],
    quantity: Int
  ) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.setCardCollectionEntryQuantity(id: id, quantity: quantity)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage =
        uniqueIDs.count == 1
        ? "Set card quantity."
        : "Set \(formatted(uniqueIDs.count)) card quantities."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func removeCardCollectionEntries(ids: [CardCollectionEntryRecord.ID]) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      let entriesBeforeRemoval = selectedCollectionEntries.filter { uniqueIDs.contains($0.id) }
      try performListMutation {
        for id in uniqueIDs {
          try database.removeCardCollectionEntry(id: id)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      let removedEntries = entriesBeforeRemoval.contains { $0.quantity <= 1 }
      if removedEntries {
        statusMessage =
          uniqueIDs.count == 1
          ? "Removed card from collection."
          : "Removed \(formatted(uniqueIDs.count)) cards from collection."
      } else {
        statusMessage =
          uniqueIDs.count == 1
          ? "Decreased card quantity."
          : "Decreased \(formatted(uniqueIDs.count)) card quantities."
      }
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func removeCardCollectionEntriesCompletely(ids: [CardCollectionEntryRecord.ID]) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.removeCardCollectionEntryCompletely(id: id)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      statusMessage =
        uniqueIDs.count == 1
        ? "Removed card from collection."
        : "Removed \(formatted(uniqueIDs.count)) cards from collection."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  public func moveCardCollectionEntry(
    id: CardCollectionEntryRecord.ID,
    toCategoryID categoryID: CardCollectionCategoryRecord.ID?
  ) {
    moveCardCollectionEntries(ids: [id], toCategoryID: categoryID)
  }

  public func moveCardCollectionEntries(
    ids: [CardCollectionEntryRecord.ID],
    toCategoryID categoryID: CardCollectionCategoryRecord.ID?
  ) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.moveCardCollectionEntry(id: id, toCategory: categoryID)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      let subject = uniqueIDs.count == 1 ? "card" : "\(formatted(uniqueIDs.count)) cards"
      if let categoryID,
        let category = selectedCollectionCategories.first(where: { $0.id == categoryID })
      {
        statusMessage = "Moved \(subject) to \(category.name)."
      } else {
        statusMessage = "Moved \(subject) to Uncategorized."
      }
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func moveCardCollectionEntry(
    id: CardCollectionEntryRecord.ID,
    toZone zone: CardCollectionZone
  ) {
    moveCardCollectionEntries(ids: [id], toZone: zone)
  }

  public func moveCardCollectionEntries(
    ids: [CardCollectionEntryRecord.ID],
    toZone zone: CardCollectionZone
  ) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }
    let zone = selectedCollection?.ruleset.normalizedZone(zone) ?? zone

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.moveCardCollectionEntry(id: id, toZone: zone)
        }
      }
      reloadCardCollections(selecting: selectedCollectionID)
      let subject = uniqueIDs.count == 1 ? "card" : "\(formatted(uniqueIDs.count)) cards"
      statusMessage = "Moved \(subject) to \(zone.title)."
    } catch {
      statusMessage = "Collection update failed."
    }
  }

  func uniqueEntryIDs(_ ids: [CardCollectionEntryRecord.ID]) -> [CardCollectionEntryRecord.ID] {
    var seenIDs: Set<CardCollectionEntryRecord.ID> = []
    return ids.filter { seenIDs.insert($0).inserted }
  }

  func uniqueCardIDs(_ ids: [CardRecord.ID]) -> [CardRecord.ID] {
    var seenIDs: Set<CardRecord.ID> = []
    return ids.filter { seenIDs.insert($0).inserted }
  }

  func isProtectedFavouritesListID(_ id: CardCollectionRecord.ID) -> Bool {
    if let list = cardCollections.first(where: { $0.id == id }) {
      return isProtectedFavouritesList(list)
    }

    guard let list = try? database.cardCollection(id: id) else {
      return false
    }
    return isProtectedFavouritesList(list)
  }

  @discardableResult
  private func useFavouritesList(
    adding cardIDs: [CardRecord.ID],
    primaryCard: CardRecord?,
    selectAfterCreate: Bool
  ) -> CardCollectionRecord? {
    do {
      let list = try ensureFavouritesList()
      if !cardIDs.isEmpty {
        addCardsToFavourites(cardIDs, primaryCard: primaryCard)
      } else {
        reloadCardCollections(
          selecting: selectAfterCreate ? list.id : selectedCollectionID,
          activatingSelection: selectAfterCreate
        )
        statusMessage = "\(Self.favouritesListName) already exists."
      }

      if selectAfterCreate {
        selectCardCollection(id: list.id)
      }
      return cardCollections.first { $0.id == list.id } ?? list
    } catch {
      statusMessage = "Collection update failed."
      return nil
    }
  }

  private func currentFavouriteListName(fallback: String) -> String {
    cardCollections.first(where: { Self.isCanonicalFavouritesListName($0.name) })?.name
      ?? cardCollections.first(where: { Self.isFavouritesListName($0.name) })?.name
      ?? fallback
  }
}
