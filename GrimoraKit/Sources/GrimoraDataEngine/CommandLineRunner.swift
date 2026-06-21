import Foundation
import GrimoraCore
import GrimoraEngineKit

/// Thin CLI shell over `GrimoraEngineKit`. Parses arguments, drives the engine, and prints results.
/// The command surface is unchanged so the installed launchd agent keeps working untouched.
struct CommandLineRunner {
  func run(arguments: [String]) async throws {
    guard let command = arguments.first else {
      throw EngineError.invalidCommand
    }

    let engine = try GrimoraDataEngine()
    let trigger = EngineRunTrigger(
      rawValue: ProcessInfo.processInfo.environment["GRIMORA_RUN_TRIGGER"] ?? ""
    ) ?? .scheduled

    let progress: EngineProgressHandler = { progress in
      if let stage = progress.stage {
        print("[\(stage)] \(progress.completed)")
      } else {
        print("[\(progress.phase.rawValue)]")
      }
    }

    switch command {
    case "check":
      let check = try await engine.checkForUpdate()
      print(check.updateAvailable ? "update available" : "unchanged")
      print("scryfall: \(check.scryfallChanged ? "changed" : "unchanged")")
      print("mtgjson: \(check.mtgjsonChanged ? "changed" : "unchanged")")
      print(try jsonString(check.current))
    case "build":
      let result = try await engine.build(
        force: arguments.contains("--force"),
        trigger: trigger,
        progress: progress
      )
      print(result.manifestURL.path)
    case "publish":
      guard arguments.count == 2 else {
        throw EngineError.invalidCommand
      }
      try await engine.publish(
        URL(fileURLWithPath: arguments[1]),
        trigger: trigger,
        progress: progress
      )
      print("published \(arguments[1])")
    case "run":
      let outcome = try await engine.run(
        force: arguments.contains("--force"),
        trigger: trigger,
        progress: progress
      )
      print(outcome.rawValue)
    case "status":
      print(try jsonString(engine.loadState()))
    default:
      throw EngineError.invalidCommand
    }
  }

  private func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}
