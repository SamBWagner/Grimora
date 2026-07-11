import Foundation
import GrimoraCore
import XCTest

#if os(iOS)
  import UIKit
#endif

/// A/B scroll benchmark for the off-main image-decode fix.
///
/// Seeds a large collection whose tiles point at real (generated) on-disk JPEGs, opens it — the
/// eager `AdaptiveCardGrid` realises every tile at once, kicking off a decode storm — scrolls the
/// whole thing, and reads the cumulative frame-hitch tally back off the perf HUD's accessibility
/// value (`GRIMORA_PERF_HUD=1`). Two methods run the identical flow with the off-main predecode ON
/// (the fix) and OFF (`GRIMORA_DISABLE_IMAGE_PREDECODE=1`, the pre-fix draw-time decode); the
/// difference in hitches between them is the win the fix buys.
///
/// This runs in the iOS simulator, whose host-class CPU decodes far faster than a real phone, so
/// treat the absolute numbers as a floor — the gap is wider on-device. iOS only.
final class ScrollPerfBenchmarkUITests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GrimoraScrollPerf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  #if os(iOS)
    /// Keeps the decoded-bitmap working set (cardCount × 745×1040×4B ≈ 465MB) under the loader's
    /// 512MB cost cap so nothing evicts mid-run and every tile decodes exactly once.
    private static let cardCount = 150

    @MainActor
    func testScrollHitchesWithPredecode() throws {
      let sample = try runBenchmark(disablePredecode: false)
      record(sample, label: "predecode-ON")
    }

    @MainActor
    func testScrollHitchesWithoutPredecode() throws {
      let sample = try runBenchmark(disablePredecode: true)
      record(sample, label: "predecode-OFF")
    }

    private struct Sample {
      var hitches: Int
      var jankMilliseconds: Int
      var gridRowPacks: Int
      var tileBodyEvals: Int
      var snapshotBuilds: Int
    }

    @MainActor
    private func runBenchmark(disablePredecode: Bool) throws -> Sample {
      let imagesDirectory = temporaryDirectory.appendingPathComponent("Images", isDirectory: true)
      let tilePaths = try generateTiles(count: Self.cardCount, into: imagesDirectory)
      let cards = Self.fixtureCards(imagePaths: tilePaths)

      let app = XCUIApplication()
      let fixtureData = try JSONEncoder().encode(cards)
      app.launchArguments += ["-Grimora.cloudSync.mode", "disabled"]
      app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
        temporaryDirectory.appendingPathComponent("perf.sqlite").path
      app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
      app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
        String(decoding: fixtureData, as: Unicode.UTF8.self)
      app.launchEnvironment["GRIMORA_TEST_CATEGORIZED_LIST_NAME"] = "PerfBench"
      app.launchEnvironment["GRIMORA_TEST_CATEGORY_NAMES"] = "Deck"
      app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = imagesDirectory.path
      app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
        "GrimoraScrollPerf-\(UUID().uuidString)"
      app.launchEnvironment["GRIMORA_PERF_HUD"] = "1"
      app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
      app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
      app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
      app.launchEnvironment["GRIMORA_DISABLE_ONBOARDING"] = "1"
      if disablePredecode {
        app.launchEnvironment["GRIMORA_DISABLE_IMAGE_PREDECODE"] = "1"
      }
      app.launch()

      let collectionsTab = button(app, labeled: "Collections")
      XCTAssertTrue(collectionsTab.waitForExistence(timeout: 30), "Collections tab not found")
      activate(collectionsTab)
      let overview = firstElement(app, identifier: "card-lists-overview")
      XCTAssertTrue(overview.waitForExistence(timeout: 15), "Collections overview did not appear")

      let tile = firstElement(app, identifier: "card-list-overview-tile-PerfBench")
      XCTAssertTrue(tile.waitForExistence(timeout: 15), "seeded list tile not found")
      // Let the HUD's CADisplayLink monitor come up and the overview settle, then baseline the
      // hitch tally *before* the expensive open+scroll so navigation chrome common to both runs
      // cancels out of the delta.
      RunLoop.current.run(until: Date().addingTimeInterval(1.5))
      let baseline = try readStatus(app)

      activate(tile)
      let scroll = firstElement(app, identifier: "card-list-detail-scroll")
      XCTAssertTrue(scroll.waitForExistence(timeout: 15), "list detail scroll not found")

      // Traverse the whole list so every tile is realised and drawn (down), then back up. The short
      // settle after each flick lets async image loads finish and actually draw — which is where the
      // main-thread decode lands when the predecode is off.
      for _ in 0..<12 {
        scroll.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
      }
      for _ in 0..<6 {
        scroll.swipeDown()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.6))

      let final = try readStatus(app)
      return Sample(
        hitches: max(0, final.hitches - baseline.hitches),
        jankMilliseconds: max(0, final.jankMilliseconds - baseline.jankMilliseconds),
        gridRowPacks: max(0, final.gridRowPacks - baseline.gridRowPacks),
        tileBodyEvals: max(0, final.tileBodyEvals - baseline.tileBodyEvals),
        snapshotBuilds: max(0, final.snapshotBuilds - baseline.snapshotBuilds)
      )
    }

    @MainActor
    private func readStatus(_ app: XCUIApplication) throws -> Sample {
      let status = firstElement(app, identifier: "perf-hud-status")
      XCTAssertTrue(status.waitForExistence(timeout: 5), "perf HUD status element not found")
      let value = (status.value as? String) ?? ""
      func field(_ key: String) -> Int {
        guard
          let token = value.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }),
          let n = Int(token.dropFirst(key.count + 1))
        else {
          XCTFail("could not parse '\(key)' from '\(value)'")
          return 0
        }
        return n
      }
      return Sample(
        hitches: field("total"),
        jankMilliseconds: field("jank"),
        gridRowPacks: field("packs"),
        tileBodyEvals: field("tiles"),
        snapshotBuilds: field("snaps")
      )
    }

    private func record(_ sample: Sample, label: String) {
      let line =
        "SCROLLPERF \(label) scrollHitches=\(sample.hitches) jankMs=\(sample.jankMilliseconds) gridRowPacks=\(sample.gridRowPacks) tileBodyEvals=\(sample.tileBodyEvals) snapshotBuilds=\(sample.snapshotBuilds) cards=\(Self.cardCount)"
      print(line)
      let attachment = XCTAttachment(string: line)
      attachment.name = "scrollperf-\(label)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }

    /// Renders `count` distinct 745×1040 (Scryfall "png"-scale) JPEG tiles at scale 1 — a gradient
    /// plus a spray of filled circles so each file carries real high-frequency content and a
    /// representative decode cost, rather than a flat fill that compresses (and decodes) to nothing.
    @MainActor
    private func generateTiles(count: Int, into directory: URL) throws -> [String] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      format.opaque = true
      let size = CGSize(width: 745, height: 1040)
      let renderer = UIGraphicsImageRenderer(size: size, format: format)
      let space = CGColorSpaceCreateDeviceRGB()

      var paths: [String] = []
      paths.reserveCapacity(count)
      for index in 0..<count {
        let image = renderer.image { context in
          let cg = context.cgContext
          let hue = CGFloat(index % 37) / 37
          let top = UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor
          let bottom = UIColor(
            hue: (hue + 0.2).truncatingRemainder(dividingBy: 1),
            saturation: 0.85, brightness: 0.35, alpha: 1
          ).cgColor
          if let gradient = CGGradient(
            colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]
          ) {
            cg.drawLinearGradient(
              gradient, start: .zero,
              end: CGPoint(x: size.width, y: size.height), options: []
            )
          }
          for i in 0..<240 {
            let rect = CGRect(
              x: CGFloat((i * 53 + index * 7) % Int(size.width)),
              y: CGFloat((i * 97 + index * 13) % Int(size.height)),
              width: 28, height: 28
            )
            UIColor(hue: CGFloat((i * 7) % 100) / 100, saturation: 0.9, brightness: 0.95, alpha: 1)
              .setFill()
            cg.fillEllipse(in: rect)
          }
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
          throw NSError(domain: "ScrollPerfBenchmark", code: 1)
        }
        let url = directory.appendingPathComponent("tile-\(index).jpg")
        try data.write(to: url)
        paths.append(url.path)
      }
      return paths
    }

    private static func fixtureCards(imagePaths: [String]) -> [CardRecord] {
      imagePaths.enumerated().map { index, path in
        var card = CardRecord(
          id: "perf-\(index)",
          name: "Perf Card \(index)",
          releasedAt: "2026-01-01",
          setCode: "prf",
          setName: "Perf Set",
          setType: "expansion",
          collectorNumber: "\(index + 1)",
          collectorNumberNumber: index + 1,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: index % 6,
          layout: "normal",
          typeLine: "Creature — Beast",
          oracleText: "",
          isRealCard: true
        )
        card.smallImagePath = path
        card.normalImagePath = path
        card.largeImagePath = path
        return card
      }
    }
  #endif
}
