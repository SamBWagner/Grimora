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

  public func isFavouritesList(_ list: CardListRecord) -> Bool {
    Self.isFavouritesListName(list.name)
  }

  public func isProtectedFavouritesList(_ list: CardListRecord) -> Bool {
    Self.isFavouritesListName(list.name)
  }

  public func selectListsOverview() {
    selectedListID = nil
    selectedListCategories = []
    selectedListEntries = []
    selectedListRulesetWarnings = []
    resetSelectedListSearchResults()
    sidebarSelection = .listsOverview
    closeSelectedCard()
  }

  public func selectSearch() {
    sidebarSelection = .search
    closeSelectedCard()
  }

  public func selectNewList() {
    sidebarSelection = .newList
    closeSelectedCard()
  }

  public func cancelNewListCreation(returningTo previousSelection: GrimoraSidebarSelection?) {
    switch previousSelection {
    case .list(let id) where cardLists.contains(where: { $0.id == id }):
      selectCardList(id: id)
    case .listsOverview:
      selectListsOverview()
    case .list, .search, .newList, nil:
      selectSearch()
    }
  }

  public func selectCardList(id: CardListRecord.ID) {
    guard cardLists.contains(where: { $0.id == id }) else {
      if selectedListID == id {
        selectedListID = nil
        selectedListCategories = []
        selectedListEntries = []
        selectedListRulesetWarnings = []
        resetSelectedListSearchResults()
      }
      if sidebarSelection == .list(id) {
        sidebarSelection = .search
      }
      return
    }

    selectedListID = id
    sidebarSelection = .list(id)
    closeSelectedCard()
    loadSelectedListState()
  }

  public func closeSelectedList() {
    selectedListID = nil
    selectedListCategories = []
    selectedListEntries = []
    selectedListRulesetWarnings = []
    resetSelectedListSearchResults()
    sidebarSelection = .listsOverview
    closeSelectedCard()
  }

  public func setSelectedListSearchDraft(_ text: String) {
    guard selectedListSearchText != text else {
      return
    }

    selectedListSearchText = text
    reloadSelectedListSearch()
  }

  public func clearSelectedListSearch() {
    setSelectedListSearchDraft("")
  }

  func reloadSelectedListSearch() {
    let query = GrimoraSearchHistoryStore.normalizedQuery(selectedListSearchText)
    selectedListSearchUnsupportedMessage = nil
    guard let selectedListID, !query.isEmpty else {
      searchedSelectedListEntries = nil
      return
    }

    do {
      switch try database.searchCardListEntries(forListID: selectedListID, text: query) {
      case .results(let entries):
        searchedSelectedListEntries = entries
      case .unsupported(let reason):
        searchedSelectedListEntries = []
        selectedListSearchUnsupportedMessage = reason.message
      }
    } catch {
      searchedSelectedListEntries = []
      statusMessage = "List search failed."
    }
  }

  func resetSelectedListSearchResults() {
    searchedSelectedListEntries = nil
    selectedListSearchUnsupportedMessage = nil
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
      return try database.searchAllCardListEntries(text: normalizedQuery)
    } catch {
      statusMessage = "List search failed."
      return .results([])
    }
  }

  /// Whether the dashboard is currently filtering its tiles by a cross-list search query.
  public var hasActiveDashboardSearch: Bool {
    !GrimoraSearchHistoryStore.normalizedQuery(dashboardSearchText).isEmpty
  }

  /// The dashboard overview items narrowed to the lists matching the active cross-list search.
  /// Returns every item when no filter is active (or when the query can't be compiled).
  public var filteredCardListOverviewItems: [CardListOverviewItem] {
    guard let dashboardListMatchIDs else {
      return cardListOverviewItems
    }
    return cardListOverviewItems.filter { dashboardListMatchIDs.contains($0.list.id) }
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
      try database.restoreCardListLibrarySnapshot(undoState.snapshot)
      try? database.recordLocalSyncSnapshotChange(reason: "undo-list-action")
      canUndoListAction = !listUndoStack.isEmpty
      let restoredSelection = restoredListSelection(from: undoState)
      reloadCardLists(
        selecting: restoredSelection.selectedListID,
        activatingSelection: restoredSelection.activatesSelection
      )
      sidebarSelection = restoredSelection.sidebarSelection
      if case .list(let listID) = sidebarSelection {
        selectedListID = listID
        loadSelectedListState()
      } else if sidebarSelection != .list(selectedListID ?? "") {
        selectedListID = nil
        selectedListCategories = []
        selectedListEntries = []
        selectedListRulesetWarnings = []
        resetSelectedListSearchResults()
      }
      statusMessage = "Undid list action."
      pushCloudSyncChangesIfNeeded()
    } catch {
      canUndoListAction = !listUndoStack.isEmpty
      statusMessage = "Undo failed."
    }
  }

  @discardableResult
  public func createCardList(
    named name: String,
    adding card: CardRecord? = nil,
    selectAfterCreate: Bool = false
  ) -> CardListRecord? {
    if Self.isFavouritesListName(name) {
      return useFavouritesList(
        adding: card.map { [$0.id] } ?? [],
        primaryCard: card,
        selectAfterCreate: selectAfterCreate
      )
    }

    do {
      let list = try performListMutation {
        let list = try database.createCardList(named: name)
        if let card {
          try database.appendCard(card.id, toList: list.id)
        }
        return list
      }
      reloadCardLists(
        selecting: selectAfterCreate ? list.id : selectedListID,
        activatingSelection: selectAfterCreate
      )
      statusMessage = card.map { "Added \($0.name) to \(list.name)." } ?? "Created \(list.name)."
      return cardLists.first { $0.id == list.id } ?? list
    } catch CardListDatabaseError.emptyName {
      return nil
    } catch {
      statusMessage = "List update failed."
      return nil
    }
  }

  @discardableResult
  public func createCardList(
    named name: String,
    addingCardIDs cardIDs: [CardRecord.ID],
    selectAfterCreate: Bool = false
  ) -> CardListRecord? {
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
        let list = try database.createCardList(named: name)
        for cardID in requestedCardIDs {
          try database.appendCard(cardID, toList: list.id)
        }
        return list
      }
      reloadCardLists(
        selecting: selectAfterCreate ? list.id : selectedListID,
        activatingSelection: selectAfterCreate
      )
      if requestedCardIDs.isEmpty {
        statusMessage = "Created \(list.name)."
      } else {
        let noun = requestedCardIDs.count == 1 ? "card" : "cards"
        statusMessage = "Created \(list.name) with \(formatted(requestedCardIDs.count)) \(noun)."
      }
      return cardLists.first { $0.id == list.id } ?? list
    } catch CardListDatabaseError.emptyName {
      return nil
    } catch {
      statusMessage = "List update failed."
      return nil
    }
  }

  @discardableResult
  public func createCardListFromCurrentSearch(named name: String) async -> CardListRecord? {
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
    let undoState: CardListUndoState
    do {
      undoState = try CardListUndoState(
        snapshot: database.cardListLibrarySnapshot(),
        sidebarSelection: sidebarSelection,
        selectedListID: selectedListID
      )
    } catch {
      statusMessage = "List update failed."
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
          let list = try database.createCardList(named: normalizedName)
          for card in cards {
            try database.appendCard(card.id, toList: list.id)
          }
          return SearchListCreationResult.success(listID: list.id, cardCount: cards.count)
        case .unsupported:
          return SearchListCreationResult.unsupported
        }
      } catch CardListDatabaseError.emptyName {
        return SearchListCreationResult.emptyName
      } catch {
        return SearchListCreationResult.failure
      }
    }.value

    guard generation == searchGeneration else {
      statusMessage = "Search changed before the list could be created."
      return nil
    }

    switch result {
    case .success(let listID, let cardCount):
      pushListUndoState(undoState)
      try? database.recordLocalSyncSnapshotChange(reason: "search-list-created")
      reloadCardLists(selecting: listID, activatingSelection: true)
      pushCloudSyncChangesIfNeeded()
      guard let list = selectedList else {
        statusMessage = "List update failed."
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
      statusMessage = "List update failed."
      return nil
    }
  }

  public func renameCardList(id: CardListRecord.ID, to name: String) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) is managed by Grimora."
      return
    }

    do {
      let list = try performListMutation {
        try database.renameCardList(id: id, to: name)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Renamed list to \(list.name)."
    } catch CardListDatabaseError.emptyName {
      return
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func setCardListPinned(
    id: CardListRecord.ID,
    isPinned: Bool,
    now: Date = Date()
  ) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) stays at the top."
      return
    }

    do {
      let list = try performListMutation {
        try database.setCardListPinned(id: id, isPinned: isPinned, now: now)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = isPinned ? "Pinned \(list.name)." : "Unpinned \(list.name)."
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func moveCardList(id: CardListRecord.ID, by offset: Int) {
    guard let list = cardLists.first(where: { $0.id == id }) else {
      return
    }
    guard !isProtectedFavouritesList(list) else {
      statusMessage = "\(Self.favouritesListName) stays at the top."
      return
    }
    let sectionLists = list.isPinned ? pinnedCardLists : unpinnedCardLists
    guard let index = sectionLists.firstIndex(where: { $0.id == id }) else {
      return
    }

    moveCardList(id: id, toPosition: index + offset, isPinned: list.isPinned)
  }

  public func moveCardList(
    id: CardListRecord.ID,
    toPosition position: Int,
    isPinned: Bool? = nil
  ) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) stays at the top."
      return
    }

    do {
      let moved = try performListMutation {
        try database.moveCardList(id: id, toPosition: position, isPinned: isPinned)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Moved \(moved.name)."
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func saveCardListDescription(
    forListID listID: CardListRecord.ID,
    rtfdData: Data?,
    plainText: String
  ) {
    do {
      try database.updateCardListDescription(id: listID, rtfdData: rtfdData, plainText: plainText)
      try? database.recordLocalSyncSnapshotChange(reason: "list-description")
      reloadCardLists(selecting: selectedListID)
      pushCloudSyncChangesIfNeeded()
    } catch {
      statusMessage = "Description save failed."
    }
  }

  public func setCardListDashboardVisibility(
    id: CardListRecord.ID,
    showsDashboard: Bool
  ) {
    do {
      try performListMutation {
        try database.setCardListDashboardVisibility(id: id, showsDashboard: showsDashboard)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = showsDashboard ? "Showing list stats." : "Hid list stats."
    } catch {
      statusMessage = "List stats update failed."
    }
  }

  public func setCardListDashboardIncludesLands(
    id: CardListRecord.ID,
    includesLands: Bool
  ) {
    do {
      try performListMutation {
        try database.setCardListDashboardIncludesLands(id: id, includesLands: includesLands)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = includesLands ? "Type stats include lands." : "Type stats exclude lands."
    } catch {
      statusMessage = "List stats update failed."
    }
  }

  public func setCardListDisplaySort(
    id: CardListRecord.ID,
    mode: SortMode?,
    direction: SearchSortDirection
  ) {
    do {
      let list = try database.setCardListDisplaySort(id: id, mode: mode, direction: direction)
      try? database.recordLocalSyncSnapshotChange(reason: "list-display-sort")
      reloadCardLists(selecting: selectedListID)
      pushCloudSyncChangesIfNeeded()
      if let mode {
        statusMessage =
          "Sorted \(list.name) by \(GrimoraSearchPreferences.sortDescription(sortMode: mode, sortDirection: direction))."
      } else {
        statusMessage = "Showing \(list.name) in list order."
      }
    } catch {
      statusMessage = "List sort update failed."
    }
  }

  public func setCardListViewMode(
    id: CardListRecord.ID,
    mode: CardListViewMode
  ) {
    do {
      let list = try database.setCardListViewMode(id: id, viewMode: mode)
      try? database.recordLocalSyncSnapshotChange(reason: "list-view-mode")
      reloadCardLists(selecting: selectedListID)
      pushCloudSyncChangesIfNeeded()
      statusMessage = "Showing \(list.name) as \(mode == .grid ? "grid" : "list")."
    } catch {
      statusMessage = "List view update failed."
    }
  }

  public func setCardListRuleset(
    id: CardListRecord.ID,
    ruleset: CardListRuleset
  ) {
    do {
      let list = try performListMutation {
        try database.setCardListRuleset(id: id, ruleset: ruleset)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Set \(list.name) ruleset to \(ruleset.title)."
    } catch {
      statusMessage = "Ruleset update failed."
    }
  }

  @discardableResult
  public func importCardListArchive(data: Data) -> CardListImportSummary? {
    do {
      let archive = try CardListArchiveCoder.decode(data)
      let listName = Self.normalizedImportListName(archive.list.name)
      let importResult = try performListMutation { () -> (listID: CardListRecord.ID, summary: CardListImportSummary) in
        let list = try database.createCardList(named: listName)
        try database.setCardListRuleset(id: list.id, ruleset: archive.list.ruleset)

        let sortedCategories = archive.categories.sorted { lhs, rhs in
          if lhs.zone != rhs.zone {
            return lhs.zone.rawValue < rhs.zone.rawValue
          }
          if lhs.position != rhs.position {
            return lhs.position < rhs.position
          }
          return lhs.id < rhs.id
        }
        var categoryIDMap: [String: CardListCategoryRecord.ID] = [:]
        for category in sortedCategories {
          let createdCategory = try database.createCardListCategory(
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

        try database.updateCardListDescription(
          id: list.id,
          rtfdData: archive.list.descriptionRTFDData,
          plainText: archive.list.descriptionPlainText
        )
        try database.setCardListDashboardVisibility(
          id: list.id,
          showsDashboard: archive.list.showsDashboard
        )
        try database.setCardListDashboardIncludesLands(
          id: list.id,
          includesLands: archive.list.dashboardIncludesLands
        )
        try database.setCardListDisplaySort(
          id: list.id,
          mode: archive.list.displaySortMode,
          direction: archive.list.displaySortDirection
        )
        try database.setCardListViewMode(
          id: list.id,
          viewMode: archive.list.viewMode
        )

        let uniqueMissingCardIDs = Array(Set(missingCardIDs)).sorted()
        let summary = CardListImportSummary(
          listName: listName,
          cardCount: sortedEntries.reduce(0) { $0 + $1.quantity },
          categoryCount: sortedCategories.count,
          missingCardIDs: uniqueMissingCardIDs
        )
        return (list.id, summary)
      }

      reloadCardLists(selecting: importResult.listID, activatingSelection: true)
      if importResult.summary.missingCardIDs.isEmpty {
        statusMessage = "Imported \(listName)."
      } else {
        statusMessage =
          "Imported \(listName). \(importResult.summary.missingCardIDs.count) unavailable print IDs were preserved."
      }
      return importResult.summary
    } catch {
      statusMessage = "List import failed."
      return nil
    }
  }

  @discardableResult
  public func createCardListFromArchidektSource(
    _ source: String,
    named requestedName: String? = nil
  ) async -> CardListImportSummary? {
    do {
      let importDeck = try await archidektImportDeck(from: source)
      let listName = Self.normalizedImportListName(requestedName ?? importDeck.name ?? "")
      return try performListMutation {
        let list = try database.createCardList(named: listName)
        return try importArchidektDeck(
          importDeck,
          intoListID: list.id,
          fallbackListName: list.name,
          sourceName: importDeck.name ?? list.name
        )
      }
    } catch {
      statusMessage = "List import failed."
      return nil
    }
  }

  @discardableResult
  public func importArchidektCards(
    from source: String,
    intoListID listID: CardListRecord.ID
  ) async -> CardListImportSummary? {
    do {
      let importDeck = try await archidektImportDeck(from: source)
      let listName = try database.cardList(id: listID)?.name ?? "List"
      return try performListMutation {
        try importArchidektDeck(
          importDeck,
          intoListID: listID,
          fallbackListName: listName,
          sourceName: importDeck.name
        )
      }
    } catch {
      statusMessage = "List import failed."
      return nil
    }
  }

  public func deleteCardList(id: CardListRecord.ID) {
    guard !isProtectedFavouritesListID(id) else {
      statusMessage = "\(Self.favouritesListName) is managed by Grimora."
      return
    }

    do {
      try performListMutation {
        try database.deleteCardList(id: id)
      }
      reloadCardLists(selecting: selectedListID == id ? nil : selectedListID)
      statusMessage = "Deleted list."
    } catch {
      statusMessage = "List update failed."
    }
  }

  @discardableResult
  public func createCardListCategory(
    named name: String,
    inListID listID: CardListRecord.ID? = nil,
    zone: CardListZone = .mainboard
  ) -> CardListCategoryRecord? {
    guard let listID = listID ?? selectedListID else {
      return nil
    }

    do {
      let category = try performListMutation {
        try database.createCardListCategory(inList: listID, zone: zone, named: name)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Created \(category.name)."
      return selectedListCategories.first { $0.id == category.id } ?? category
    } catch CardListDatabaseError.emptyName {
      return nil
    } catch CardListDatabaseError.duplicateName {
      statusMessage = "Category already exists."
      return nil
    } catch {
      statusMessage = "Category update failed."
      return nil
    }
  }

  public func renameCardListCategory(id: CardListCategoryRecord.ID, to name: String) {
    do {
      let category = try performListMutation {
        try database.renameCardListCategory(id: id, to: name)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Renamed category to \(category.name)."
    } catch CardListDatabaseError.emptyName {
      return
    } catch CardListDatabaseError.duplicateName {
      statusMessage = "Category already exists."
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func deleteCardListCategory(id: CardListCategoryRecord.ID) {
    do {
      try performListMutation {
        try database.deleteCardListCategory(id: id)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Deleted category."
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func moveCardListCategory(id: CardListCategoryRecord.ID, by offset: Int) {
    guard let index = selectedListCategories.firstIndex(where: { $0.id == id }) else {
      return
    }

    moveCardListCategory(id: id, toPosition: index + offset)
  }

  public func moveCardListCategory(id: CardListCategoryRecord.ID, toPosition position: Int) {
    do {
      try performListMutation {
        try database.moveCardListCategory(id: id, toPosition: position)
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage = "Moved category."
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func addCard(_ card: CardRecord, toListID listID: CardListRecord.ID) {
    addCardID(card.id, named: card.name, toListID: listID)
  }

  public func addCardToFavourites(_ card: CardRecord) {
    addCardsToFavourites([card.id], primaryCard: card)
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

      let currentLists = try database.cardLists()
      let favouritesList =
        currentLists.first(where: { Self.isCanonicalFavouritesListName($0.name) })
        ?? currentLists.first(where: { Self.isFavouritesListName($0.name) })
      let existingFavouriteCardIDs: Set<CardRecord.ID>
      if let favouritesList {
        existingFavouriteCardIDs = Set(
          try database.cardListEntries(forListID: favouritesList.id).map(\.cardID)
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
        let list: CardListRecord
        if let favouritesList {
          list = favouritesList
        } else {
          list = try database.createCardList(named: Self.favouritesListName)
        }
        for cardID in cardIDsToAdd {
          try database.appendCard(cardID, toList: list.id)
        }
        return list
      }

      reloadCardLists(selecting: selectedListID)
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
      statusMessage = "List update failed."
    }
  }

  public func addCardID(_ cardID: CardRecord.ID, toListID listID: CardListRecord.ID) {
    addCardID(cardID, named: nil, toListID: listID)
  }

  public func addCards(_ cardIDs: [CardRecord.ID], toListID listID: CardListRecord.ID) {
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
      reloadCardLists(selecting: selectedListID)
      if let list = cardLists.first(where: { $0.id == listID }) {
        let noun = requestedCardIDs.count == 1 ? "card" : "cards"
        statusMessage =
          "Added \(formatted(requestedCardIDs.count)) \(noun) to \(list.name)."
      }
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func removeCardListEntry(id: CardListEntryRecord.ID) {
    removeCardListEntries(ids: [id])
  }

  public func incrementCardListEntryQuantity(id: CardListEntryRecord.ID) {
    incrementCardListEntryQuantities(ids: [id])
  }

  public func incrementCardListEntryQuantities(ids: [CardListEntryRecord.ID]) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.incrementCardListEntryQuantity(id: id)
        }
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage =
        uniqueIDs.count == 1
        ? "Increased card quantity."
        : "Increased \(formatted(uniqueIDs.count)) card quantities."
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func setCardListEntryQuantities(
    ids: [CardListEntryRecord.ID],
    quantity: Int
  ) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.setCardListEntryQuantity(id: id, quantity: quantity)
        }
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage =
        uniqueIDs.count == 1
        ? "Set card quantity."
        : "Set \(formatted(uniqueIDs.count)) card quantities."
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func removeCardListEntries(ids: [CardListEntryRecord.ID]) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      let entriesBeforeRemoval = selectedListEntries.filter { uniqueIDs.contains($0.id) }
      try performListMutation {
        for id in uniqueIDs {
          try database.removeCardListEntry(id: id)
        }
      }
      reloadCardLists(selecting: selectedListID)
      let removedEntries = entriesBeforeRemoval.contains { $0.quantity <= 1 }
      if removedEntries {
        statusMessage =
          uniqueIDs.count == 1
          ? "Removed card from list."
          : "Removed \(formatted(uniqueIDs.count)) cards from list."
      } else {
        statusMessage =
          uniqueIDs.count == 1
          ? "Decreased card quantity."
          : "Decreased \(formatted(uniqueIDs.count)) card quantities."
      }
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func removeCardListEntriesCompletely(ids: [CardListEntryRecord.ID]) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.removeCardListEntryCompletely(id: id)
        }
      }
      reloadCardLists(selecting: selectedListID)
      statusMessage =
        uniqueIDs.count == 1
        ? "Removed card from list."
        : "Removed \(formatted(uniqueIDs.count)) cards from list."
    } catch {
      statusMessage = "List update failed."
    }
  }

  public func moveCardListEntry(
    id: CardListEntryRecord.ID,
    toCategoryID categoryID: CardListCategoryRecord.ID?
  ) {
    moveCardListEntries(ids: [id], toCategoryID: categoryID)
  }

  public func moveCardListEntries(
    ids: [CardListEntryRecord.ID],
    toCategoryID categoryID: CardListCategoryRecord.ID?
  ) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.moveCardListEntry(id: id, toCategory: categoryID)
        }
      }
      reloadCardLists(selecting: selectedListID)
      let subject = uniqueIDs.count == 1 ? "card" : "\(formatted(uniqueIDs.count)) cards"
      if let categoryID,
        let category = selectedListCategories.first(where: { $0.id == categoryID })
      {
        statusMessage = "Moved \(subject) to \(category.name)."
      } else {
        statusMessage = "Moved \(subject) to Uncategorized."
      }
    } catch {
      statusMessage = "Category update failed."
    }
  }

  public func moveCardListEntry(
    id: CardListEntryRecord.ID,
    toZone zone: CardListZone
  ) {
    moveCardListEntries(ids: [id], toZone: zone)
  }

  public func moveCardListEntries(
    ids: [CardListEntryRecord.ID],
    toZone zone: CardListZone
  ) {
    let uniqueIDs = uniqueEntryIDs(ids)
    guard !uniqueIDs.isEmpty else {
      return
    }
    let zone = selectedList?.ruleset.normalizedZone(zone) ?? zone

    do {
      try performListMutation {
        for id in uniqueIDs {
          try database.moveCardListEntry(id: id, toZone: zone)
        }
      }
      reloadCardLists(selecting: selectedListID)
      let subject = uniqueIDs.count == 1 ? "card" : "\(formatted(uniqueIDs.count)) cards"
      statusMessage = "Moved \(subject) to \(zone.title)."
    } catch {
      statusMessage = "List update failed."
    }
  }

  func uniqueEntryIDs(_ ids: [CardListEntryRecord.ID]) -> [CardListEntryRecord.ID] {
    var seenIDs: Set<CardListEntryRecord.ID> = []
    return ids.filter { seenIDs.insert($0).inserted }
  }

  func uniqueCardIDs(_ ids: [CardRecord.ID]) -> [CardRecord.ID] {
    var seenIDs: Set<CardRecord.ID> = []
    return ids.filter { seenIDs.insert($0).inserted }
  }

  func isProtectedFavouritesListID(_ id: CardListRecord.ID) -> Bool {
    if let list = cardLists.first(where: { $0.id == id }) {
      return isProtectedFavouritesList(list)
    }

    guard let list = try? database.cardList(id: id) else {
      return false
    }
    return isProtectedFavouritesList(list)
  }

  @discardableResult
  private func useFavouritesList(
    adding cardIDs: [CardRecord.ID],
    primaryCard: CardRecord?,
    selectAfterCreate: Bool
  ) -> CardListRecord? {
    do {
      let list = try ensureFavouritesList()
      if !cardIDs.isEmpty {
        addCardsToFavourites(cardIDs, primaryCard: primaryCard)
      } else {
        reloadCardLists(
          selecting: selectAfterCreate ? list.id : selectedListID,
          activatingSelection: selectAfterCreate
        )
        statusMessage = "\(Self.favouritesListName) already exists."
      }

      if selectAfterCreate {
        selectCardList(id: list.id)
      }
      return cardLists.first { $0.id == list.id } ?? list
    } catch {
      statusMessage = "List update failed."
      return nil
    }
  }

  private func currentFavouriteListName(fallback: String) -> String {
    cardLists.first(where: { Self.isCanonicalFavouritesListName($0.name) })?.name
      ?? cardLists.first(where: { Self.isFavouritesListName($0.name) })?.name
      ?? fallback
  }
}
