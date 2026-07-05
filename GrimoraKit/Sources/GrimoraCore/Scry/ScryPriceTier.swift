import Foundation

/// A coarse "how valuable is this card" band used by Scry to color the scan
/// confirmation and pick a celebratory sound. Ordered cheapest → most valuable.
public enum ScryPriceTier: Int, CaseIterable, Sendable, Equatable {
  case none
  case green
  case blue
  case purple
  case gold
}

/// The USD price boundaries between `ScryPriceTier`s. A card lands in the highest
/// tier whose threshold it meets or exceeds; below `green` (or with no known
/// price) it is `.none`.
public struct ScryPriceThresholds: Equatable, Sendable {
  public var green: Double
  public var blue: Double
  public var purple: Double
  public var gold: Double

  public init(green: Double, blue: Double, purple: Double, gold: Double) {
    self.green = green
    self.blue = blue
    self.purple = purple
    self.gold = gold
  }

  /// The shipped defaults: $1 / $5 / $10 / $25.
  public static let `default` = ScryPriceThresholds(green: 1, blue: 5, purple: 10, gold: 25)

  /// The tier a USD price falls into. A `nil` price (unknown value) → `.none`.
  public func tier(forUSD price: Double?) -> ScryPriceTier {
    guard let price else { return .none }
    if price >= gold { return .gold }
    if price >= purple { return .purple }
    if price >= blue { return .blue }
    if price >= green { return .green }
    return .none
  }
}

/// UserDefaults-backed storage for the Scry price-tier thresholds, mirroring
/// `GrimoraValuePreferences`. The keys are shared with the `@AppStorage` bindings
/// in the settings section, so edits there and reads here agree.
public enum GrimoraScryPreferences {
  public static let greenThresholdKey = "Grimora.scry.priceTier.green"
  public static let blueThresholdKey = "Grimora.scry.priceTier.blue"
  public static let purpleThresholdKey = "Grimora.scry.priceTier.purple"
  public static let goldThresholdKey = "Grimora.scry.priceTier.gold"

  public static let defaultThresholds = ScryPriceThresholds.default

  /// Reads the four thresholds, falling back to the default for any key that has
  /// never been set. An absent key reads as `nil` (not `0`) via `object(forKey:)`,
  /// so a threshold the user deliberately set to 0 is still honored.
  public static func thresholds(userDefaults: UserDefaults = .standard) -> ScryPriceThresholds {
    ScryPriceThresholds(
      green: userDefaults.object(forKey: greenThresholdKey) as? Double ?? defaultThresholds.green,
      blue: userDefaults.object(forKey: blueThresholdKey) as? Double ?? defaultThresholds.blue,
      purple: userDefaults.object(forKey: purpleThresholdKey) as? Double ?? defaultThresholds.purple,
      gold: userDefaults.object(forKey: goldThresholdKey) as? Double ?? defaultThresholds.gold
    )
  }
}
