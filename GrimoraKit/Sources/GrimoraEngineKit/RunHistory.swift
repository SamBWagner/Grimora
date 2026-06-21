import Foundation
import GrimoraCore

/// What initiated a run. `cli` covers launchd-driven and ad-hoc terminal invocations unless
/// overridden via the `GRIMORA_RUN_TRIGGER` environment variable; `manual` is used by the app's
/// "Run now" button.
public enum EngineRunTrigger: String, Codable, Sendable, CaseIterable {
  case scheduled
  case manual
  case login
  case cli
}

/// Coarse phase of a run, with optional pipeline-stage detail while building.
public struct EngineRunProgress: Codable, Sendable, Equatable {
  public enum Phase: String, Codable, Sendable {
    case checking
    case downloading
    case building
    case publishing
  }

  public var phase: Phase
  /// Raw value of the underlying `CatalogPipelineProgress.Stage` while `phase == .building`.
  public var stage: String?
  /// Optional human sub-status, e.g. which file is downloading or which upload is in flight.
  public var detail: String?
  public var completed: Int
  public var total: Int?

  public init(
    phase: Phase,
    stage: String? = nil,
    detail: String? = nil,
    completed: Int = 0,
    total: Int? = nil
  ) {
    self.phase = phase
    self.stage = stage
    self.detail = detail
    self.completed = completed
    self.total = total
  }

  /// Fraction in 0...1 when a total is known, else nil (indeterminate).
  public var fractionCompleted: Double? {
    guard let total, total > 0 else { return nil }
    return min(1, max(0, Double(completed) / Double(total)))
  }
}

/// Snapshot of the in-flight run, persisted to `current-run.json` so other processes (the app) can
/// reflect a launchd-driven build live.
public struct CurrentRunStatus: Codable, Sendable, Equatable {
  public var runID: UUID
  public var trigger: EngineRunTrigger
  public var operation: EngineRunRecord.Operation
  public var startedAt: Date
  public var progress: EngineRunProgress
  public var updatedAt: Date

  public init(
    runID: UUID,
    trigger: EngineRunTrigger,
    operation: EngineRunRecord.Operation,
    startedAt: Date,
    progress: EngineRunProgress,
    updatedAt: Date
  ) {
    self.runID = runID
    self.trigger = trigger
    self.operation = operation
    self.startedAt = startedAt
    self.progress = progress
    self.updatedAt = updatedAt
  }
}

/// A completed (or failed) run, persisted to the run-history log.
public struct EngineRunRecord: Codable, Sendable, Identifiable, Equatable {
  public enum Operation: String, Codable, Sendable {
    case run
    case build
    case publish
  }

  public enum Outcome: String, Codable, Sendable {
    case succeeded
    case failed
    case skippedUnchanged
  }

  public var id: UUID
  public var trigger: EngineRunTrigger
  public var operation: Operation
  public var startedAt: Date
  public var finishedAt: Date?
  public var outcome: Outcome
  public var publishedVersion: String?
  public var sourceVersions: CatalogSourceVersions?
  public var counts: CatalogCounts?
  public var error: String?

  public init(
    id: UUID,
    trigger: EngineRunTrigger,
    operation: Operation,
    startedAt: Date,
    finishedAt: Date?,
    outcome: Outcome,
    publishedVersion: String?,
    sourceVersions: CatalogSourceVersions?,
    counts: CatalogCounts?,
    error: String?
  ) {
    self.id = id
    self.trigger = trigger
    self.operation = operation
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.outcome = outcome
    self.publishedVersion = publishedVersion
    self.sourceVersions = sourceVersions
    self.counts = counts
    self.error = error
  }

  public var duration: TimeInterval? {
    finishedAt.map { $0.timeIntervalSince(startedAt) }
  }
}

private enum EngineJSON {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

/// Append-only, capped log of runs stored as a JSON array (newest first) at `fileURL`.
public struct RunHistoryStore: Sendable {
  public let fileURL: URL
  public let limit: Int

  public init(fileURL: URL, limit: Int = 200) {
    self.fileURL = fileURL
    self.limit = max(1, limit)
  }

  /// Records, newest first.
  public func all() -> [EngineRunRecord] {
    guard let data = try? Data(contentsOf: fileURL),
      let records = try? EngineJSON.decoder.decode([EngineRunRecord].self, from: data)
    else {
      return []
    }
    return records
  }

  public func append(_ record: EngineRunRecord) {
    var records = all()
    records.removeAll { $0.id == record.id }
    records.insert(record, at: 0)
    if records.count > limit {
      records = Array(records.prefix(limit))
    }
    if let data = try? EngineJSON.encoder.encode(records) {
      try? data.write(to: fileURL, options: .atomic)
    }
  }
}

/// Reads/writes the single `current-run.json` describing the in-flight run.
public struct CurrentRunStatusStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func read() -> CurrentRunStatus? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? EngineJSON.decoder.decode(CurrentRunStatus.self, from: data)
  }

  public func write(_ status: CurrentRunStatus) {
    if let data = try? EngineJSON.encoder.encode(status) {
      try? data.write(to: fileURL, options: .atomic)
    }
  }

  public func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}
