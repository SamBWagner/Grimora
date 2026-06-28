import Foundation
import GrimoraCore

public enum GrimoraSidebarSelection: Equatable, Sendable {
  case search
  case listsOverview
  case newList
  case list(CardCollectionRecord.ID)
}

/// Tracks where the selected collection's detail state is in its load lifecycle.
///
/// The view switch keys off this so tapping a list swaps to the detail view *this*
/// run-loop tick (showing a skeleton) instead of blocking on a synchronous DB read.
/// `loading` carries the list ID it is loading so the detail view only shows the
/// skeleton for the collection currently selected, never a stale one.
public enum ListLoadPhase: Equatable, Sendable {
  case idle
  case loading(CardCollectionRecord.ID)
  case ready
}

/// The off-main result of reading a collection's detail state from the database.
/// Every field is `Sendable`, so the loader can compute it on a background task and
/// hand it back to the `@MainActor` model to publish.
struct LoadedSelectedListState: Sendable {
  var categories: [CardCollectionCategoryRecord]
  var entries: [CardCollectionEntryRecord]
  var warnings: [CardCollectionRulesetWarning]
  var sections: [CardCollectionEntrySection]
}

public enum LibraryReadinessState: Equatable, Sendable {
  case missing
  case initializing
  case ready
  case failed(String)
}

public enum GrimoraLibraryActivityState: Equatable, Sendable {
  case running
  case succeeded
  case failed
}

public enum GrimoraLibraryActivityStepState: Equatable, Sendable {
  case pending
  case running
  case succeeded
  case failed
}

public struct GrimoraLibraryActivityStep: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var detail: String?
  public var progress: Double?
  public var state: GrimoraLibraryActivityStepState

  public init(
    id: String,
    title: String,
    detail: String? = nil,
    progress: Double? = 0,
    state: GrimoraLibraryActivityStepState = .pending
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.progress = progress
    self.state = state
  }
}

public enum GrimoraLibraryActivityOperation: Equatable, Sendable {
  case setupLibrary
  case importCardDatabase
  case refreshCardDatabase
  case deleteAndRefreshDatabase
  case refreshCardValues
  case updateSyncedDatabase
}

public struct GrimoraLibraryActivity: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var operation: GrimoraLibraryActivityOperation
  public var title: String
  public var message: String
  public var state: GrimoraLibraryActivityState
  public var steps: [GrimoraLibraryActivityStep]

  public init(
    id: UUID = UUID(),
    operation: GrimoraLibraryActivityOperation = .importCardDatabase,
    title: String,
    message: String,
    state: GrimoraLibraryActivityState,
    steps: [GrimoraLibraryActivityStep] = []
  ) {
    self.id = id
    self.operation = operation
    self.title = title
    self.message = message
    self.state = state
    self.steps = steps
  }
}

public enum ValueHistoryBackgroundActivityState: Equatable, Sendable {
  case running
  case failed
}

public struct ValueHistoryBackgroundActivity: Equatable, Sendable {
  public var state: ValueHistoryBackgroundActivityState
  public var title: String
  public var message: String
  public var progress: Double?

  public init(
    state: ValueHistoryBackgroundActivityState,
    title: String,
    message: String,
    progress: Double? = nil
  ) {
    self.state = state
    self.title = title
    self.message = message
    self.progress = progress
  }
}

public enum GrimoraCloudSyncMode: String, Equatable, Sendable {
  case undecided
  case enabled
  case disabled
}

public struct CardCollectionImportSummary: Equatable, Sendable {
  public var listName: String
  public var cardCount: Int
  public var categoryCount: Int
  public var missingCardIDs: [String]
  public var sourceName: String?
  public var skippedLines: [CardCollectionImportSkippedLine]

  public var importedEntryCount: Int {
    cardCount
  }

  public init(
    listName: String,
    cardCount: Int,
    categoryCount: Int,
    missingCardIDs: [String],
    sourceName: String? = nil,
    skippedLines: [CardCollectionImportSkippedLine] = []
  ) {
    self.listName = listName
    self.cardCount = cardCount
    self.categoryCount = categoryCount
    self.missingCardIDs = missingCardIDs
    self.sourceName = sourceName
    self.skippedLines = skippedLines
  }
}

public struct CardCollectionOverviewItem: Identifiable, Equatable, Sendable {
  public var list: CardCollectionRecord
  public var topEntry: CardCollectionEntryRecord?
  public var topCard: CardRecord?

  public var id: CardCollectionRecord.ID {
    list.id
  }

  public init(
    list: CardCollectionRecord,
    topEntry: CardCollectionEntryRecord?,
    topCard: CardRecord?
  ) {
    self.list = list
    self.topEntry = topEntry
    self.topCard = topCard
  }
}

public struct CardCollectionImportSkippedLine: Equatable, Sendable {
  public var lineNumber: Int?
  public var text: String
  public var reason: String

  public init(lineNumber: Int? = nil, text: String, reason: String) {
    self.lineNumber = lineNumber
    self.text = text
    self.reason = reason
  }
}

struct CardCollectionUndoState: Sendable {
  var snapshot: CardCollectionLibrarySnapshot
  var sidebarSelection: GrimoraSidebarSelection
  var selectedCollectionID: CardCollectionRecord.ID?
}
