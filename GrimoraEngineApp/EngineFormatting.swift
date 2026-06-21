import Foundation
import GrimoraCore
import GrimoraEngineKit
import SwiftUI

extension EngineRunProgress.Phase {
  var title: String {
    switch self {
    case .checking: "Checking sources"
    case .downloading: "Downloading sources"
    case .building: "Building catalog"
    case .publishing: "Publishing"
    }
  }
}

extension EngineRunProgress {
  /// Human-readable secondary line, e.g. the current pipeline stage while building.
  var detail: String? {
    guard phase == .building, let stage else { return nil }
    switch stage {
    case "preparing": return "Preparing database"
    case "ingestingScryfall": return "Ingesting Scryfall cards"
    case "ingestingPrices": return "Importing price history"
    case "enriching": return "Enriching"
    case "finalizing": return "Finalizing"
    case "validating": return "Validating"
    default: return stage
    }
  }
}

extension EngineRunRecord.Outcome {
  var label: String {
    switch self {
    case .succeeded: "Succeeded"
    case .failed: "Failed"
    case .skippedUnchanged: "No changes"
    }
  }

  var symbol: String {
    switch self {
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.octagon.fill"
    case .skippedUnchanged: "minus.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .succeeded: .green
    case .failed: .red
    case .skippedUnchanged: .secondary
    }
  }
}

extension EngineRunTrigger {
  var label: String {
    switch self {
    case .scheduled: "Scheduled"
    case .manual: "Manual"
    case .login: "At login"
    case .cli: "CLI"
    }
  }
}

extension EngineRunRecord.Operation {
  var label: String {
    switch self {
    case .run: "Run"
    case .build: "Build"
    case .publish: "Publish"
    }
  }
}

enum EngineFormat {
  static func duration(_ interval: TimeInterval) -> String {
    let total = Int(interval.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m \(seconds)s" }
    return "\(seconds)s"
  }

  static func relative(_ date: Date, now: Date = Date()) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: now)
  }

  static func absolute(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  static func bytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
  }

  /// Human label for Scryfall's bulk-data freshness (the date portion of its updated-at timestamp).
  static func scryfallVersion(_ sources: CatalogSourceVersions) -> String {
    String(sources.scryfallUpdatedAt.prefix(10))
  }

  /// Human label for MTGJSON's price-data version.
  static func mtgjsonVersion(_ sources: CatalogSourceVersions) -> String {
    "\(sources.mtgjsonDate) (\(sources.mtgjsonVersion))"
  }

  /// A short human description of a launchd calendar schedule.
  static func scheduleSummary(_ schedule: EngineSchedule) -> String {
    guard schedule.isInstalled else {
      return "Launch agent not installed"
    }
    let dailyTimes = schedule.entries.compactMap { entry -> String? in
      guard entry.day == nil, entry.weekday == nil, entry.month == nil, let hour = entry.hour else {
        return nil
      }
      return String(format: "%02d:%02d", hour, entry.minute ?? 0)
    }
    if !dailyTimes.isEmpty, dailyTimes.count == schedule.entries.count {
      return "Daily at " + dailyTimes.sorted().joined(separator: ", ")
    }
    if schedule.entries.isEmpty {
      return schedule.runAtLoad ? "Runs at login only" : "No calendar schedule"
    }
    return "Custom schedule (\(schedule.entries.count) times)"
  }
}

/// The ordered stages of a run, used to render the staged progress stepper.
enum RunStep: Int, CaseIterable, Identifiable {
  case checkingSources
  case downloadingSources
  case preparing
  case ingestingCards
  case importingPrices
  case enriching
  case finalizing
  case validating
  case publishing

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .checkingSources: "Checking sources"
    case .downloadingSources: "Downloading sources"
    case .preparing: "Preparing database"
    case .ingestingCards: "Ingesting card data"
    case .importingPrices: "Importing price history"
    case .enriching: "Enriching"
    case .finalizing: "Finalizing"
    case .validating: "Validating"
    case .publishing: "Publishing"
    }
  }

  /// The step a progress event corresponds to.
  static func current(for progress: EngineRunProgress) -> RunStep {
    switch progress.phase {
    case .checking: .checkingSources
    case .downloading: .downloadingSources
    case .publishing: .publishing
    case .building:
      switch progress.stage {
      case "preparing": .preparing
      case "ingestingScryfall": .ingestingCards
      case "ingestingPrices": .importingPrices
      case "enriching": .enriching
      case "finalizing": .finalizing
      case "validating": .validating
      default: .preparing
      }
    }
  }

  /// The steps shown for a given operation.
  static func steps(for operation: EngineRunRecord.Operation) -> [RunStep] {
    switch operation {
    case .build:
      [.checkingSources, .downloadingSources, .preparing, .ingestingCards, .importingPrices,
        .enriching, .finalizing, .validating]
    case .run:
      allCases
    case .publish:
      [.publishing]
    }
  }
}
