import Foundation
import GrimoraCore

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum SearchInputMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case scryfall
  case plainText

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .scryfall:
      "Scryfall"
    case .plainText:
      "Plain Text"
    }
  }
}

public struct PlainTextSearchTranspilerAvailability: Equatable, Sendable {
  public var isAvailable: Bool
  public var message: String?

  public init(isAvailable: Bool, message: String? = nil) {
    self.isAvailable = isAvailable
    self.message = message
  }

  public static let available = PlainTextSearchTranspilerAvailability(isAvailable: true)

  public static func unavailable(_ message: String) -> PlainTextSearchTranspilerAvailability {
    PlainTextSearchTranspilerAvailability(isAvailable: false, message: message)
  }
}

public struct PlainTextSearchTranspilation: Equatable, Sendable {
  public var query: String
  public var note: String?

  public init(query: String, note: String? = nil) {
    self.query = query
    self.note = note
  }
}

public enum PlainTextSearchTranspilerError: Error, Equatable, Sendable {
  case unavailable(String)
  case failed(String)

  public var message: String {
    switch self {
    case .unavailable(let message), .failed(let message):
      message
    }
  }
}

public protocol PlainTextSearchTranspiling: Sendable {
  var availability: PlainTextSearchTranspilerAvailability { get }

  func transpile(_ prompt: String) async throws -> PlainTextSearchTranspilation
  func repair(
    prompt: String,
    rejectedQuery: String,
    reason: SearchQueryUnsupportedReason
  ) async throws -> PlainTextSearchTranspilation
}

public enum PlainTextSearchTranspilerFactory {
  public static let testResponseEnvironmentKey = "GRIMORA_TEST_PLAIN_TEXT_SEARCH_RESPONSES"

  public static func live(processInfo: ProcessInfo = .processInfo) -> any PlainTextSearchTranspiling {
    if let responseScript = processInfo.environment[testResponseEnvironmentKey] {
      return ScriptedPlainTextSearchTranspiler(script: responseScript)
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      return FoundationModelsPlainTextSearchTranspiler()
    }
    #endif

    return UnavailablePlainTextSearchTranspiler(
      message: "Plain-text search requires Apple Intelligence on iOS 26 or macOS 26."
    )
  }
}

public struct UnavailablePlainTextSearchTranspiler: PlainTextSearchTranspiling {
  public var availability: PlainTextSearchTranspilerAvailability

  public init(message: String) {
    availability = .unavailable(message)
  }

  public func transpile(_ prompt: String) async throws -> PlainTextSearchTranspilation {
    throw PlainTextSearchTranspilerError.unavailable(
      availability.message ?? "Plain-text search is unavailable."
    )
  }

  public func repair(
    prompt: String,
    rejectedQuery: String,
    reason: SearchQueryUnsupportedReason
  ) async throws -> PlainTextSearchTranspilation {
    try await transpile(prompt)
  }
}

private struct ScriptedPlainTextSearchTranspiler: PlainTextSearchTranspiling {
  var responses: [String: PlainTextSearchTranspilation]

  var availability: PlainTextSearchTranspilerAvailability {
    .available
  }

  init(script: String) {
    responses = script
      .split(separator: "\n", omittingEmptySubsequences: true)
      .reduce(into: [:]) { result, line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
          return
        }

        let prompt = GrimoraSearchHistoryStore.normalizedQuery(String(parts[0]))
        let note = parts.count >= 3 ? String(parts[2]) : nil
        result[prompt] = PlainTextSearchTranspilation(query: String(parts[1]), note: note)
      }
  }

  func transpile(_ prompt: String) async throws -> PlainTextSearchTranspilation {
    let key = GrimoraSearchHistoryStore.normalizedQuery(prompt)
    guard let response = responses[key] else {
      throw PlainTextSearchTranspilerError.failed("The test plain-text search has no scripted response.")
    }

    return response
  }

  func repair(
    prompt: String,
    rejectedQuery: String,
    reason: SearchQueryUnsupportedReason
  ) async throws -> PlainTextSearchTranspilation {
    try await transpile(prompt)
  }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private struct FoundationModelsPlainTextSearchTranspiler: PlainTextSearchTranspiling {
  var availability: PlainTextSearchTranspilerAvailability {
    switch SystemLanguageModel.default.availability {
    case .available:
      return .available
    case .unavailable(let reason):
      return .unavailable(Self.message(for: reason))
    }
  }

  func transpile(_ prompt: String) async throws -> PlainTextSearchTranspilation {
    try await generate(prompt: prompt, repairContext: nil)
  }

  func repair(
    prompt: String,
    rejectedQuery: String,
    reason: SearchQueryUnsupportedReason
  ) async throws -> PlainTextSearchTranspilation {
    try await generate(
      prompt: prompt,
      repairContext:
        "The previous query `\(rejectedQuery)` was rejected: \(reason.message). Return a different supported query."
    )
  }

  private func generate(prompt: String, repairContext: String?) async throws -> PlainTextSearchTranspilation {
    guard availability.isAvailable else {
      throw PlainTextSearchTranspilerError.unavailable(
        availability.message ?? "Plain-text search is unavailable."
      )
    }

    let session = LanguageModelSession(instructions: Self.instructions)
    let response = try await session.respond(
      to: Self.prompt(for: prompt, repairContext: repairContext),
      generating: FoundationModelsPlainTextSearchResult.self,
      options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
    )

    return PlainTextSearchTranspilation(
      query: response.content.query,
      note: response.content.note
    )
  }

  private static let instructions = """
    Convert Magic: The Gathering card search requests into one concise Scryfall query supported by Grimora's offline search.
    Return Scryfall search syntax only. Use bare words only for card-name searches; for colors, types, rules text, formats, prices, dates, display controls, or other attributes, use a field/operator such as name:, t:, o:, kw:, m:, mv, c:, id:, r:, s:, f:, is:, has:, new:, unique:, order:, direction:, prefer:, or include:. Quote multi-word field values, such as o:"creature token"; never emit o:creature token as separate terms. Never return comma-separated keywords, explanations, Markdown, or prose in the query field.
    Remember that c: means card color only. Never use c:token or color:token. Token creation is oracle text, usually o:"creature token" or another o: phrase.
    Use only these supported fields and forms:
    name text, exact names, t/type, o/oracle, kw/keyword, m/mana, mv/manavalue, pow, tou, loy, pt, c/color, id/ci/commander, r/rarity, s/set, cn/number, st/settype, b/block, f/legal, banned, restricted, usd, eur, tix, border, frame, game, year, date, lang/language, is/has/new flags, unique, order, direction, prefer, include:extras.
    Prefer simple AND queries. Use OR only when needed. Do not use cube, art tags, oracle tags, function tags, or unsupported Scryfall server-only syntax.
    Examples: "red goblins that draw" -> "t:goblin c:r o:draw"; "red or blue goblins that draw" -> "t:goblin (c:r or c:u) o:draw"; "dragons under four mana" -> "t:dragon mv<4"; "creates tokens that are creatures" -> "o:\"creature token\"".
    """

  private static func prompt(for text: String, repairContext: String?) -> String {
    var prompt = "Request: \(text)\nReturn the best supported Scryfall query."
    if let repairContext {
      prompt += "\n\(repairContext)\nThe replacement must be valid Scryfall syntax supported by Grimora offline."
    }
    return prompt
  }

  private static func message(
    for reason: SystemLanguageModel.Availability.UnavailableReason
  ) -> String {
    switch reason {
    case .deviceNotEligible:
      "Plain-text search needs an Apple Intelligence-capable device."
    case .appleIntelligenceNotEnabled:
      "Turn on Apple Intelligence to use plain-text search."
    case .modelNotReady:
      "Apple Intelligence is still preparing its on-device model."
    @unknown default:
      "Plain-text search is unavailable."
    }
  }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct FoundationModelsPlainTextSearchResult {
  @Guide(description: "A concise valid Grimora-supported Scryfall query.")
  var query: String

  @Guide(description: "A short optional note about assumptions.")
  var note: String?
}
#endif
