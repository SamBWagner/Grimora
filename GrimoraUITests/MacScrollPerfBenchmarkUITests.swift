import AppKit
import GrimoraCore
import XCTest

/// macOS counterpart of `ScrollPerfBenchmarkUITests` (iOS). Seeds a large collection whose tiles
/// point at generated on-disk JPEGs, opens it (the eager `AdaptiveCardGrid` realises every tile),
/// scrolls it hard, and reads the cumulative frame-hitch / jank / counter tally back off the perf
/// HUD's accessibility value (`GRIMORA_PERF_HUD=1`). Run with the off-main predecode ON and OFF
/// (`GRIMORA_DISABLE_IMAGE_PREDECODE`) to A/B, and diff `snaps`/`packs`/`tiles` to attribute the
/// Mac "chug" the same way the iOS run did.
///
/// NOTE: macOS XCUITest needs an interactive, windowed login session — it can't run headless — so
/// this is driven on a real Mac (locally or CI), not in an agent sandbox.
final class MacScrollPerfBenchmarkUITests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GrimoraMacScrollPerf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

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
      String(decoding: fixtureData, as: UTF8.self)
    app.launchEnvironment["GRIMORA_TEST_CATEGORIZED_LIST_NAME"] = "PerfBench"
    app.launchEnvironment["GRIMORA_TEST_CATEGORY_NAMES"] = "Deck"
    app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = imagesDirectory.path
    app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
      "GrimoraMacScrollPerf-\(UUID().uuidString)"
    app.launchEnvironment["GRIMORA_PERF_HUD"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_ONBOARDING"] = "1"
    if disablePredecode {
      app.launchEnvironment["GRIMORA_DISABLE_IMAGE_PREDECODE"] = "1"
    }
    app.launch()

    // Open the seeded list from the sidebar (Mac split view — no tab bar).
    let listRow = app.buttons["card-list-row-PerfBench"]
    XCTAssertTrue(listRow.waitForExistence(timeout: 30), "seeded list row not found")
    // Let the HUD's display link come up + the sidebar settle, then baseline the tally *before* the
    // expensive open+scroll so navigation chrome common to both runs cancels out of the delta.
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    let baseline = try readStatus(app)

    listRow.click()
    let scrollView = app.scrollViews["card-list-detail-scroll"]
    XCTAssertTrue(scrollView.waitForExistence(timeout: 15), "list detail scroll not found")

    // Traverse the whole list (down, then back up), realising and drawing every tile. The short
    // settle after each drag lets async image loads finish and actually draw.
    for _ in 0..<12 {
      scrollCollection(scrollView, down: true)
      RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }
    for _ in 0..<6 {
      scrollCollection(scrollView, down: false)
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

  /// Drags the scroll view up/down — macOS XCUITest has no `swipeUp`, so mirror the file's existing
  /// `scrollPrimaryScrollView` coordinate press-drag.
  @MainActor
  private func scrollCollection(_ scrollView: XCUIElement, down: Bool) {
    guard scrollView.exists else { return }
    let startY = down ? 0.82 : 0.24
    let endY = down ? 0.24 : 0.82
    let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
    let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
    start.press(forDuration: 0.05, thenDragTo: end)
  }

  @MainActor
  private func readStatus(_ app: XCUIApplication) throws -> Sample {
    let status = app.descendants(matching: .any).matching(identifier: "perf-hud-status").firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 5), "perf HUD status element not found")
    // macOS surfaces the status string as the AX label, not the value (unlike iOS) — fall back.
    let rawValue = (status.value as? String) ?? ""
    let value = rawValue.isEmpty ? status.label : rawValue
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

  @MainActor
  private func record(_ sample: Sample, label: String) {
    let line =
      "SCROLLPERF \(label) scrollHitches=\(sample.hitches) jankMs=\(sample.jankMilliseconds) gridRowPacks=\(sample.gridRowPacks) tileBodyEvals=\(sample.tileBodyEvals) snapshotBuilds=\(sample.snapshotBuilds) cards=\(Self.cardCount)"
    print(line)
    let attachment = XCTAttachment(string: line)
    attachment.name = "scrollperf-\(label)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Renders `count` distinct 745×1040 JPEG tiles (gradient + a spray of filled circles) so each
  /// file carries real high-frequency content and a representative decode cost. AppKit variant of
  /// the iOS generator (`UIGraphicsImageRenderer` isn't available on macOS).
  @MainActor
  private func generateTiles(count: Int, into directory: URL) throws -> [String] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let width = 745
    let height = 1040
    var paths: [String] = []
    paths.reserveCapacity(count)

    for index in 0..<count {
      guard
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: width,
          pixelsHigh: height,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ),
        let graphicsContext = NSGraphicsContext(bitmapImageRep: rep)
      else {
        throw NSError(domain: "MacScrollPerfBenchmark", code: 1)
      }

      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphicsContext
      let bounds = NSRect(x: 0, y: 0, width: width, height: height)
      let hue = CGFloat(index % 37) / 37
      let top = NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1)
      let bottom = NSColor(
        hue: (hue + 0.2).truncatingRemainder(dividingBy: 1),
        saturation: 0.85, brightness: 0.35, alpha: 1)
      NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -45)
      for i in 0..<240 {
        let rect = NSRect(
          x: CGFloat((i * 53 + index * 7) % width),
          y: CGFloat((i * 97 + index * 13) % height),
          width: 28, height: 28)
        NSColor(hue: CGFloat((i * 7) % 100) / 100, saturation: 0.9, brightness: 0.95, alpha: 1)
          .setFill()
        NSBezierPath(ovalIn: rect).fill()
      }
      NSGraphicsContext.restoreGraphicsState()

      guard
        let data = rep.representation(
          using: .jpeg, properties: [.compressionFactor: 0.85])
      else {
        throw NSError(domain: "MacScrollPerfBenchmark", code: 2)
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
}
