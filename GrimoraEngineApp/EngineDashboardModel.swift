import Foundation
import GrimoraCore
import GrimoraEngineKit
import Observation

/// Observable state for the dashboard. Polls the shared engine state so both in-process runs and
/// launchd-driven runs are reflected live.
@MainActor
@Observable
final class EngineDashboardModel {
  enum Activity: Equatable {
    case idle
    case running(EngineRunProgress)
  }

  /// Result of a "Check for Updates" probe against the data sources.
  struct CheckResult: Equatable {
    var check: CatalogUpdateCheck
    var checkedAt: Date
  }

  private let controller: EngineController
  private let pollInterval: Duration

  private(set) var activity: Activity = .idle
  private(set) var history: [EngineRunRecord] = []
  private(set) var schedule = EngineSchedule(
    label: EngineSchedule.defaultLabel,
    isInstalled: false,
    runAtLoad: false,
    entries: [],
    environment: [:]
  )
  private(set) var nextScheduledRun: Date?
  private(set) var lastState = EngineState()
  private(set) var localBuild: LocalBuildInfo?
  private(set) var runErrorMessage: String?
  private(set) var isStartingRun = false
  private(set) var isChecking = false
  private(set) var lastCheck: CheckResult?
  /// The operation currently running, used to choose which steps the stepper shows.
  private(set) var activeOperation: EngineRunRecord.Operation?

  var isBusy: Bool {
    if case .running = activity { return true }
    return isStartingRun
  }

  var canPublish: Bool {
    localBuild != nil && !isBusy
  }

  init(controller: EngineController, pollInterval: Duration = .seconds(2)) {
    self.controller = controller
    self.pollInterval = pollInterval
  }

  /// Continuously refreshes until the surrounding `.task` is cancelled.
  func startPolling() async {
    while !Task.isCancelled {
      await refresh()
      try? await Task.sleep(for: pollInterval)
    }
  }

  func refresh() async {
    let controller = controller
    let snapshot = await Task.detached { controller.snapshot() }.value

    history = snapshot.history
    schedule = snapshot.schedule
    nextScheduledRun = snapshot.nextScheduledRun
    lastState = snapshot.state
    localBuild = snapshot.localBuild

    // Don't let polling overwrite the live progress of a run we started in-process.
    if isStartingRun { return }

    if snapshot.isRunning {
      activity = .running(snapshot.currentRun?.progress ?? EngineRunProgress(phase: .checking))
      activeOperation = snapshot.currentRun?.operation ?? activeOperation
    } else {
      activity = .idle
      activeOperation = nil
    }
  }

  /// Build the catalog locally without publishing.
  func build(force: Bool) async {
    await performAction(.build) { progress in
      try await self.controller.build(force: force, progress: progress)
    }
  }

  /// Publish the most recent local build.
  func publish() async {
    await performAction(.publish) { progress in
      try await self.controller.publishLast(progress: progress)
    }
  }

  /// Build and publish in one step.
  func buildAndPublish(force: Bool) async {
    await performAction(.run) { progress in
      _ = try await self.controller.buildAndPublish(force: force, progress: progress)
    }
  }

  /// Shared lifecycle around an in-process operation: guards against concurrent runs, surfaces
  /// live progress, records errors, and refreshes afterwards.
  private func performAction(
    _ operation: EngineRunRecord.Operation,
    _ body: @escaping (@escaping EngineProgressHandler) async throws -> Void
  ) async {
    guard !isBusy else { return }
    isStartingRun = true
    activeOperation = operation
    runErrorMessage = nil
    activity = .running(EngineRunProgress(phase: operation == .publish ? .publishing : .checking))

    do {
      try await body { [weak self] progress in
        await MainActor.run { self?.activity = .running(progress) }
      }
    } catch {
      runErrorMessage = String(describing: error)
    }

    isStartingRun = false
    activity = .idle
    activeOperation = nil
    await refresh()
  }

  func checkForUpdates() async {
    guard !isChecking else { return }
    isChecking = true
    runErrorMessage = nil
    defer { isChecking = false }

    do {
      let result = try await controller.checkForUpdate()
      lastCheck = CheckResult(check: result, checkedAt: Date())
    } catch {
      runErrorMessage = String(describing: error)
    }
  }
}
