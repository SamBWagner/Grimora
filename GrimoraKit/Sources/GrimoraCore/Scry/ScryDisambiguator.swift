import Foundation

/// The on-device AI seam for the hardest scans, mirroring the structure of
/// `PlainTextSearchTranspiler` (protocol + factory + scripted/unavailable doubles).
///
/// Apple's on-device model gains native image input in iOS 27; until then the
/// model cannot look at the card pixels, so `live()` returns the unavailable
/// double and the resolver routes ambiguous scans to the disambiguation UI
/// instead. Tests inject deterministic answers via `GRIMORA_TEST_SCRY_RESPONSES`.
public struct ScryDisambiguationRequest: Equatable, Sendable {
  public var signals: ScrySignals
  /// Ranked candidates the text/visual tiers could not separate.
  public var candidates: [CardRecord]
  // A rectified card image will be attached here once iOS 27 image input lands.

  public init(signals: ScrySignals, candidates: [CardRecord]) {
    self.signals = signals
    self.candidates = candidates
  }
}

public struct ScryDisambiguationResult: Equatable, Sendable {
  /// The chosen candidate's id, or `nil` if the model declined to pick.
  public var chosenCardID: String?

  public init(chosenCardID: String?) {
    self.chosenCardID = chosenCardID
  }
}

public protocol ScryDisambiguating: Sendable {
  /// Whether the model can actually run on this device/OS right now.
  var isAvailable: Bool { get }

  func disambiguate(_ request: ScryDisambiguationRequest) async throws -> ScryDisambiguationResult
}

public enum ScryDisambiguatorFactory {
  public static let testResponseEnvironmentKey = "GRIMORA_TEST_SCRY_RESPONSES"

  public static func live(processInfo: ProcessInfo = .processInfo) -> any ScryDisambiguating {
    if let script = processInfo.environment[testResponseEnvironmentKey] {
      return ScriptedScryDisambiguator(script: script)
    }

    // Native on-device image input arrives in iOS 27. Until the deployment
    // target can rely on it, the hard tail is handled by the disambiguation UI.
    return UnavailableScryDisambiguator()
  }
}

/// Used on iOS 26, where the on-device model cannot accept the card image.
public struct UnavailableScryDisambiguator: ScryDisambiguating {
  public init() {}

  public var isAvailable: Bool { false }

  public func disambiguate(_ request: ScryDisambiguationRequest) async throws -> ScryDisambiguationResult {
    ScryDisambiguationResult(chosenCardID: nil)
  }
}

/// Deterministic test double driven by a tab-separated script of
/// `normalizedName<TAB>chosenCardID` lines (one per line).
struct ScriptedScryDisambiguator: ScryDisambiguating {
  var responses: [String: String]

  var isAvailable: Bool { true }

  init(script: String) {
    responses = script
      .split(separator: "\n", omittingEmptySubsequences: true)
      .reduce(into: [:]) { result, line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return }
        result[String(parts[0]).normalizedQueryKey] = String(parts[1])
      }
  }

  func disambiguate(_ request: ScryDisambiguationRequest) async throws -> ScryDisambiguationResult {
    guard let name = request.signals.name else {
      return ScryDisambiguationResult(chosenCardID: nil)
    }
    let chosen = responses[name.normalizedQueryKey]
    // Only honor a scripted id that is actually among the offered candidates.
    if let chosen, request.candidates.contains(where: { $0.id == chosen }) {
      return ScryDisambiguationResult(chosenCardID: chosen)
    }
    return ScryDisambiguationResult(chosenCardID: nil)
  }
}
