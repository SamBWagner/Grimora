import Foundation

/// Reads the installed launchd agent for the data engine to surface the schedule (for "next run")
/// and the environment it runs with (so an in-process run can target the same Tigris buckets).
///
/// This is intentionally read-only for now; in-app schedule editing is a planned follow-up and can
/// build on this type rather than replace it.
public struct EngineSchedule: Sendable, Equatable {
  /// One `StartCalendarInterval` entry. Unset fields are wildcards, matching launchd semantics.
  public struct CalendarEntry: Sendable, Equatable {
    public var minute: Int?
    public var hour: Int?
    public var day: Int?
    public var weekday: Int?
    public var month: Int?

    public init(
      minute: Int? = nil,
      hour: Int? = nil,
      day: Int? = nil,
      weekday: Int? = nil,
      month: Int? = nil
    ) {
      self.minute = minute
      self.hour = hour
      self.day = day
      self.weekday = weekday
      self.month = month
    }

    init(dictionary: [String: Any]) {
      func value(_ key: String) -> Int? { (dictionary[key] as? NSNumber)?.intValue }
      self.init(
        minute: value("Minute"),
        hour: value("Hour"),
        day: value("Day"),
        weekday: value("Weekday"),
        month: value("Month")
      )
    }
  }

  public static let defaultLabel = "com.samwagner.GrimoraDataEngine"

  public var label: String
  public var isInstalled: Bool
  public var runAtLoad: Bool
  public var entries: [CalendarEntry]
  public var environment: [String: String]

  public init(
    label: String,
    isInstalled: Bool,
    runAtLoad: Bool,
    entries: [CalendarEntry],
    environment: [String: String]
  ) {
    self.label = label
    self.isInstalled = isInstalled
    self.runAtLoad = runAtLoad
    self.entries = entries
    self.environment = environment
  }

  public static func installedAgentURL(
    label: String = defaultLabel,
    fileManager: FileManager = .default
  ) -> URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  /// Loads the installed agent, or returns a not-installed schedule if none is present.
  public static func load(
    label: String = defaultLabel,
    fileManager: FileManager = .default
  ) -> EngineSchedule {
    let url = installedAgentURL(label: label, fileManager: fileManager)
    guard let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else {
      return EngineSchedule(
        label: label,
        isInstalled: false,
        runAtLoad: false,
        entries: [],
        environment: [:]
      )
    }

    var entries: [CalendarEntry] = []
    if let array = plist["StartCalendarInterval"] as? [[String: Any]] {
      entries = array.map(CalendarEntry.init(dictionary:))
    } else if let single = plist["StartCalendarInterval"] as? [String: Any] {
      entries = [CalendarEntry(dictionary: single)]
    }

    return EngineSchedule(
      label: label,
      isInstalled: true,
      runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
      entries: entries,
      environment: plist["EnvironmentVariables"] as? [String: String] ?? [:]
    )
  }

  /// The next time launchd will fire the agent after `date`, or nil if there is no calendar schedule.
  /// launchd interprets `StartCalendarInterval` in the local time zone, so this uses `calendar`.
  public func nextRunDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
    entries.compactMap { entry -> Date? in
      var components = DateComponents()
      components.minute = entry.minute
      components.hour = entry.hour
      components.day = entry.day
      components.weekday = entry.weekday
      components.month = entry.month
      // launchd treats an unspecified minute alongside a specified hour as minute 0.
      if components.minute == nil, entry.hour != nil {
        components.minute = 0
      }
      guard components.minute != nil || components.hour != nil || components.day != nil
        || components.weekday != nil || components.month != nil
      else {
        return nil
      }
      return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }
    .min()
  }
}
