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

  // MARK: - The reported bug: a lagging-clock device's edits must not revert

  /// Reproduces "it syncs across, then keeps re-writing my list back to what it was."
  ///
  /// Device B's wall clock runs far behind Device A's. With a raw wall-clock last-writer-wins
  /// merge, B can never stamp an edit newer than what it just pulled from A, so B's edits lose
  /// the merge on every sync and the list is locked to A's version forever. The logical clock
  /// advances B past the newest instant it observes from A on each pull, so B's subsequent edits
  /// win — which is what this test proves.
  func testLaggingClockDeviceEditsAreNotReverted() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iMac", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPhone", transport: transport)

    // A's wall clock is ~11 days ahead of B's — the kind of skew that makes B always lose.
    var aTick = 0.0
    func aNow() -> Date {
      aTick += 1
      return Date(timeIntervalSince1970: 1_000_000 + aTick)
    }
    var bTick = 0.0
    func bNow() -> Date {
      bTick += 1
      return Date(timeIntervalSince1970: 10 + bTick)
    }

    // A creates a list and publishes it; B pulls it down.
    let list = try deviceA.database.createCardCollection(named: "Architect", now: aNow())
    try deviceA.database.appendCard("alpha", toList: list.id, now: aNow())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "seed")
    try await settle([deviceA, deviceB])
    XCTAssertTrue(
      try deviceB.database.cardCollections().contains { $0.id == list.id },
      "Device B should have received the shared list."
    )

    // B edits on its lagging clock — timestamps far *below* A's — then syncs.
    try deviceB.database.renameCardCollection(id: list.id, to: "Architect (B)", now: bNow())
    try deviceB.database.appendCard("beta", toList: list.id, now: bNow())
    try deviceB.database.recordLocalSyncSnapshotChange(reason: "b-edit")
    try await settle([deviceA, deviceB])

    // B's edits must survive on *both* devices rather than reverting to A's version.
    try assertConverged([deviceA, deviceB])
    for device in [deviceA, deviceB] {
      XCTAssertEqual(
        try device.database.cardCollections().first { $0.id == list.id }?.name,
        "Architect (B)",
        "\(device.name) reverted B's rename — the lagging device lost the merge."
      )
      let cards = Set(try device.database.cardCollectionEntries(forListID: list.id).map(\.cardID))
      XCTAssertTrue(cards.isSuperset(of: ["alpha", "beta"]), "\(device.name) lost an add: \(cards)")
    }

    // The report's loop: B keeps editing at lagging timestamps and each edit must stick.
    for round in 0..<5 {
      try deviceB.database.renameCardCollection(id: list.id, to: "Round \(round)", now: bNow())
      try deviceB.database.recordLocalSyncSnapshotChange(reason: "round-\(round)")
      try await settle([deviceA, deviceB])
      try assertConverged([deviceA, deviceB])
      for device in [deviceA, deviceB] {
        XCTAssertEqual(
          try device.database.cardCollections().first { $0.id == list.id }?.name,
          "Round \(round)",
          "\(device.name) reverted B's round-\(round) rename."
        )
      }
    }
  }

  /// A printing swap (and other content-only entry edits) must actually propagate. These paths
  /// historically changed the row without bumping its `updatedAt`, so after the upload diff
  /// started skipping unchanged rows the edit silently stopped syncing.
  func testPrintingSwapPropagatesAcrossDevices() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let list = try deviceA.database.createCardCollection(named: "Deck", now: nextDate())
    let entry = try deviceA.database.appendCard("sol-ring-a", toList: list.id, now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "seed")
    try await settle([deviceA, deviceB])

    // A swaps the printing; the entry keeps its id but points at a different card.
    _ = try deviceA.database.replaceCardCollectionEntryPrint(
      id: entry.id, withCardID: "sol-ring-b", now: nextDate()
    )
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "swap-print")
    try await settle([deviceA, deviceB])

    try assertConverged([deviceA, deviceB])
    for device in [deviceA, deviceB] {
      XCTAssertEqual(
        try device.database.cardCollectionEntries(forListID: list.id).map(\.cardID),
        ["sol-ring-b"],
        "\(device.name) did not receive the printing swap."
      )
    }
  }

  // MARK: - The change ledger unions across devices

  /// The append-only change ledger syncs as a pure union: every device's history survives on
  /// every device, pulling never drops or rewrites a peer's entries, and provenance is kept.
  func testChangeLedgerUnionsAcrossDevices() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let list = try deviceA.database.createCardCollection(named: "Deck", now: nextDate())
    try await settle([deviceA, deviceB])

    // Each device performs a distinct, ledger-logged action before syncing.
    try deviceA.database.appendCard("alpha", toList: list.id, now: nextDate())
    _ = try deviceB.database.appendCard("beta", toList: list.id, now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "a")
    try deviceB.database.recordLocalSyncSnapshotChange(reason: "b")
    try await settle([deviceA, deviceB])

    try assertConverged([deviceA, deviceB])

    let ledgerA = try deviceA.database.changeLogEntries()
    let ledgerB = try deviceB.database.changeLogEntries()
    XCTAssertEqual(Set(ledgerA.map(\.id)), Set(ledgerB.map(\.id)), "Ledgers did not converge")

    let actions = ledgerA.map(\.action)
    XCTAssertTrue(actions.contains(ChangeLogAction.createList), "createList missing: \(actions)")
    XCTAssertEqual(
      actions.filter { $0 == ChangeLogAction.addCard }.count, 2,
      "Both devices' addCard events should survive the union, got \(actions)"
    )
    // Provenance is preserved: the two adds originated on two different devices.
    let addDevices = Set(
      ledgerA.filter { $0.action == ChangeLogAction.addCard }.map(\.deviceID)
    )
    XCTAssertEqual(addDevices.count, 2, "Each add should retain its origin device id")
  }

  // MARK: - A large ledger stays bounded per sync and never re-uploads settled rows

  /// The ledger grows without bound, but a single sync must not re-serialize and re-upload the whole
  /// history every time. This proves both halves of the retention design: the outbound snapshot
  /// carries only the newest `changeLogSyncSnapshotLimit` rows (bounded per-sync work; full history
  /// stays in the local DB), and rows CloudKit already holds are never flagged for re-upload because
  /// ledger rows are immutable and id-keyed.
  func testLargeChangeLedgerBoundsSyncSnapshotAndSkipsReupload() throws {
    let database = try Fixtures.database()
    try database.saveLibraryIdentity(
      LibraryIdentity(defaultCardsUpdatedAt: "2026-04-25T09:09:59.477+00:00")
    )
    let list = try database.createCardCollection(named: "Deck", now: nextDate())
    let entry = try database.appendCard("alpha", toList: list.id, now: nextDate())

    // Log far more actions than a single sync should ever carry.
    let overflow = CardDatabase.changeLogSyncSnapshotLimit + 25
    for quantity in 2...(overflow + 1) {
      _ = try database.setCardCollectionEntryQuantity(
        id: entry.id, quantity: quantity, now: nextDate()
      )
    }

    // The local ledger keeps every row for history...
    let fullLedger = try database.changeLogEntries()
    XCTAssertGreaterThan(fullLedger.count, CardDatabase.changeLogSyncSnapshotLimit)

    // ...but a sync snapshot carries only the newest N, so per-sync work stays bounded.
    let settings = SyncSearchSettings(updatedAt: .distantPast)
    let snapshot = try database.deviceSyncSnapshot(
      deviceID: "device-a", deviceName: "iPhone", searchSettings: settings
    )
    XCTAssertEqual(snapshot.changeLog.count, CardDatabase.changeLogSyncSnapshotLimit)
    XCTAssertEqual(
      Set(snapshot.changeLog.map(\.id)),
      Set(fullLedger.prefix(CardDatabase.changeLogSyncSnapshotLimit).map(\.id)),
      "The snapshot must carry the most-recent rows, not an arbitrary slice."
    )

    // Model the server already holding those rows from a prior sync. A second sync of the same
    // state must flag none of them for re-upload — the whole point of the immutable ledger.
    let known = Dictionary(
      try CloudSyncEntityCodec.records(from: snapshot).map {
        ($0.id, CloudSyncUploadDiff.KnownRecord(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt))
      },
      uniquingKeysWith: { first, _ in first }
    )
    let secondSnapshot = try database.deviceSyncSnapshot(
      deviceID: "device-a", deviceName: "iPhone", searchSettings: settings
    )
    let ledgerNeedingReupload = try CloudSyncEntityCodec.records(from: secondSnapshot).filter {
      $0.entityType == .changeLogEntry
        && CloudSyncUploadDiff.needsUpload(
          updatedAt: $0.updatedAt, deletedAt: $0.deletedAt, known: known[$0.id]
        )
    }
    XCTAssertTrue(
      ledgerNeedingReupload.isEmpty,
      "Settled ledger rows must not re-upload, found \(ledgerNeedingReupload.count)."
    )
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

  // MARK: - A ruleset change re-zones entries and consolidates categories on every device

  /// Flipping a list from Commander to Collection re-homes command-zone entries into the mainboard
  /// and folds a duplicate-named command-zone category into its mainboard twin, deleting the now
  /// redundant category. Both halves must propagate: the re-zoned entry rows have to bump
  /// `updated_at` (or the upload diff skips them) and the deleted category needs a tombstone (or it
  /// resurrects from the other device's union merge — and drags its entries back with it).
  func testRulesetChangeNormalizationPropagatesAndTombstonesConsolidatedCategory() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    // A Commander deck with a "Ramp" category in both the command zone and the mainboard, plus a
    // bare (uncategorized) command-zone entry.
    let deck = try deviceA.database.createCardCollection(
      named: "Deck", ruleset: .commander, now: nextDate()
    )
    let mainRamp = try deviceA.database.createCardCollectionCategory(
      inList: deck.id, zone: .mainboard, named: "Ramp", now: nextDate()
    )
    let commandRamp = try deviceA.database.createCardCollectionCategory(
      inList: deck.id, zone: .commander, named: "Ramp", now: nextDate()
    )
    try deviceA.database.appendCard(
      "sol-ring", toList: deck.id, zone: .commander, categoryID: commandRamp.id, now: nextDate()
    )
    try deviceA.database.appendCard(
      "llanowar-elves", toList: deck.id, zone: .mainboard, categoryID: mainRamp.id, now: nextDate()
    )
    try deviceA.database.appendCard(
      "golos", toList: deck.id, zone: .commander, now: nextDate()
    )
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "seed")
    try await settle([deviceA, deviceB])

    // Sanity: B received the full Commander shape before the ruleset flip.
    XCTAssertEqual(
      Set(try deviceB.database.cardCollectionCategories(forListID: deck.id).map(\.id)),
      [mainRamp.id, commandRamp.id]
    )

    // A flips the deck to a plain Collection. Normalization folds the command-zone "Ramp" into the
    // mainboard "Ramp" (deleting the former) and moves every command-zone entry to the mainboard.
    _ = try deviceA.database.setCardCollectionRuleset(id: deck.id, ruleset: .none, now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "ruleset")
    try await settle([deviceA, deviceB])

    try assertConverged([deviceA, deviceB])
    for device in [deviceA, deviceB] {
      let categories = try device.database.cardCollectionCategories(forListID: deck.id)
      XCTAssertEqual(
        categories.map(\.id), [mainRamp.id],
        "\(device.name) should keep only the mainboard Ramp category, got \(categories.map(\.name))."
      )
      XCTAssertFalse(
        categories.contains { $0.id == commandRamp.id },
        "\(device.name) resurrected the consolidated command-zone category."
      )
      let entries = try device.database.cardCollectionEntries(forListID: deck.id)
      XCTAssertTrue(
        entries.allSatisfy { $0.zone == .mainboard },
        "\(device.name) left an entry in a now-illegal zone: "
          + "\(entries.map { "\($0.cardID):\($0.zone.rawValue)" })"
      )
      XCTAssertEqual(
        entries.first { $0.cardID == "sol-ring" }?.categoryID, mainRamp.id,
        "\(device.name) lost the consolidated entry's new mainboard category."
      )
    }
  }

  // MARK: - Reordering collections syncs the new order to every device

  /// Dragging a collection to a new position renumbers *every* sibling's `position`, not just the
  /// moved one. Those sibling rewrites must bump `updated_at` or the upload diff skips them and the
  /// new order never reaches the other device.
  func testCollectionReorderPropagatesAcrossDevices() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let first = try deviceA.database.createCardCollection(named: "First", now: nextDate())
    let second = try deviceA.database.createCardCollection(named: "Second", now: nextDate())
    let third = try deviceA.database.createCardCollection(named: "Third", now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "seed")
    try await settle([deviceA, deviceB])

    let mine: Set<String> = [first.id, second.id, third.id]
    func orderedIDs(_ device: Device) throws -> [String] {
      try device.database.cardCollections().map(\.id).filter { mine.contains($0) }
    }
    XCTAssertEqual(try orderedIDs(deviceA), [first.id, second.id, third.id])
    XCTAssertEqual(try orderedIDs(deviceB), [first.id, second.id, third.id])

    // A drags "Third" to the front, shifting First and Second down by one.
    _ = try deviceA.database.moveCardCollection(id: third.id, toPosition: 0, now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "reorder")
    try await settle([deviceA, deviceB])

    XCTAssertEqual(
      try orderedIDs(deviceA), [third.id, first.id, second.id],
      "The reorder did not take on the originating device."
    )
    XCTAssertEqual(
      try orderedIDs(deviceB), [third.id, first.id, second.id],
      "Device B never received the reordered sibling positions."
    )
    try assertConverged([deviceA, deviceB])
  }

  // MARK: - Merging a duplicate entry must not resurrect the source from another device

  /// Swapping an entry's printing onto a card that already has an entry merges the two rows: the
  /// existing entry absorbs the quantity and the source row is deleted. That deletion needs a
  /// tombstone, or the source entry — still present on the other device — resurrects on the next
  /// union merge, re-creating the very duplicate the merge removed.
  func testDuplicateMergeDeletionDoesNotResurrectAcrossDevices() async throws {
    let transport = SimulatedCloudKitTransport()
    let deviceA = try makeDevice(id: "device-a", name: "iPhone", transport: transport)
    let deviceB = try makeDevice(id: "device-b", name: "iPad", transport: transport)

    let list = try deviceA.database.createCardCollection(named: "Deck", now: nextDate())
    let source = try deviceA.database.appendCard("sol-ring-a", toList: list.id, now: nextDate())
    _ = try deviceA.database.appendCard("sol-ring-b", toList: list.id, now: nextDate())
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "seed")
    try await settle([deviceA, deviceB])

    XCTAssertEqual(
      Set(try deviceB.database.cardCollectionEntries(forListID: list.id).map(\.cardID)),
      ["sol-ring-a", "sol-ring-b"]
    )

    // A re-prints the "sol-ring-a" entry as "sol-ring-b"; it collides with the existing
    // "sol-ring-b" entry, so the two merge and the "sol-ring-a" source row is deleted.
    _ = try deviceA.database.replaceCardCollectionEntryPrint(
      id: source.id, withCardID: "sol-ring-b", now: nextDate()
    )
    try deviceA.database.recordLocalSyncSnapshotChange(reason: "merge-print")
    try await settle([deviceA, deviceB])

    try assertConverged([deviceA, deviceB])
    for device in [deviceA, deviceB] {
      let entries = try device.database.cardCollectionEntries(forListID: list.id)
      XCTAssertEqual(
        entries.map(\.cardID), ["sol-ring-b"],
        "\(device.name) kept the merged-away source entry: \(entries.map(\.cardID))"
      )
      XCTAssertFalse(
        entries.contains { $0.id == source.id },
        "\(device.name) resurrected the deleted source entry id."
      )
      XCTAssertEqual(
        entries.first?.quantity, 2,
        "\(device.name) lost the merged quantity."
      )
    }
  }
}
