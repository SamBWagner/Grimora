import Foundation
import GrimoraCore
import GrimoraEngineKit

/// Describes the most recent local build present on disk (built but not necessarily published).
struct LocalBuildInfo: Sendable, Equatable {
  var version: String
  var directory: URL
  /// The uncompressed SQLite database, available for inspection before publishing.
  var databaseURL: URL
  var isPublished: Bool
}

/// An immutable view of the engine's shared on-disk state at one moment in time.
struct EngineSnapshot: Sendable {
  var state: EngineState
  var history: [EngineRunRecord]
  var currentRun: CurrentRunStatus?
  var isRunning: Bool
  var schedule: EngineSchedule
  var nextScheduledRun: Date?
  var localBuild: LocalBuildInfo?
}

/// Bridges the SwiftUI layer to `GrimoraEngineKit`.
///
/// It runs builds in-process and reads the same state files the launchd CLI writes, so the
/// dashboard reflects scheduled runs too. The engine environment is seeded from the installed
/// launch agent so an in-process publish targets the same Tigris buckets — nothing is hardcoded
/// here. Kept as a small `Sendable` value so future variants (e.g. a remote control surface) can
/// slot in behind the same shape.
struct EngineController: Sendable {
  private let environment: [String: String]

  init() {
    var environment = ProcessInfo.processInfo.environment
    // Fill any missing engine config (Tigris buckets, public base URL) from the installed agent.
    for (key, value) in EngineSchedule.load().environment where environment[key] == nil {
      environment[key] = value
    }
    self.environment = environment
  }

  private func makeEngine() throws -> GrimoraDataEngine {
    try GrimoraDataEngine(environment: environment)
  }

  /// Reads all observable state in one pass. Safe to call off the main actor.
  func snapshot() -> EngineSnapshot {
    let schedule = EngineSchedule.load()
    guard let engine = try? makeEngine() else {
      return EngineSnapshot(
        state: EngineState(),
        history: [],
        currentRun: nil,
        isRunning: false,
        schedule: schedule,
        nextScheduledRun: schedule.nextRunDate(),
        localBuild: nil
      )
    }
    let state = engine.loadState()
    let localBuild = engine.lastLocalBuild().map { build in
      LocalBuildInfo(
        version: build.manifest.version,
        directory: build.directory,
        databaseURL: build.directory.appendingPathComponent("catalog.sqlite"),
        isPublished: state.lastPublishedVersion == build.manifest.version
      )
    }
    return EngineSnapshot(
      state: state,
      history: engine.loadRunHistory(),
      currentRun: engine.currentRun(),
      isRunning: engine.isRunning(),
      schedule: schedule,
      nextScheduledRun: schedule.nextRunDate(),
      localBuild: localBuild
    )
  }

  /// Builds the catalog locally (no publish), forwarding live progress.
  func build(force: Bool, progress: @escaping EngineProgressHandler) async throws {
    _ = try await makeEngine().build(force: force, trigger: .manual, progress: progress)
  }

  /// Publishes the most recent local build, forwarding live progress.
  func publishLast(progress: @escaping EngineProgressHandler) async throws {
    try await makeEngine().publishLastBuild(trigger: .manual, progress: progress)
  }

  /// Runs a build + publish in-process, forwarding live progress.
  @discardableResult
  func buildAndPublish(
    force: Bool,
    progress: @escaping EngineProgressHandler
  ) async throws -> EngineRunRecord.Outcome {
    try await makeEngine().run(force: force, trigger: .manual, progress: progress)
  }

  /// Pings the data sources (Scryfall + MTGJSON) and reports, per source, whether they changed since
  /// the last successful build. Does not acquire the build lock or modify any state.
  func checkForUpdate() async throws -> CatalogUpdateCheck {
    try await makeEngine().checkForUpdate()
  }
}
