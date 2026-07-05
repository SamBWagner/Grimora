import GrimoraCore
import SwiftUI

extension ScryPriceTier {
  /// The accent color for this tier, or `nil` for `.none` — cards below the first
  /// threshold stay uncolored/neutral.
  var accentColor: Color? {
    switch self {
    case .none: nil
    case .green: .green
    case .blue: .blue
    case .purple: .purple
    case .gold: Color(red: 0.85, green: 0.63, blue: 0.16)  // legendary orangey-gold
    }
  }

  /// Only the top ("legendary") tier draws a solid border around the popup.
  var hasBorder: Bool { self == .gold }
}
