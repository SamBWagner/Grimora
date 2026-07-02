#if os(iOS)
import GrimoraCore
import SwiftUI
import UIKit

/// The Scry tab. Two modes, both funnelling into the **Scanned** collection:
/// - **Single:** passive — the pipeline continuously identifies the card in
///   view and offers it as a tappable chip (`ScrySingleFlow` owns the rules);
///   tapping the chip opens the review sheet. Tapping anywhere on the preview
///   focuses the camera there and forces a scan, with explicit success/failure
///   feedback. There is no shutter button.
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

  // Single-mode passive flow (reducer-driven).
  @State private var flow: ScrySingleFlow.Phase = .idle
  @State private var singleCommittedCentroid: CGPoint?
  @State private var showNoCardFlash = false
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
    .onChange(of: mode) { _, m in applyFocus(for: m); resetBulk(); resetSingle() }
    // Drive stability off the per-cycle generation, not previewGuess —
    // a stably-recognized card produces an unchanged guess, so onChange(of:
    // previewGuess) would never fire the follow-up cycles and never commit.
    .onChange(of: controller.previewGeneration) { _, _ in
      switch mode {
      case .single: applySingle(previewTickEvent())
      case .bulk: considerForBulk(controller.previewGuess)
      }
    }
    .onChange(of: controller.detectedCards) { _, cards in
      switch mode {
      case .single: trackSingleMovement(cards)
      case .bulk: trackMovement(cards)
      }
    }
    .sheet(
      item: $picker,
      onDismiss: {
        // A pick opens the review sheet; a dismissal without one is a cancel.
        if mode == .single, review == nil {
          applySingle(.pickerCancelled)
        }
      }
    ) { item in
      ScryDisambiguationSheet(candidates: item.candidates) { card in
        picker = nil
        review = Review(kind: .single, card: card)
      }
    }
    .sheet(
      item: $review,
      onDismiss: {
        // Swipe-dismiss without a decision counts as "not added". Decisions the
        // buttons already reported moved the flow past `.offer`, where this
        // event is a no-op — so sending it unconditionally is safe.
        if mode == .single {
          applySingle(.reviewClosed(added: false))
        }
      }
    ) { item in
      ScryReviewSheet(
        card: item.card,
        kind: item.kind,
        onAddToScanned: { acceptSingle(item.card) },
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
        // In single mode a tap is also the manual scan gesture: focus where the
        // user pointed, then read whatever is there — with loud feedback.
        if mode == .single {
          applySingle(.userTappedScreen)
        }
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
        Text(controller.detectedCards.isEmpty ? "Point at a card — tap to focus & scan" : "Reading card…")
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
    case .single: singleStatus.padding(.bottom, 28)
    case .bulk: bulkStatus.padding(.bottom, 28)
    }
  }

  /// The passive single-mode bottom area: nothing while idle (the top hint
  /// teaches the gesture), a subtle progress pill while a scan verifies, and
  /// the confirm chip once a card is on offer.
  @ViewBuilder
  private var singleStatus: some View {
    switch flow {
    case .verifying:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading…").font(.subheadline.weight(.medium))
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      .background(.ultraThinMaterial, in: Capsule())
      .transition(.opacity)
    case .offer(let offer):
      ScryConfirmChip(
        offer: offer,
        onTap: { applySingle(.offerTapped) },
        onSwipeAccept: { applySingle(.offerSwipedToAccept) },
        onSwipeRetry: { applySingle(.offerSwipedToRetry) }
      )
      .transition(.move(edge: .bottom).combined(with: .opacity))
    case .idle, .tracking, .cooldown:
      EmptyView()
    }
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
    if showNoCardFlash {
      Text("No card locked — line one up and try again")
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
  }

  // MARK: - Single mode (passive flow)

  /// Feeds an event through `ScrySingleFlow` and executes the returned effect —
  /// the reducer owns every interaction rule; this just wires the world to it.
  private func applySingle(_ event: ScrySingleFlow.Event) {
    guard mode == .single else { return }
    let (next, effect) = ScrySingleFlow.reduce(flow, event)
    // A light ding as the confident chip pops — only on the transition out of
    // verifying (never re-dinged while the chip holds), and only for passive
    // finds: manual scans open the review sheet, and accepting a card has its
    // own, stronger sound.
    if case .verifying = flow,
       case .offer(let offer) = next,
       case .confident = offer.kind,
       !offer.manual {
      ScrySound.identified()
    }
    withAnimation(.easeInOut(duration: 0.2)) {
      flow = next
    }
    switch effect {
    case .none:
      break
    case .startScan(let manual):
      Task {
        // Only the deliberate tap uses the (audible, focus-sensitive) still
        // capture; passive scans read the quiet video frame the preview uses.
        if let result = await controller.scan(usingStillCapture: manual) {
          applySingle(.scanFinished(result.resolution))
        } else {
          applySingle(.scanFailed)
        }
      }
    case .presentReview(let card):
      review = Review(kind: .single, card: card)
    case .presentPicker(let candidates):
      picker = PickerItem(candidates: candidates)
    case .commitToScanned(let card):
      // Swipe-accept: same commit as the review sheet's button, minus the sheet.
      addToScanned(card)
      singleCommittedCentroid = subjectCentroid(controller.detectedCards)
    case .flashFailure:
      flashNoCard()
    }
  }

  /// The current preview cycle as a reducer event: the guess's identity key
  /// (card id when confident, name otherwise), or `nil` when nothing reads.
  private func previewTickEvent() -> ScrySingleFlow.Event {
    guard let guess = controller.previewGuess else {
      return .previewTick(key: nil, confident: false)
    }
    return .previewTick(key: guess.card?.id ?? guess.name, confident: guess.confident)
  }

  /// "Add to Scanned" from the review sheet: persist, remember where the card
  /// sat (cooldown re-arms on movement from here), and advance the flow.
  private func acceptSingle(_ card: CardRecord) {
    addToScanned(card)
    singleCommittedCentroid = subjectCentroid(controller.detectedCards)
    review = nil
    applySingle(.reviewClosed(added: true))
  }

  /// Cooldown watchdog: the accepted card moving (or leaving) re-arms passive
  /// tracking, exactly like bulk placement.
  private func trackSingleMovement(_ cards: [ScryDetectedCard]) {
    guard case .cooldown = flow else { return }
    switch ScryBulkPlacement.movement(
      detectedCentroid: subjectCentroid(cards),
      committedCentroid: singleCommittedCentroid,
      hasCommittedCard: true,
      threshold: movementThreshold
    ) {
    case .adoptBaseline(let centroid):
      singleCommittedCentroid = centroid
    case .rearm:
      singleCommittedCentroid = nil
      applySingle(.subjectMoved)
    case .hold:
      break
    }
  }

  private func resetSingle() {
    flow = .idle
    singleCommittedCentroid = nil
    showNoCardFlash = false
  }

  private func flashNoCard() {
    ScrySound.failed()
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    showNoCardFlash = true
    Task {
      try? await Task.sleep(for: .seconds(1.6))
      showNoCardFlash = false
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
    switch ScryBulkPlacement.movement(
      detectedCentroid: subjectCentroid(cards),
      committedCentroid: committedCentroid,
      hasCommittedCard: committedCardID != nil,
      threshold: movementThreshold
    ) {
    case .adoptBaseline(let centroid):
      // Commit didn't capture a baseline; lock onto the card now in frame instead of
      // re-arming, so it isn't rescanned. A genuine swap is still caught by
      // considerForBulk (a different confident card re-arms regardless).
      committedCentroid = centroid
    case .rearm:
      armed = true
      committedCentroid = nil
      rejectedIDs = []
      stableKey = nil
      stableCount = 0
    case .hold:
      break
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
      await controller.start(database: model.database, imageCache: model.imageCache)
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
       FileManager.default.fileExists(atPath: path) {
      // Decode off the main thread (and cache) via LocalCardImage instead of
      // UIImage(contentsOfFile:) in the body, which blocked the Scry result sheet on the
      // main thread while the full image decoded.
      LocalCardImage(path: path, cornerRadius: 12, contentMode: .fit)
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
