#if os(iOS)
import GrimoraCore
import SwiftUI
import UIKit

/// The Scry tab. Two modes, both funnelling into the **Scanned** collection:
/// - **Single:** tap to scan → a confirmation card with "Add to Scanned".
/// - **Bulk:** mount the phone over a fixed spot; confident cards fire straight
///   into Scanned, uncertain ones pause for a Correct/Incorrect call. A card is
///   only scanned once per placement — you must *move* it (swap/remove) before the
///   next one, which also lets you add duplicates.
struct ScryTabView: View {
  @Environment(GrimoraAppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  var isActive: Bool

  @State private var controller = ScryCameraController()
  @State private var mode: Mode = .single

  // Single-mode.
  @State private var phase: Phase = .idle
  @State private var picker: PickerItem?

  // Shared review sheet (single "Add to Scanned" + bulk Correct/Incorrect).
  @State private var review: Review?

  // Bulk-mode workflow.
  @State private var scannedCount = 0
  @State private var lastAddedName: String?
  @State private var armed = true
  @State private var isScanning = false
  @State private var stableKey: String?
  @State private var stableCount = 0
  @State private var committedCentroid: CGPoint?
  @State private var committedCardID: CardRecord.ID?
  @State private var rejectedIDs: Set<CardRecord.ID> = []

  private enum Mode: String { case single, bulk }
  private enum Phase: Equatable { case idle, scanning, noCard }

  private struct Review: Identifiable {
    let id = UUID()
    let kind: ScryReviewKind
    let card: CardRecord
  }

  /// How far (normalized) the card must move to count as a new placement.
  private let movementThreshold: CGFloat = 0.08

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      switch controller.authorization {
      case .authorized: authorized
      case .denied: ScryPermissionDeniedView()
      case .undetermined: ProgressView().tint(.white)
      }
    }
    .onAppear { syncCamera() }
    .onDisappear { controller.stop() }
    .onChange(of: isActive) { _, _ in syncCamera() }
    .onChange(of: scenePhase) { _, _ in syncCamera() }
    // Pause the camera entirely while the card detail pane is open — the user is
    // looking at a card, not the viewfinder, so there's no reason to keep the
    // capture session and Vision running under load.
    .onChange(of: model.selectedCard?.id) { _, _ in syncCamera() }
    .onChange(of: mode) { _, m in applyFocus(for: m); resetBulk() }
    // Drive bulk stability off the per-cycle generation, not previewGuess —
    // a stably-recognized card produces an unchanged guess, so onChange(of:
    // previewGuess) would never fire the follow-up cycles and never commit.
    .onChange(of: controller.previewGeneration) { _, _ in considerForBulk(controller.previewGuess) }
    .onChange(of: controller.detectedCards) { _, cards in trackMovement(cards) }
    .sheet(item: $picker) { item in
      ScryDisambiguationSheet(candidates: item.candidates) { card in
        picker = nil
        review = Review(kind: .single, card: card)
      }
    }
    .sheet(item: $review) { item in
      ScryReviewSheet(
        card: item.card,
        kind: item.kind,
        onAddToScanned: { addToScanned(item.card); review = nil },
        onFullDetails: { review = nil; model.selectCard(item.card) },
        onCorrect: { commit(item.card); review = nil },
        onIncorrect: { rejectAndResume(item.card) },
        onDismiss: { review = nil }
      )
    }
  }

  private struct PickerItem: Identifiable { let id = UUID(); let candidates: [CardRecord] }

  // MARK: - Authorized content

  private var authorized: some View {
    ScryCameraPreviewView(
      session: controller.session,
      detectedCards: controller.detectedCards,
      lockColor: .scryLock,
      onFocusTap: { devicePoint in
        controller.focus(atDevicePoint: devicePoint, lock: mode == .bulk)
      }
    )
    .ignoresSafeArea()
    .overlay(alignment: .top) { topControls }
    .overlay(alignment: .bottom) { bottomControls }
    .overlay { transientMessage }
  }

  private var topControls: some View {
    VStack(spacing: 10) {
      SwiftUI.Picker("Mode", selection: $mode) {
        Text("Single").tag(Mode.single)
        Text("Bulk").tag(Mode.bulk)
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 240)

      if mode == .bulk { bulkBar } else { hint }
    }
    .padding(.top, 10)
  }

  private var hint: some View {
    HStack(spacing: 7) {
      if let guess = controller.previewGuess {
        Image(systemName: guess.confident ? "checkmark.circle.fill" : "eye")
          .foregroundStyle(guess.confident ? .green : .secondary)
        Text(guess.confident ? guess.name : "\(guess.name)?").fontWeight(.semibold)
      } else {
        Text(controller.detectedCards.isEmpty ? "Point at a card" : "Card locked — tap to scan")
      }
    }
    .font(.subheadline.weight(.medium))
    .lineLimit(1)
    .padding(.horizontal, 14).padding(.vertical, 8)
    .background(.ultraThinMaterial, in: Capsule())
    .animation(.easeInOut(duration: 0.15), value: controller.previewGuess)
  }

  private var bulkBar: some View {
    HStack(spacing: 10) {
      if let guess = controller.previewGuess {
        Image(systemName: guess.confident ? "checkmark.circle.fill" : "eye")
          .foregroundStyle(guess.confident ? .green : .secondary)
        Text(guess.confident ? guess.name : "\(guess.name)?").fontWeight(.semibold).lineLimit(1)
      } else {
        Text("Place a card under the camera")
      }
      Button { controller.refocusThenLock() } label: { Image(systemName: "camera.metering.center.weighted") }
        .help("Refocus")
    }
    .font(.subheadline.weight(.medium))
    .padding(.horizontal, 14).padding(.vertical, 8)
    .background(.ultraThinMaterial, in: Capsule())
  }

  @ViewBuilder
  private var bottomControls: some View {
    switch mode {
    case .single: scanButton.padding(.bottom, 28)
    case .bulk: bulkStatus.padding(.bottom, 28)
    }
  }

  private var scanButton: some View {
    Button { scanSingle() } label: {
      ZStack {
        Circle().fill(.white).frame(width: 74, height: 74)
        Circle().stroke(.white, lineWidth: 4).frame(width: 86, height: 86)
        if phase == .scanning { ProgressView().tint(.black) }
        else { Image(systemName: "eye.fill").font(.title2).foregroundStyle(.black) }
      }
    }
    .disabled(phase == .scanning)
    .accessibilityIdentifier("scry-scan-button")
    .accessibilityLabel("Scan card")
  }

  private var bulkStatus: some View {
    VStack(spacing: 4) {
      Text("Auto-adding to Scanned")
      if scannedCount > 0 {
        Text("Added \(scannedCount)\(lastAddedName.map { " · \($0)" } ?? "")")
          .fontWeight(.semibold).foregroundStyle(.green)
      } else {
        Text("Drop a card, lift it, drop the next").foregroundStyle(.secondary)
      }
    }
    .font(.subheadline)
    .multilineTextAlignment(.center)
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(.ultraThinMaterial, in: Capsule())
    .animation(.easeInOut(duration: 0.15), value: scannedCount)
  }

  @ViewBuilder
  private var transientMessage: some View {
    if phase == .noCard {
      Text("No card locked — line one up and try again")
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
  }

  // MARK: - Single mode

  private func scanSingle() {
    guard phase != .scanning else { return }
    phase = .scanning
    Task {
      let result = await controller.scan()
      phase = .idle
      guard let result else { flashNoCard(); return }
      switch result.resolution.confidence {
      case .auto:
        if let card = result.resolution.card {
          review = Review(kind: .single, card: card)
        }
      case .ambiguous:
        picker = PickerItem(candidates: result.resolution.candidates)
      case .none:
        flashNoCard()
      }
    }
  }

  private func flashNoCard() {
    ScrySound.failed()
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    phase = .noCard
    Task {
      try? await Task.sleep(for: .seconds(1.6))
      if phase == .noCard { phase = .idle }
    }
  }

  // MARK: - Bulk mode

  private func considerForBulk(_ guess: ScryCameraController.PreviewGuess?) {
    guard mode == .bulk, review == nil, !isScanning else { return }
    guard let guess else { stableKey = nil; stableCount = 0; return }

    let key = guess.card?.id ?? guess.name
    if key == stableKey { stableCount += 1 } else { stableKey = key; stableCount = 1 }
    guard stableCount >= 2 else { return }

    // Re-arm when a *different* confident card appears — a new card was placed,
    // even if it landed in the same spot (centroid movement can miss that). Safe
    // against stationary flicker because it requires a different confident id.
    if !armed, guess.confident, let card = guess.card, card.id != committedCardID {
      armed = true
      rejectedIDs = []
    }
    guard armed else { return }

    if guess.confident, let card = guess.card, !rejectedIDs.contains(card.id) {
      commit(card)  // confident → straight to Scanned
    } else if !guess.confident {
      runUncertainScan()  // need candidates for the Correct/Incorrect pass
    }
  }

  /// A full scan to get ranked candidates for an uncertain card.
  private func runUncertainScan() {
    isScanning = true
    Task {
      let result = await controller.scan()
      isScanning = false
      guard mode == .bulk, armed, review == nil, let result else { return }
      switch result.resolution.confidence {
      case .auto:
        if let card = result.resolution.card, !rejectedIDs.contains(card.id) { commit(card) }
      case .ambiguous:
        if let next = result.resolution.candidates.first(where: { !rejectedIDs.contains($0.id) }) {
          review = Review(kind: .bulkUncertain, card: next)
        }
      case .none:
        break
      }
    }
  }

  /// Commits a card to Scanned and waits for the card to move before the next.
  private func commit(_ card: CardRecord) {
    addToScanned(card)
    committedCentroid = subjectCentroid(controller.detectedCards)
    committedCardID = card.id
    armed = false
    stableKey = nil
    stableCount = 0
  }

  private func rejectAndResume(_ card: CardRecord) {
    rejectedIDs.insert(card.id)
    review = nil
    stableKey = nil
    stableCount = 0  // re-trigger a scan for the next-best candidate
  }

  /// Re-arms only when the card actually moves (or leaves), so a stationary card
  /// is never scanned twice — and a swap/duplicate is picked up immediately.
  private func trackMovement(_ cards: [ScryDetectedCard]) {
    guard mode == .bulk, !armed else { return }
    let centroid = subjectCentroid(cards)
    let moved: Bool
    if let centroid, let committed = committedCentroid {
      moved = distance(centroid, committed) > movementThreshold
    } else {
      moved = true  // no card in frame, or nothing committed → treat as moved
    }
    if moved {
      armed = true
      committedCentroid = nil
      rejectedIDs = []
      stableKey = nil
      stableCount = 0
    }
  }

  private func addToScanned(_ card: CardRecord) {
    guard model.addCardToScanned(card) else {
      ScrySound.failed()
      return
    }
    scannedCount += 1
    lastAddedName = card.name
    ScrySound.scanned()
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  private func resetBulk() {
    armed = true
    isScanning = false
    stableKey = nil
    stableCount = 0
    committedCentroid = nil
    committedCardID = nil
    rejectedIDs = []
  }

  // MARK: - Geometry

  private func subjectCentroid(_ cards: [ScryDetectedCard]) -> CGPoint? {
    guard let corners = cards.first?.normalizedCorners, !corners.isEmpty else { return nil }
    let sum = corners.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    return CGPoint(x: sum.x / CGFloat(corners.count), y: sum.y / CGFloat(corners.count))
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }

  // MARK: - Lifecycle / focus

  /// The camera should run only when the tab is active, the app is foregrounded,
  /// and no full card detail pane is covering it.
  private var shouldRunCamera: Bool {
    isActive && scenePhase == .active && model.selectedCard == nil
  }

  private func syncCamera() {
    if shouldRunCamera { startCamera() } else { controller.stop() }
  }

  private func startCamera() {
    Task {
      await controller.start(database: model.database)
      applyFocus(for: mode)
    }
  }

  private func applyFocus(for mode: Mode) {
    switch mode {
    case .bulk: controller.refocusThenLock()
    case .single: controller.setFocusLocked(false)
    }
  }
}

/// Confirmation card shown after a scan (single) or for an uncertain bulk card.
private struct ScryReviewSheet: View {
  let card: CardRecord
  let kind: ScryReviewKind
  let onAddToScanned: () -> Void
  let onFullDetails: () -> Void
  let onCorrect: () -> Void
  let onIncorrect: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      cardImage
        .frame(maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))

      VStack(spacing: 4) {
        Text(card.name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
        Text("\(card.setName) · \(card.setCode.uppercased()) \(card.collectorNumber)")
          .font(.subheadline).foregroundStyle(.secondary)
      }

      switch kind {
      case .single:
        VStack(spacing: 10) {
          Button(action: onAddToScanned) {
            Label("Add to Scanned", systemImage: "tray.and.arrow.down.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)

          Button("Full details", action: onFullDetails)
          Button("Rescan", role: .cancel, action: onDismiss)
        }
      case .bulkUncertain:
        Text("Is this right?").font(.headline)
        HStack(spacing: 12) {
          Button(role: .destructive, action: onIncorrect) {
            Label("Incorrect", systemImage: "xmark").frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered).controlSize(.large)

          Button(action: onCorrect) {
            Label("Correct", systemImage: "checkmark").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).controlSize(.large)
        }
      }
    }
    .padding(24)
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private var cardImage: some View {
    if let path = card.normalImagePath ?? card.largeImagePath,
       let image = UIImage(contentsOfFile: path) {
      Image(uiImage: image).resizable().scaledToFit()
    } else if let urlString = card.normalImageURL ?? card.largeImageURL,
              let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFit()
      } placeholder: {
        ProgressView()
      }
    } else {
      RoundedRectangle(cornerRadius: 12).fill(.quaternary).aspectRatio(0.72, contentMode: .fit)
    }
  }
}

private enum ScryReviewKind { case single, bulkUncertain }

/// Shown when camera access is denied — routes the user to Settings.
private struct ScryPermissionDeniedView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "eye.slash").font(.system(size: 44)).foregroundStyle(.secondary)
      Text("Camera access needed").font(.headline)
      Text("Scry uses the camera to recognize cards. Enable camera access in Settings.")
        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(32)
    .foregroundStyle(.white)
  }
}

/// A printing picker for the genuinely-ambiguous single-scan case.
private struct ScryDisambiguationSheet: View {
  let candidates: [CardRecord]
  let onPick: (CardRecord) -> Void

  var body: some View {
    NavigationStack {
      List(candidates) { card in
        Button { onPick(card) } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(card.name).font(.body)
            Text("\(card.setName) · \(card.setCode.uppercased()) \(card.collectorNumber)")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Which printing?")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
  }
}
#endif
