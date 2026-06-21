import Foundation

struct CloudSyncListSemanticIdentity: Hashable, Sendable {
  struct Category: Hashable, Sendable {
    var zone: CardListZone
    var name: String
    var position: Int
  }

  struct Entry: Hashable, Sendable {
    var cardID: CardRecord.ID
    var zone: CardListZone
    var category: Category?
    var position: Int
    var quantity: Int
  }

  var normalizedName: String
  var ruleset: CardListRuleset
  var descriptionRTFDData: Data?
  var descriptionPlainText: String
  var showsDashboard: Bool
  var dashboardIncludesLands: Bool
  var displaySortMode: SortMode?
  var displaySortDirection: SearchSortDirection
  var viewMode: CardListViewMode
  var categories: [Category]
  var entries: [Entry]

  init(listID: CardListRecord.ID, snapshot: CardListLibrarySnapshot) {
    guard let list = snapshot.lists.first(where: { $0.id == listID }) else {
      normalizedName = ""
      ruleset = .none
      descriptionRTFDData = nil
      descriptionPlainText = ""
      showsDashboard = false
      dashboardIncludesLands = false
      displaySortMode = nil
      displaySortDirection = .ascending
      viewMode = .grid
      categories = []
      entries = []
      return
    }

    normalizedName = Self.normalizedName(list.name)
    ruleset = list.ruleset
    descriptionRTFDData = list.descriptionRTFDData
    descriptionPlainText = list.descriptionPlainText
    showsDashboard = list.showsDashboard
    dashboardIncludesLands = list.dashboardIncludesLands
    displaySortMode = list.displaySortMode
    displaySortDirection = list.displaySortDirection
    viewMode = list.viewMode

    let categoryValues = snapshot.categories
      .filter { $0.listID == listID }
      .map {
        (
          id: $0.id,
          value: Category(
            zone: $0.zone,
            name: Self.normalizedName($0.name),
            position: $0.position
          )
        )
      }
    let categoriesByID = Dictionary(uniqueKeysWithValues: categoryValues.map { ($0.id, $0.value) })
    categories = categoryValues.map(\.value).sorted(by: Self.categorySort)
    entries = snapshot.entries
      .filter { $0.listID == listID }
      .map {
        Entry(
          cardID: $0.cardID.lowercased(),
          zone: $0.zone,
          category: $0.categoryID.flatMap { categoriesByID[$0] },
          position: $0.position,
          quantity: $0.quantity
        )
      }
      .sorted(by: Self.entrySort)
  }

  static func normalizedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func categorySort(_ lhs: Category, _ rhs: Category) -> Bool {
    if lhs.zone != rhs.zone {
      return lhs.zone.rawValue < rhs.zone.rawValue
    }
    if lhs.position != rhs.position {
      return lhs.position < rhs.position
    }
    return lhs.name < rhs.name
  }

  private static func entrySort(_ lhs: Entry, _ rhs: Entry) -> Bool {
    if lhs.zone != rhs.zone {
      return lhs.zone.rawValue < rhs.zone.rawValue
    }
    switch (lhs.category, rhs.category) {
    case (nil, nil):
      break
    case (nil, .some):
      return true
    case (.some, nil):
      return false
    case let (.some(lhsCategory), .some(rhsCategory)):
      if lhsCategory != rhsCategory {
        return categorySort(lhsCategory, rhsCategory)
      }
    }
    if lhs.position != rhs.position {
      return lhs.position < rhs.position
    }
    if lhs.cardID != rhs.cardID {
      return lhs.cardID < rhs.cardID
    }
    return lhs.quantity < rhs.quantity
  }
}
