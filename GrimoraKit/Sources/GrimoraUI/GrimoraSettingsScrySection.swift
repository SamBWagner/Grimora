#if os(iOS)
import GrimoraCore
import SwiftUI

/// "Scry Price Alerts" settings: the four USD thresholds that decide a scanned
/// card's color + sound tier. Backed by `GrimoraScryPreferences` — the same keys
/// the scan popups read, so edits here take effect on the next scan.
struct GrimoraSettingsScrySection: View {
  @AppStorage(GrimoraScryPreferences.greenThresholdKey)
  private var green = GrimoraScryPreferences.defaultThresholds.green
  @AppStorage(GrimoraScryPreferences.blueThresholdKey)
  private var blue = GrimoraScryPreferences.defaultThresholds.blue
  @AppStorage(GrimoraScryPreferences.purpleThresholdKey)
  private var purple = GrimoraScryPreferences.defaultThresholds.purple
  @AppStorage(GrimoraScryPreferences.goldThresholdKey)
  private var gold = GrimoraScryPreferences.defaultThresholds.gold

  var body: some View {
    Section("Scry Price Alerts") {
      thresholdRow("Green", tier: .green, value: $green, id: "green")
      thresholdRow("Blue", tier: .blue, value: $blue, id: "blue")
      thresholdRow("Purple", tier: .purple, value: $purple, id: "purple")
      thresholdRow("Legendary", tier: .gold, value: $gold, id: "gold")

      Text("When you scan a card, the confirmation shows its price (USD) and plays a bigger \u{201C}level-up\u{201D} sound as the value crosses each threshold. Cards under the Green threshold use the default click.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func thresholdRow(
    _ label: String,
    tier: ScryPriceTier,
    value: Binding<Double>,
    id: String
  ) -> some View {
    HStack(spacing: 12) {
      Circle()
        .fill(tier.accentColor ?? .secondary)
        .frame(width: 14, height: 14)
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
      Text(label)
      Spacer()
      TextField(label, value: value, format: .currency(code: "USD"))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 90)
        .accessibilityIdentifier("scry-threshold-\(id)")
    }
  }
}
#endif
