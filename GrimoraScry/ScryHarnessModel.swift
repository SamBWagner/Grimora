import Foundation
import GrimoraCore
import GrimoraUI
import SwiftUI
import UIKit

/// Wraps a finished scan while the user passes verdict on it.
struct PendingReview: Identifiable, Sendable {
  let id = UUID()
  let capture: ScryScanCapture
}

@MainActor
@Observable
final class ScryHarnessModel {
  enum Phase: Equatable {
    case loading
    case downloadingCatalog(String)
    case ready
    case failed(String)
  }

  private(set) var phase: Phase = .loading
  private(set) var environment: HarnessEnvironment?
  private(set) var captures: [CaptureRecord] = []
  private(set) var isScanning = false

  var pendingReview: PendingReview?
  var showsCaptureList = false

  let camera = ScryCameraController()
  let store = CaptureStore.documents()

  // Sticky per-session labeling defaults — most scanning sessions run through
  // one binder or box, so these rarely change capture to capture.
  var foil: Bool { didSet { UserDefaults.standard.set(foil, forKey: "capture.foil") } }
  var sleeved: Bool { didSet { UserDefaults.standard.set(sleeved, forKey: "capture.sleeved") } }
  var background: String { didSet { UserDefaults.standard.set(background, forKey: "capture.background") } }

  static let backgroundOptions = ["black", "wood", "white", "other"]

  init() {
    foil = UserDefaults.standard.bool(forKey: "capture.foil")
    sleeved = UserDefaults.standard.bool(forKey: "capture.sleeved")
    background = UserDefaults.standard.string(forKey: "capture.background") ?? "black"
  }

  // MARK: - Launch

  func launch() async {
    captures = store.listRecords()
    let environment: HarnessEnvironment
    do {
      environment = try await Task.detached(priority: .userInitiated) {
        try HarnessEnvironment.live()
      }.value
    } catch {
      phase = .failed("Could not open the card database: \(error)")
      return
    }
    self.environment = environment

    do {
      if try environment.database.cardCount() == 0 {
        try await downloadCatalog(environment: environment)
      }
    } catch {
      phase = .failed("Catalog download failed: \(error)")
      return
    }

    phase = .ready
    await camera.start(database: environment.database, imageCache: environment.imageCache)
  }

  private func downloadCatalog(environment: HarnessEnvironment) async throws {
    phase = .downloadingCatalog("Checking for card data…")
    let check = try await environment.updateService.checkForUpdates(manual: true)
    switch check {
    case .noLocalLibrary(let manifest), .updateAvailable(let manifest):
      _ = try await environment.updateService.downloadAndImport(
        manifest: manifest,
        temporaryDirectory: environment.temporaryDirectory,
        importer: environment.importer
      ) { [weak self] progress in
        await MainActor.run {
          self?.phase = .downloadingCatalog(Self.describe(progress))
        }
      }
    case .upToDate, .skipped:
      break
    }
  }

  private static func describe(_ progress: ImportProgress) -> String {
    switch progress {
    case .downloadingBulkData:
      return "Downloading card data…"
    case .downloadingBulkDataProgress(let completed, let total):
      guard let total, total > 0 else { return "Downloading card data…" }
      let percent = Int(Double(completed) / Double(total) * 100)
      return "Downloading card data… \(percent)%"
    case .decodingCardData:
      return "Unpacking card data…"
    case .storingSearchIndex, .storingSearchIndexProgress:
      return "Indexing cards…"
    case .cardDataReady(let count):
      return "Ready — \(count) cards"
    default:
      return "Preparing…"
    }
  }

  // MARK: - Scanning

  func scan() async {
    guard phase == .ready, !isScanning else { return }
    isScanning = true
    defer { isScanning = false }
    let capture = await camera.scanCapturingInput(usingStillCapture: true)
    pendingReview = PendingReview(capture: capture)
  }

  // MARK: - Saving

  /// Persists the reviewed capture: sidecar + still + upright crop.
  func save(
    _ capture: ScryScanCapture,
    verdict: CaptureRecord.Verdict,
    groundTruth: CaptureRecord.CardIdentity?,
    pickedFromCandidates: Bool,
    notes: String?
  ) async {
    let record = CaptureRecord(
      schemaVersion: 1,
      id: CaptureStore.makeID(),
      timestamp: Date(),
      verdict: verdict,
      pickedFromCandidates: pickedFromCandidates,
      needsLabel: groundTruth == nil,
      groundTruth: groundTruth,
      foil: foil,
      sleeved: sleeved,
      background: background,
      notes: (notes?.isEmpty ?? true) ? nil : notes,
      engine: capture.result.map { CaptureRecord.EngineOutcome($0.resolution) },
      capture: CaptureRecord.CaptureMeta(
        source: capture.source.rawValue,
        exifOrientation: capture.orientation.rawValue,
        deviceModel: Self.deviceModel(),
        systemVersion: UIDevice.current.systemVersion
      )
    )
    let store = self.store
    do {
      try await Task.detached(priority: .userInitiated) {
        let crop: CGImage? = capture.result.flatMap { result in
          result.rectified.map { ScryTextExtractor.makeUpright($0, orientation: result.orientation) }
        }
        try store.save(
          record: record,
          still: capture.image,
          stillOrientation: capture.orientation,
          crop: crop
        )
      }.value
      captures = store.listRecords()
    } catch {
      phase = .failed("Could not save capture: \(error)")
    }
  }

  func update(record: CaptureRecord) {
    try? store.write(record: record)
    captures = store.listRecords()
  }

  func delete(_ record: CaptureRecord) {
    store.delete(id: record.id)
    captures = store.listRecords()
  }

  // MARK: - Search

  /// Plain-text catalog search for labeling the true card by hand.
  func searchCards(_ text: String) -> [CardRecord] {
    guard let database = environment?.database,
          !text.trimmingCharacters(in: .whitespaces).isEmpty,
          case .results(let cards, _)? = try? database.search(
            CardSearchRequest(text: text, printingDisplayMode: .all, limit: 50)
          )
    else {
      return []
    }
    return cards
  }

  private static func deviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafeBytes(of: systemInfo.machine) { buffer in
      String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
  }
}
