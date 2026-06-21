import Foundation
import GrimoraCore
import Testing
import GrimoraEngineKit

private func temporaryURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("\(name)-\(UUID().uuidString).json")
}

private func makeRecord(
  trigger: EngineRunTrigger = .manual,
  outcome: EngineRunRecord.Outcome = .succeeded,
  startedAt: Date = Date()
) -> EngineRunRecord {
  EngineRunRecord(
    id: UUID(),
    trigger: trigger,
    operation: .run,
    startedAt: startedAt,
    finishedAt: startedAt.addingTimeInterval(90),
    outcome: outcome,
    publishedVersion: "v1-test",
    sourceVersions: nil,
    counts: CatalogCounts(cards: 1, priceSeries: 2),
    error: nil
  )
}

@Test
func runHistoryStoresNewestFirstAndCaps() {
  let url = temporaryURL("runs")
  defer { try? FileManager.default.removeItem(at: url) }
  let store = RunHistoryStore(fileURL: url, limit: 3)

  let base = Date(timeIntervalSince1970: 0)
  let first = makeRecord(startedAt: base)
  let second = makeRecord(startedAt: base.addingTimeInterval(10))
  store.append(first)
  store.append(second)

  #expect(store.all().map(\.id) == [second.id, first.id])

  // Exceeding the limit drops the oldest entries.
  let third = makeRecord(startedAt: base.addingTimeInterval(20))
  let fourth = makeRecord(startedAt: base.addingTimeInterval(30))
  store.append(third)
  store.append(fourth)
  let ids = store.all().map(\.id)
  #expect(ids.count == 3)
  #expect(ids.first == fourth.id)
  #expect(!ids.contains(first.id))
}

@Test
func currentRunStatusRoundTripsAndClears() {
  let url = temporaryURL("current-run")
  defer { try? FileManager.default.removeItem(at: url) }
  let store = CurrentRunStatusStore(fileURL: url)
  #expect(store.read() == nil)

  let status = CurrentRunStatus(
    runID: UUID(),
    trigger: .scheduled,
    operation: .run,
    startedAt: Date(timeIntervalSince1970: 100),
    progress: EngineRunProgress(
      phase: .downloading,
      detail: "Scryfall card data",
      completed: 5,
      total: 10
    ),
    updatedAt: Date(timeIntervalSince1970: 110)
  )
  store.write(status)
  #expect(store.read() == status)

  store.clear()
  #expect(store.read() == nil)
}

@Test
func engineRunProgressFractionIsClampedAndIndeterminate() {
  #expect(EngineRunProgress(phase: .building, completed: 5, total: 10).fractionCompleted == 0.5)
  #expect(EngineRunProgress(phase: .building, completed: 5, total: nil).fractionCompleted == nil)
  #expect(EngineRunProgress(phase: .building, completed: 50, total: 10).fractionCompleted == 1)
}

@Test
func engineScheduleComputesNextSixHourlyRun() {
  let schedule = EngineSchedule(
    label: "test",
    isInstalled: true,
    runAtLoad: true,
    entries: [0, 6, 12, 18].map { EngineSchedule.CalendarEntry(minute: 0, hour: $0) },
    environment: ["TIGRIS_ARTIFACTS_BUCKET": "history"]
  )

  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 3, minute: 30))!

  let next = schedule.nextRunDate(after: now, calendar: calendar)
  let components = next.map { calendar.dateComponents([.hour, .minute], from: $0) }
  #expect(components?.hour == 6)
  #expect(components?.minute == 0)
}

@Test
func engineScheduleWithoutCalendarHasNoNextRun() {
  let schedule = EngineSchedule(
    label: "test",
    isInstalled: false,
    runAtLoad: false,
    entries: [],
    environment: [:]
  )
  #expect(schedule.nextRunDate() == nil)
}
