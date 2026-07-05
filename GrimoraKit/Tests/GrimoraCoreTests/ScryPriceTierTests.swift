@testable import GrimoraCore
import XCTest

/// Pure tests for the Scry price-tier mapping and its UserDefaults-backed
/// thresholds — no UI, no camera.
final class ScryPriceTierTests: XCTestCase {
  // MARK: - Tier boundaries

  func testDefaultThresholdBoundaries() {
    let t = ScryPriceThresholds.default
    XCTAssertEqual(t.tier(forUSD: nil), .none)   // unknown price → uncolored
    XCTAssertEqual(t.tier(forUSD: 0), .none)
    XCTAssertEqual(t.tier(forUSD: 0.99), .none)
    XCTAssertEqual(t.tier(forUSD: 1.0), .green)  // at the threshold counts as in-tier
    XCTAssertEqual(t.tier(forUSD: 4.99), .green)
    XCTAssertEqual(t.tier(forUSD: 5.0), .blue)
    XCTAssertEqual(t.tier(forUSD: 9.99), .blue)
    XCTAssertEqual(t.tier(forUSD: 10.0), .purple)
    XCTAssertEqual(t.tier(forUSD: 24.99), .purple)
    XCTAssertEqual(t.tier(forUSD: 25.0), .gold)
    XCTAssertEqual(t.tier(forUSD: 999.0), .gold)
  }

  func testCustomThresholds() {
    let t = ScryPriceThresholds(green: 2, blue: 8, purple: 20, gold: 50)
    XCTAssertEqual(t.tier(forUSD: 1.99), .none)
    XCTAssertEqual(t.tier(forUSD: 2.0), .green)
    XCTAssertEqual(t.tier(forUSD: 8.0), .blue)
    XCTAssertEqual(t.tier(forUSD: 19.99), .blue)
    XCTAssertEqual(t.tier(forUSD: 20.0), .purple)
    XCTAssertEqual(t.tier(forUSD: 49.99), .purple)
    XCTAssertEqual(t.tier(forUSD: 50.0), .gold)
  }

  // MARK: - Foil-aware effective price

  private func card(
    finishes: [String],
    priceUSD: Double? = nil
  ) -> CardRecord {
    CardRecord(
      id: "c",
      name: "Card",
      setCode: "set",
      setName: "Set",
      setType: "expansion",
      collectorNumber: "1",
      rarity: "rare",
      priceUSD: priceUSD,
      colorSortKey: 0,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "",
      finishes: finishes
    )
  }

  /// A foil-only printing (Bria, Riptide Rogue) has no non-foil `priceUSD`, but the
  /// value guide knows its foil price — so tiering must find $42, not treat it as free.
  func testFoilOnlyCardUsesFoilGuidePrice() {
    let bria = card(finishes: ["foil"], priceUSD: nil)
    let price = ScryValueTiering.effectivePriceUSD(for: bria, finishPrices: [.foil: 42.62])
    XCTAssertEqual(price, 42.62)
    XCTAssertEqual(ScryPriceThresholds.default.tier(forUSD: price), .gold)  // the loud one
  }

  /// A both-finish card is valued by its inherent (normal) finish — an expensive foil
  /// variant must not over-celebrate the plain copy the user most likely scanned.
  func testBothFinishCardPrefersDefaultNormalFinish() {
    let c = card(finishes: ["nonfoil", "foil"], priceUSD: 3.0)
    let price = ScryValueTiering.effectivePriceUSD(for: c, finishPrices: [.normal: 2.90, .foil: 40.0])
    XCTAssertEqual(price, 2.90)
  }

  /// When the default finish has no guide entry, fall through the finish ordering
  /// rather than dropping to the (possibly absent) `priceUSD`.
  func testFallsThroughFinishOrderingWhenDefaultMissing() {
    let c = card(finishes: ["nonfoil", "foil"], priceUSD: nil)  // default .normal
    let price = ScryValueTiering.effectivePriceUSD(for: c, finishPrices: [.foil: 40.0])
    XCTAssertEqual(price, 40.0)
  }

  /// No guide data → the Scryfall non-foil `priceUSD` still tiers normal cards.
  func testFallsBackToPriceUSDWhenNoGuide() {
    let c = card(finishes: ["nonfoil"], priceUSD: 5.0)
    XCTAssertEqual(ScryValueTiering.effectivePriceUSD(for: c, finishPrices: [:]), 5.0)
  }

  /// A foil-only card with no guide data and no non-foil price stays unknown (a light
  /// cue), never a false jackpot.
  func testUnknownWhenNoDataAtAll() {
    let c = card(finishes: ["foil"], priceUSD: nil)
    XCTAssertNil(ScryValueTiering.effectivePriceUSD(for: c, finishPrices: [:]))
  }

  // MARK: - Preferences

  /// A fresh, isolated defaults store — cleared on creation so each test starts clean.
  private func makeCleanDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "ScryPriceTierTests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  func testPreferencesReturnDefaultsWhenUnset() {
    let defaults = makeCleanDefaults()
    XCTAssertEqual(GrimoraScryPreferences.thresholds(userDefaults: defaults), ScryPriceThresholds.default)
  }

  func testPreferencesRoundTripWrittenValues() {
    let defaults = makeCleanDefaults()
    defaults.set(3.0, forKey: GrimoraScryPreferences.greenThresholdKey)
    defaults.set(12.0, forKey: GrimoraScryPreferences.blueThresholdKey)
    defaults.set(30.0, forKey: GrimoraScryPreferences.purpleThresholdKey)
    defaults.set(75.0, forKey: GrimoraScryPreferences.goldThresholdKey)

    XCTAssertEqual(
      GrimoraScryPreferences.thresholds(userDefaults: defaults),
      ScryPriceThresholds(green: 3, blue: 12, purple: 30, gold: 75)
    )
  }

  func testExplicitZeroThresholdIsHonored() {
    // object(forKey:) distinguishes "set to 0" from "absent", so a deliberate 0
    // is kept rather than snapping back to the default.
    let defaults = makeCleanDefaults()
    defaults.set(0.0, forKey: GrimoraScryPreferences.greenThresholdKey)
    let t = GrimoraScryPreferences.thresholds(userDefaults: defaults)
    XCTAssertEqual(t.green, 0)
    XCTAssertEqual(t.blue, ScryPriceThresholds.default.blue)  // untouched keys still default
  }
}
