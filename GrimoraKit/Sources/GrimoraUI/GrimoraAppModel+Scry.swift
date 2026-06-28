import Foundation
import GrimoraCore

/// "Scanned" is a special collection, just like Favourites: it's identified by
/// name, created lazily the first time you keep a scan, and is where Scry sends
/// cards by default.
extension GrimoraAppModel {
  public static let scannedListName = "Scanned"

  public static func isScannedListName(_ name: String) -> Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare(scannedListName) == .orderedSame
  }

  /// The Scanned collection if it already exists (it's created on first keep).
  public var scannedList: CardCollectionRecord? {
    cardCollections.first { Self.isScannedListName($0.name) }
  }

  public func isScannedList(_ list: CardCollectionRecord) -> Bool {
    Self.isScannedListName(list.name)
  }

  /// Favourites and Scanned are the built-in "system" lists — pinned to the top
  /// of the collections overview and visually set apart from user collections.
  public func isSystemList(_ list: CardCollectionRecord) -> Bool {
    isProtectedFavouritesList(list) || isScannedList(list)
  }

  @discardableResult
  func ensureScannedList() throws -> CardCollectionRecord {
    let lists = try database.cardCollections()
    if let scanned = lists.first(where: { Self.isScannedListName($0.name) }) {
      return scanned
    }
    return try database.createCardCollection(named: Self.scannedListName)
  }

  /// Adds a card to the Scanned collection, creating it if needed.
  @discardableResult
  public func addCardToScanned(_ card: CardRecord) -> Bool {
    do {
      let list = try ensureScannedList()
      addCard(card, toListID: list.id)
      return true
    } catch {
      statusMessage = "Couldn't add \(card.name) to \(Self.scannedListName)."
      return false
    }
  }
}
