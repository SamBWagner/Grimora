import Foundation

@testable import GrimoraCore

/// A deterministic in-memory stand-in for CloudKit's private database that models the
/// semantics the real `CKSyncEngine` transport depends on, so multi-device sync can be
/// proven correct without two iCloud-connected devices:
///
///  - **Server-side last-writer-wins.** The server keeps one canonical record per entity
///    id, retaining the newest by `updatedAt`. A stale write never regresses a newer
///    server value — exactly how the production `CloudSyncEntityCodec` merge behaves.
///  - **Eventual consistency.** `fetchRemoteState()` returns current server truth, but
///    `.remoteChangesAvailable` notifications are queued and only delivered when the test
///    calls ``deliverPendingNotifications()``. This lets a test interleave devices
///    deterministically the way real push delivery would.
///  - **Transient failures.** ``failNextSaves(_:)`` makes the next N saves throw, modelling
///    a `CKError.serverRecordChanged` / network blip, to prove queued local work is never
///    lost.
///
/// One instance represents the shared server; every device's `CloudSyncCoordinator`
/// shares the same instance, each with its own notification subscription.
actor SimulatedCloudKitTransport: CloudSyncTransport {
  private var entityRecords: [CloudSyncEntityRecord] = []
  private var recoverySnapshots: [CloudSyncRecoverySnapshot] = []
  private var requiredLibraryIdentity: LibraryIdentity?
  private var fallbackIdentity: LibraryIdentity
  private var eventContinuations: [UUID: AsyncStream<CloudSyncTransportEvent>.Continuation] = [:]
  private var pendingNotifications: [CloudSyncTransportEvent] = []
  private var remainingForcedFailures = 0
  private let account: String?

  private(set) var saveCount = 0

  init(
    fallbackIdentity: LibraryIdentity = LibraryIdentity(),
    accountIdentifier: String? = "simulated-icloud-account"
  ) {
    self.fallbackIdentity = fallbackIdentity
    self.account = accountIdentifier
  }

  // MARK: CloudSyncTransport

  func accountIdentifier() async throws -> String? {
    account
  }

  func eventStream() -> AsyncStream<CloudSyncTransportEvent> {
    let id = UUID()
    return AsyncStream { continuation in
      eventContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeEventContinuation(id: id) }
      }
    }
  }

  func fetchRemoteState() async throws -> CloudRemoteState {
    currentState()
  }

  func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws {
    if remainingForcedFailures > 0 {
      remainingForcedFailures -= 1
      throw SimulatedCloudKitError.transient
    }
    saveCount += 1
    self.requiredLibraryIdentity = requiredLibraryIdentity
    fallbackIdentity = requiredLibraryIdentity
    // Server-side last-writer-wins merge: existing canonical records win unless the
    // incoming record is strictly newer.
    entityRecords = CloudSyncEntityCodec.mergedRecords([
      entityRecords,
      try CloudSyncEntityCodec.records(from: snapshot),
    ])
    enqueueNotification(.remoteChangesAvailable)
  }

  func save(recoverySnapshots newSnapshots: [CloudSyncRecoverySnapshot]) async throws {
    recoverySnapshots = CloudSyncRecoveryPolicy.retained(recoverySnapshots + newSnapshots)
  }

  // MARK: Test control

  /// Makes the next `count` `save(snapshot:…)` calls throw a transient error.
  func failNextSaves(_ count: Int) {
    remainingForcedFailures = count
  }

  /// Flushes queued `.remoteChangesAvailable` notifications to every subscriber. Models
  /// CloudKit eventually delivering a push after a remote write.
  func deliverPendingNotifications() {
    let events = pendingNotifications
    pendingNotifications.removeAll()
    for event in events {
      for continuation in eventContinuations.values {
        continuation.yield(event)
      }
    }
  }

  /// The merged server truth, as the single canonical snapshot a device would download.
  func currentMergedSnapshot() -> DeviceSyncSnapshot? {
    try? CloudSyncEntityCodec.snapshot(from: entityRecords, fallbackIdentity: fallbackIdentity)
  }

  private func currentState() -> CloudRemoteState {
    let snapshot = try? CloudSyncEntityCodec.snapshot(
      from: entityRecords,
      fallbackIdentity: fallbackIdentity
    )
    return CloudRemoteState(
      requiredLibraryIdentity: requiredLibraryIdentity,
      snapshots: snapshot.map { [$0] } ?? [],
      recoverySnapshots: recoverySnapshots
    )
  }

  private func enqueueNotification(_ event: CloudSyncTransportEvent) {
    pendingNotifications.append(event)
  }

  private func removeEventContinuation(id: UUID) {
    eventContinuations[id] = nil
  }
}

enum SimulatedCloudKitError: Error, Equatable {
  case transient
}
