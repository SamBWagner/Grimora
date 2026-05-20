import Foundation
import GrimoraCore

public enum GrimoraSidebarSelection: Equatable, Sendable {
  case search
  case listsOverview
  case newList
  case list(CardListRecord.ID)
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

public struct CardListImportSummary: Equatable, Sendable {
  public var listName: String
  public var cardCount: Int
  public var categoryCount: Int
  public var missingCardIDs: [String]
  public var sourceName: String?
  public var skippedLines: [CardListImportSkippedLine]

  public var importedEntryCount: Int {
    cardCount
  }

  public init(
    listName: String,
    cardCount: Int,
    categoryCount: Int,
    missingCardIDs: [String],
    sourceName: String? = nil,
    skippedLines: [CardListImportSkippedLine] = []
  ) {
    self.listName = listName
    self.cardCount = cardCount
    self.categoryCount = categoryCount
    self.missingCardIDs = missingCardIDs
    self.sourceName = sourceName
    self.skippedLines = skippedLines
  }
}

public struct CardListOverviewItem: Identifiable, Equatable, Sendable {
  public var list: CardListRecord
  public var topEntry: CardListEntryRecord?
  public var topCard: CardRecord?

  public var id: CardListRecord.ID {
    list.id
  }

  public init(
    list: CardListRecord,
    topEntry: CardListEntryRecord?,
    topCard: CardRecord?
  ) {
    self.list = list
    self.topEntry = topEntry
    self.topCard = topCard
  }
}

public struct CardListImportSkippedLine: Equatable, Sendable {
  public var lineNumber: Int?
  public var text: String
  public var reason: String

  public init(lineNumber: Int? = nil, text: String, reason: String) {
    self.lineNumber = lineNumber
    self.text = text
    self.reason = reason
  }
}

struct CardListUndoState: Sendable {
  var snapshot: CardListLibrarySnapshot
  var sidebarSelection: GrimoraSidebarSelection
  var selectedListID: CardListRecord.ID?
}
