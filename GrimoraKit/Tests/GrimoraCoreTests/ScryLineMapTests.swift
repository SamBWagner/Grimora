@testable import GrimoraCore
import CoreGraphics
import XCTest

/// Pure-geometry tests for `ScryLineMap` — no Vision, just synthetic line sets
/// shaped like real card layouts. Boxes are Vision-normalized (bottom-left
/// origin, y up).
final class ScryLineMapTests: XCTestCase {
  private func line(_ text: String, x: CGFloat = 0.06, y: CGFloat, width: CGFloat = 0.5, height: CGFloat = 0.035) -> ScryRecognizedLine {
    ScryRecognizedLine(text: text, boundingBox: CGRect(x: x, y: y, width: width, height: height))
  }

  // MARK: - Standard frame

  func testStandardFrameAnchors() {
    let map = ScryLineMap(lines: [
      line("Captain of the Watch", y: 0.92),
      line("Creature — Human Soldier", y: 0.40, width: 0.55),
      line("Vigilance", y: 0.30),
      line("Greg Staples", y: 0.06),
      line("TM & © 1993-2009 Wizards of the Coast LLC 6/249", y: 0.03)
    ])

    XCTAssertEqual(map.nameLine?.text, "Captain of the Watch")
    XCTAssertEqual(map.typeLine?.text, "Creature — Human Soldier")
    XCTAssertEqual(map.copyrightLine?.text, "TM & © 1993-2009 Wizards of the Coast LLC 6/249")

    let band = try! XCTUnwrap(map.symbolBand)
    // Right of the type line's right edge (0.06 + 0.55)…
    XCTAssertGreaterThan(band.minX, 0.60)
    // …vertically around it: type line midY 0.4175 (y up) → top-left-origin ≈ 0.58.
    XCTAssertEqual(band.midY, 1 - 0.4175, accuracy: 0.03)
  }

  // MARK: - Saga / class (low type line)

  func testSagaLowTypeLinePullsAnchorsDown() {
    let map = ScryLineMap(lines: [
      line("History of Benalia", y: 0.92),
      line("I, II — Create a 2/2 white Knight", y: 0.75),
      line("III — Knights you control get +2/+1", y: 0.55),
      line("Enchantment — Saga", y: 0.115, width: 0.45),
      line("™ & © 2018 Wizards of the Coast", y: 0.03)
    ])

    XCTAssertEqual(map.typeLine?.text, "Enchantment — Saga")
    XCTAssertEqual(map.nameLine?.text, "History of Benalia")

    let band = try! XCTUnwrap(map.symbolBand)
    // Low type line → low band (top-left-origin y grows downward).
    XCTAssertGreaterThan(band.midY, 0.80)
  }

  // MARK: - Adventure (second type box must not steal anchors)

  func testAdventureSecondTypeBoxDoesNotWin() {
    let map = ScryLineMap(lines: [
      line("Brazen Borrower", y: 0.92),
      line("Creature — Faerie Rogue", y: 0.42, width: 0.55),
      line("Petty Theft", y: 0.36, width: 0.30),
      line("Instant — Adventure", y: 0.32, width: 0.30),
      line("Flash", y: 0.25)
    ])

    // The topmost type line anchors — the adventure's own box lower down doesn't.
    XCTAssertEqual(map.typeLine?.text, "Creature — Faerie Rogue")
    XCTAssertEqual(map.nameLine?.text, "Brazen Borrower")
  }

  // MARK: - Flip (inverted half must not confuse the name)

  func testFlipCardTopHalfAnchors() {
    let map = ScryLineMap(lines: [
      line("Bushi Tenderfoot", y: 0.92),
      line("Creature — Human Soldier", y: 0.55, width: 0.55),
      line("Kenzo the Hardhearted", y: 0.08)  // inverted bottom-half title
    ])

    XCTAssertEqual(map.typeLine?.text, "Creature — Human Soldier")
    XCTAssertEqual(map.nameLine?.text, "Bushi Tenderfoot")
  }

  // MARK: - Fallbacks

  func testNoTypeLineFallsBackToTopFractionRule() {
    // Full-art basic where the type line didn't OCR: the old top-32% rule holds.
    let map = ScryLineMap(lines: [
      line("Island", y: 0.55),
      line("Some flavor script", y: 0.10)
    ])

    XCTAssertNil(map.typeLine)
    XCTAssertEqual(map.nameLine?.text, "Island")
    XCTAssertNil(map.symbolBand)
  }

  func testTypeLineRunningToCardEdgeYieldsNoBand() {
    let map = ScryLineMap(lines: [
      line("Some Card", y: 0.92),
      line("Creature — Human Soldier Ranger Scout", y: 0.40, width: 0.90)
    ])

    XCTAssertEqual(map.typeLine?.text, "Creature — Human Soldier Ranger Scout")
    XCTAssertNil(map.symbolBand, "no room right of a full-width type line")
  }

  func testBareTypeWordNeverBecomesName() {
    let map = ScryLineMap(lines: [
      line("Land", y: 0.92),
      line("278/318", y: 0.03)
    ])

    XCTAssertNil(map.nameLine, "a bare type word is not a name even at the top")
  }
}
