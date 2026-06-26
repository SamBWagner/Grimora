import XCTest

@testable import GrimoraCore

/// Multi-device convergence proofs for the CloudKit single-source-of-truth model.
///
/// These tests stand in for two iCloud-connected devices: each "device" is an in-memory
/// `CardDatabase` + `CloudSyncCoordinator` sharing one ``SimulatedCloudKitTransport``.
/// They assert the two properties the user's data safety depends on:
///   1. Steady-state editing never errors out mid-convergence (the interactive
///      "which copy?" resolution flow that made the app unusable was removed, so the
///      `.resolving` status no longer exists — the type system now enforces that too).
///   2. Arbitrary interleavings of edits across devices converge to identical libraries
///      with no last-written change lost.
final class CloudSyncConvergenceTests: XCTestCase {
  private struct Device {
    let id: String
    let name: String
    let database: CardDatabase
    let coordinator: CloudSyncCoordinator
  }

  private var clockTick: TimeInterval = 0
  private func nextDate() -> Date {
    clockTick += 1
    return Date(timeIntervalSince1970: clockTick)
  }

  private func makeDevice(
    id: String,
    name: String,
    transport: SimulatedCloudKitTransport,
    bootstrapResolved: Bool = true
  ) throws -> Device {
    let database = try Fixtures.database()
    try database.saveLibraryIdentity(
      LibraryIdentity(defaultCardsUpdatedAt: "2026-04-25T09:09:59.477+00:00")
    )
    if bootstrapResolved {
      try database.markCloudSyncBootstrapResolved(true)
    }
    return Device(
      id: id,
      name: name,
      database: database,
      coordinator: CloudSyncCoordinator(database: database, transport: transport)
    )
  }

  /// A semantic fingerprint of a library that ignores timestamps and ordering so two
  /// devices that have converged compare equal.
  private func signature(of database: CardDatabase) throws -> String {
    try database.cardCollections()
      .sorted { $0.id < $1.id }
      .map { list in
        let entries = try database.cardCollectionEntries(forListID: list.id)
          .map { "\($0.cardID)|\($0.zone.rawValue)|\($0.categoryID ?? "")|\($0.quantity)" }
          .sorted()
        return "\(list.id):\(list.name):[\(entries.joined(separator: ","))]"
      }
      .joined(separator: ";")
  }

  /// Runs rounds of every device pushing then pulling until the shared library is
  /// stable. Returns every status produced so callers can assert the run stayed healthy.
  @discardableResult
  private func settle(_ devices: [Device], rounds: Int = 5) async throws -> [CloudSyncStatus] {
    var statuses: [CloudSyncStatus] = []
    for _ in 0..<rounds {
      for device in devices {
        statuses.append(
          await device.coordinator.pushLocalState(
            deviceID: device.id,
            deviceName: device.name,
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
          )
        )
        statuses.append(
          await device.coordinator.reconcileRemoteState(
            deviceID: device.id,
            deviceName: device.name,
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
          )
        )
      }
    }
    return statuses
  }

  private func assertConverged(_ devices: [Device], file: StaticString = #filePath, line: UInt = #line) throws {
    let signatures = try devices.map { try signature(of: $0.database) }
    for signature in signatures.dropFirst() {
      XCTAssertEqual(signature, signatures[0], "Devices did not converge", file: file, line: line)
    }
  }

  private func assertNoSyncFailure(_ statuses: [CloudSyncStatus], file: StaticString = #filePath, line: UInt = #line) {
    for status in statuses {
      if case .failed(let message) = status {
        XCTFail("Sync should not fail during convergence: \(message)", file: file, line: line)
      }
    }
  }

  // MARK: - The regression: repeated edits after a same-id divergence

  func testRepeatedEditsAfterSameIdDivergenceNeverPrompt() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    // Both devices start out sharing one list with the same id (as a link-import that
    // preserves the original list's UUID would produce).
    let shared = try deviceA.database.createCardCollection(named: "Architect", now: nextDate())
    try deviceA.database.appendCard("alpha", toList: shared.id, now: nextDate())
    try await settle([deviceA, deviceB])
    XCTAssertTrue(
      try deviceB.database.cardCollections().contains { $0.id == shared.id },
      "Device B should have received the shared list."
    )

    // Now both edit the same list incompatibly before syncing — a genuine divergence.
    try deviceA.database.renameCardCollection(id: shared.id, to: "Architect (mine)", now: nextDate())
    try deviceA.database.appendCard("beta", toList: shared.id, now: nextDate())
    try deviceB.database.appendCard("gamma", toList: shared.id, now: nextDate())

    // Repeatedly edit on A the way the bug report describes (add a card, sync, repeat).
    var statuses: [CloudSyncStatus] = []
    for _ in 0..<5 {
      try deviceA.database.appendCard("alpha", toList: shared.id, now: nextDate())
      try deviceA.database.recordLocalSyncSnapshotChange(reason: "add-card")
      statuses.append(
        await deviceA.coordinator.pushLocalState(
          deviceID: deviceA.id,
          deviceName: deviceA.name,
          searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )
      )
    }
    statuses += try await settle([deviceA, deviceB])

    // Sync must stay healthy across all those edits (the interactive prompt that made
    // the app unusable is gone)...
    assertNoSyncFailure(statuses)
    // ...and both devices must end up identical.
    try assertConverged([deviceA, deviceB])

    // The independent additions from each device survive the merge (entry union).
    let entries = Set(
      try deviceA.database.cardCollectionEntries(forListID: shared.id).map(\.cardID)
    )
    XCTAssertTrue(entries.isSuperset(of: ["beta", "gamma"]), "Both devices' adds must survive, got \(entries)")
  }

  // MARK: - Bootstrap with a same-id divergence also never prompts

  func testBootstrapWithSameIdDivergenceMergesWithoutPrompt() async throws {
    let transport = SimulatedCloudKitTransport()
    // Device A has already published a list.
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let shared = try deviceA.database.createCardCollection(named: "Architect", now: nextDate())
    try deviceA.database.appendCard("alpha", toList: shared.id, now: nextDate())
    _ = await deviceA.coordinator.pushLocalState(
      deviceID: deviceA.id,
      deviceName: deviceA.name,
      searchSettings: SyncSearchSettings(updatedAt: .distantPast)
    )

    // Device B joins for the first time (bootstrap NOT resolved) carrying a divergent
    // copy of the same list id.
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport, bootstrapResolved: false)
    try deviceB.database.restoreCardCollectionLibrarySnapshot(
      CardCollectionLibrarySnapshot(
        lists: [
          CardCollectionRecord(id: shared.id, name: "Architect", createdAt: nextDate(), updatedAt: nextDate())
        ],
        categories: [],
        entries: [
          CardCollectionEntryRecord(id: "b-entry", listID: shared.id, cardID: "gamma", position: 0, createdAt: nextDate())
        ]
      )
    )

    let startStatus = await deviceB.coordinator.start(
      deviceID: deviceB.id,
      deviceName: deviceB.name,
      searchSettings: SyncSearchSettings(updatedAt: .distantPast)
    )
    assertNoSyncFailure([startStatus])

    let statuses = try await settle([deviceA, deviceB])
    assertNoSyncFailure(statuses)
    try assertConverged([deviceA, deviceB])
  }

  // MARK: - Concurrent independent adds are unioned

  func testConcurrentDifferentCardAddsAreUnioned() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let list = try deviceA.database.createCardCollection(named: "Deck", now: nextDate())
    try await settle([deviceA, deviceB])

    // Same list, different cards added concurrently before either syncs.
    try deviceA.database.appendCard("alpha", toList: list.id, now: nextDate())
    try deviceB.database.appendCard("beta", toList: list.id, now: nextDate())
    let statuses = try await settle([deviceA, deviceB])

    assertNoSyncFailure(statuses)
    try assertConverged([deviceA, deviceB])
    XCTAssertEqual(
      Set(try deviceA.database.cardCollectionEntries(forListID: list.id).map(\.cardID)),
      ["alpha", "beta"]
    )
  }

  // MARK: - Delete-versus-edit resolves to the newest action

  func testDeleteVersusEditResolvesToNewestActionAndConverges() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let list = try deviceA.database.createCardCollection(named: "Temp", now: nextDate())
    try deviceA.database.appendCard("alpha", toList: list.id, now: nextDate())
    try await settle([deviceA, deviceB])

    // A edits the list; B deletes it strictly later. Newest action (delete) wins.
    try deviceA.database.appendCard("beta", toList: list.id, now: nextDate())
    try deviceB.database.deleteCardCollection(id: list.id)
    let deleteDate = nextDate()
    try deviceB.database.recordLocalSyncSnapshotChange(reason: "delete")
    _ = deleteDate

    let statuses = try await settle([deviceA, deviceB])
    assertNoSyncFailure(statuses)
    try assertConverged([deviceA, deviceB])
    XCTAssertFalse(
      try deviceA.database.cardCollections().contains { $0.id == list.id },
      "The later deletion should win on every device."
    )
  }

  // MARK: - A transient save failure never loses queued work

  func testTransientSaveFailureRetainsOutboxThenConverges() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let list = try deviceA.database.createCardCollection(named: "Resilient", now: nextDate())
    try deviceA.database.appendCard("alpha", toList: list.id, now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "create")

    // The next save fails (network blip / serverRecordChanged).
    await transport.failNextSaves(1)
    let failedStatus = await deviceA.coordinator.pushLocalState(
      deviceID: deviceA.id,
      deviceName: deviceA.name,
      searchSettings: SyncSearchSettings(updatedAt: .distantPast)
    )
    XCTAssertEqual(failedStatus, .failed("Sync failed. Grimora will try again later."))
    XCTAssertEqual(
      try deviceA.database.pendingSyncChanges().count,
      1,
      "A failed save must keep the work queued."
    )

    // The next attempt succeeds and everything converges with no data lost.
    let statuses = try await settle([deviceA, deviceB])
    assertNoSyncFailure(statuses)
    try assertConverged([deviceA, deviceB])
    XCTAssertEqual(
      Set(try deviceB.database.cardCollections().map(\.name)),
      ["Resilient"]
    )
  }

  // MARK: - Interleaved multi-device editing converges

  func testThreeDevicesInterleavedEditsConverge() async throws {
    let transport = SimulatedCloudKitTransport()
    let devices = try [
      makeDevice(id: "device-a", name: "iPhone", transport: transport),
      makeDevice(id: "device-b", name: "iPad", transport: transport),
      makeDevice(id: "device-c", name: "Mac", transport: transport),
    ]

    // Seed a shared list from device A.
    let list = try devices[0].database.createCardCollection(named: "Shared", now: nextDate())
    try await settle(devices)

    // A fixed, deterministic interleaving of edits across all three devices.
    let cards = ["alpha", "beta", "gamma"]
    let script: [(device: Int, card: String)] = [
      (0, "alpha"), (1, "beta"), (2, "gamma"),
      (1, "alpha"), (0, "gamma"), (2, "beta"),
      (2, "alpha"), (0, "beta"), (1, "gamma"),
    ]
    var statuses: [CloudSyncStatus] = []
    for step in script {
      let device = devices[step.device]
      try device.database.appendCard(step.card, toList: list.id, now: nextDate())
      try device.database.recordLocalSyncSnapshotChange(reason: "edit")
      statuses.append(
        await device.coordinator.pushLocalState(
          deviceID: device.id,
          deviceName: device.name,
          searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )
      )
      // A different device pulls in between, modelling staggered delivery.
      let puller = devices[(step.device + 1) % devices.count]
      statuses.append(
        await puller.coordinator.reconcileRemoteState(
          deviceID: puller.id,
          deviceName: puller.name,
          searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )
      )
      _ = cards
    }

    statuses += try await settle(devices)
    assertNoSyncFailure(statuses)
    try assertConverged(devices)
  }
}
