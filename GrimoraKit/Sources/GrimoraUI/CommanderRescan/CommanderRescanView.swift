#if os(iOS)
import GrimoraCore
import SwiftUI
import UIKit

/// The **Re-scan Deck** flow for Commander decks. Reached from a deck's `···` menu.
///
/// Two phases in one full-screen cover:
/// - **Scanning** — reuses the tuned Bulk-scan machinery (`ScryBulkCoordinator`) but
///   accumulates cards into an in-memory `RescanSession` instead of the Scanned list.
/// - **Summary** — on *Done*, diffs the session against the deck (`CommanderRescan`)
///   and shows what changed for the user to Accept or Discard as a whole.
struct CommanderRescanView: View {
  @Environment(GrimoraAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  let list: CardCollectionRecord
  let entries: [CardCollectionEntryRecord]

  @State private var controller = ScryCameraController()
  @State private var session = RescanSession()
  @State private var bulk = ScryBulkCoordinator()
  @State private var review: Review?
  /// Non-nil once the user taps Done: the computed change set to review.
  @State private var summary: CommanderRescanDiff?

  private struct Review: Identifiable {
    let id = UUID()
    let card: CardRecord
    let priceUSD: Double?
  }

  private var priceThresholds: ScryPriceThresholds { GrimoraScryPreferences.thresholds() }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let summary {
        CommanderRescanSummarySheet(
          deckName: list.name,
          diff: summary,
          onAccept: {
            model.applyCommanderRescan(listID: list.id, diff: summary)
            dismiss()
          },
          onDiscard: { dismiss() }
        )
      } else {
        scanning
      }
    }
    .onAppear {
      bulk.onScanned = { session.record($0) }
      bulk.onNeedsReview = { card in
        review = Review(card: card, priceUSD: model.scanTierPriceUSD(for: card))
      }
      syncCamera()
    }
    .onDisappear { controller.stop() }
    .onChange(of: scenePhase) { _, _ in syncCamera() }
  }

  // MARK: - Scanning phase

  @ViewBuilder
  private var scanning: some View {
    switch controller.authorization {
    case .authorized: authorizedScanning
    case .denied: ScryPermissionDeniedView()
    case .undetermined: ProgressView().tint(.white)
    }
  }

  private var authorizedScanning: some View {
    ScryCameraPreviewView(
      session: controller.session,
      detectedCards: controller.detectedCards,
      lockColor: .scryLock,
      onFocusTap: { devicePoint in
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        controller.focus(atDevicePoint: devicePoint)
      }
    )
    .ignoresSafeArea()
    .overlay(alignment: .top) { topBar }
    .overlay(alignment: .bottom) { bottomBar }
    .onChange(of: controller.previewGeneration) { _, _ in
      bulk.consider(guess: controller.previewGuess, controller: controller)
    }
    .onChange(of: controller.detectedCards) { _, cards in
      bulk.trackMovement(cards: cards, controller: controller)
    }
    .sheet(
      item: $review,
      onDismiss: { bulk.reviewDismissed() }
    ) { item in
      ScryReviewSheet(
        card: item.card,
        tier: priceThresholds.tier(forUSD: item.priceUSD),
        priceUSD: item.priceUSD,
        kind: .bulkUncertain,
        onAddToScanned: {},
        onFullDetails: {},
        onCorrect: { bulk.acceptUncertain(item.card, controller: controller); review = nil },
        onIncorrect: { bulk.rejectUncertain(item.card); review = nil },
        onDismiss: { review = nil }
      )
    }
  }

  private var topBar: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.headline)
          .padding(10)
          .background(.ultraThinMaterial, in: Circle())
      }
      .accessibilityLabel("Cancel re-scan")

      Spacer()

      if let guess = controller.previewGuess {
        HStack(spacing: 7) {
          Image(systemName: guess.confident ? "checkmark.circle.fill" : "eye")
            .foregroundStyle(guess.confident ? .green : .secondary)
          Text(guess.confident ? guess.name : "\(guess.name)?")
            .fontWeight(.semibold).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
      }

      Spacer()

      Button { controller.refocusCenter() } label: {
        Image(systemName: "camera.metering.center.weighted")
          .font(.headline)
          .padding(10)
          .background(.ultraThinMaterial, in: Circle())
      }
      .accessibilityLabel("Refocus")
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
  }

  private var bottomBar: some View {
    VStack(spacing: 14) {
      VStack(spacing: 4) {
        Text("Re-scanning \(list.name)")
        if let voided = session.lastVoidedName {
          Text("Already scanned · \(voided)")
            .fontWeight(.semibold).foregroundStyle(.orange)
        } else if session.total > 0 {
          Text("Scanned \(session.total)\(session.lastName.map { " · \($0)" } ?? "")")
            .fontWeight(.semibold).foregroundStyle(.green)
        } else {
          Text("Drop a card, lift it, drop the next").foregroundStyle(.secondary)
        }
      }
      .font(.subheadline)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16).padding(.vertical, 10)
      .background(.ultraThinMaterial, in: Capsule())
      .animation(.easeInOut(duration: 0.15), value: session.total)
      .animation(.easeInOut(duration: 0.15), value: session.lastVoidedName)

      Button {
        finishScanning()
      } label: {
        Text("Done").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.horizontal, 40)
      .disabled(session.total == 0)
      .accessibilityIdentifier("finish-rescan-button")
    }
    .padding(.bottom, 28)
  }

  // MARK: - Actions / lifecycle

  private func finishScanning() {
    controller.stop()
    summary = CommanderRescan.diff(deckEntries: entries, scanned: session.scannedCards)
  }

  private var shouldRunCamera: Bool {
    scenePhase == .active && summary == nil
  }

  private func syncCamera() {
    guard shouldRunCamera else { controller.stop(); return }
    Task {
      await controller.start(database: model.database, imageCache: model.imageCache)
      controller.beginBulkFocus()
    }
  }
}

/// Observable wrapper around `CommanderRescanTally` that adds the scanning feedback:
/// the running count for the HUD, sound/haptics, and a brief "already scanned" note
/// when a duplicate singleton is voided. The counting rules live in the pure tally.
@MainActor
@Observable
final class RescanSession {
  private(set) var total = 0
  private(set) var lastName: String?
  /// Briefly set when a duplicate singleton scan was voided, for HUD feedback.
  private(set) var lastVoidedName: String?

  private var tally = CommanderRescanTally()
  private var voidClearTask: Task<Void, Never>?

  func record(_ card: CardRecord) {
    switch tally.record(card) {
    case .counted:
      total = tally.total
      lastName = card.name
      voidClearTask?.cancel()
      lastVoidedName = nil
      ScrySound.scanned()
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .voidedDuplicate:
      flashVoided(card.name)  // already have this singleton — skip the duplicate
      ScrySound.identified()
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
  }

  var scannedCards: [CommanderRescanScannedCard] { tally.scannedCards }

  private func flashVoided(_ name: String) {
    lastVoidedName = name
    voidClearTask?.cancel()
    voidClearTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.6))
      lastVoidedName = nil
    }
  }
}
#endif
