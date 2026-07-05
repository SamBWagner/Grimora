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

  // The offered card's foil-aware value, resolved once when a confident offer
  // appears and read by the confirm chip (drag re-renders must not hit the DB).
  @State private var offeredPriceUSD: Double?

  // Bulk-mode workflow. The tuned state machine lives in ScryBulkCoordinator so the
  // Commander Re-scan flow shares one implementation; the tab keeps only the running
  // count for its "Auto-adding to Scanned" status.
  @State private var scannedCount = 0
  @State private var lastAddedName: String?
  @State private var bulk = ScryBulkCoordinator()

  private enum Mode: String { case single, bulk }

  private struct Review: Identifiable {
    let id = UUID()
    let kind: ScryReviewKind
    let card: CardRecord
    let priceUSD: Double?
  }

  /// Builds a review, resolving the card's foil-aware value up front so the sheet
  /// (accent + price line) matches the detail screen for foil-only cards.
  private func makeReview(kind: ScryReviewKind, card: CardRecord) -> Review {
    Review(kind: kind, card: card, priceUSD: model.scanTierPriceUSD(for: card))
  }

  /// How far (normalized) the card must move to count as a new placement.
  private let movementThreshold: CGFloat = 0.08

  /// Live price-tier thresholds from Settings, reread on access so edits take
  /// effect on the next scan without a restart.
  private var priceThresholds: ScryPriceThresholds { GrimoraScryPreferences.thresholds() }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      switch controller.authorization {
      case .authorized: authorized
      case .denied: ScryPermissionDeniedView()
      case .undetermined: ProgressView().tint(.white)
      }
    }
    .onAppear {
      bulk.onScanned = { addToScanned($0) }
      bulk.onNeedsReview = { card in review = makeReview(kind: .bulkUncertain, card: card) }
      syncCamera()
    }
    .onDisappear { controller.stop() }
    .onChange(of: isActive) { _, _ in syncCamera() }
    .onChange(of: scenePhase) { _, _ in syncCamera() }
    // Pause the camera entirely while the card detail pane is open — the user is
    // looking at a card, not the viewfinder, so there's no reason to keep the
    // capture session and Vision running under load.
    .onChange(of: model.selectedCard?.id) { _, _ in syncCamera() }
    .onChange(of: mode) { _, m in applyFocus(for: m); bulk.reset(); resetSingle() }
    // Drive stability off the per-cycle generation, not previewGuess —
    // a stably-recognized card produces an unchanged guess, so onChange(of:
    // previewGuess) would never fire the follow-up cycles and never commit.
    .onChange(of: controller.previewGeneration) { _, _ in
      switch mode {
      case .single: applySingle(previewTickEvent())
      case .bulk: bulk.consider(guess: controller.previewGuess, controller: controller)
      }
    }
    .onChange(of: controller.detectedCards) { _, cards in
      switch mode {
      case .single: trackSingleMovement(cards)
      case .bulk: bulk.trackMovement(cards: cards, controller: controller)
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
        review = makeReview(kind: .single, card: card)
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
        } else {
          bulk.reviewDismissed()
        }
      }
    ) { item in
      ScryReviewSheet(
        card: item.card,
        tier: priceThresholds.tier(forUSD: item.priceUSD),
        priceUSD: item.priceUSD,
        kind: item.kind,
        onAddToScanned: { acceptSingle(item.card) },
        onFullDetails: { review = nil; model.selectCard(item.card) },
        onCorrect: { bulk.acceptUncertain(item.card, controller: controller); review = nil },
        onIncorrect: { bulk.rejectUncertain(item.card); review = nil },
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        controller.focus(atDevicePoint: devicePoint)
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
        Text("Place a card — tap to focus")
      }
      Button { controller.refocusCenter() } label: { Image(systemName: "camera.metering.center.weighted") }
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
        thresholds: priceThresholds,
        priceUSD: offeredPriceUSD,
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
    // A tiered cue as the confident offer appears — the light click for cheap
    // cards, escalating "level-up" jingles for valuable ones. Fires once on the
    // verifying → offer transition (the chip for passive finds, the review sheet
    // for a manual tap); reopening an existing offer doesn't retrigger it.
    if case .verifying = flow,
       case .offer(let offer) = next,
       case .confident(let card) = offer.kind {
      // Foil-aware value so a foil-only card (nil non-foil `priceUSD`) celebrates
      // at its real worth. Resolved once here and reused by the chip.
      let priceUSD = model.scanTierPriceUSD(for: card)
      offeredPriceUSD = priceUSD
      ScrySound.tier(priceThresholds.tier(forUSD: priceUSD))
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
      review = makeReview(kind: .single, card: card)
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

  /// The bulk sink: persist to the Scanned collection and give scan feedback. The
  /// stability/placement machinery lives in `ScryBulkCoordinator`.
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
    case .bulk: controller.beginBulkFocus()
    case .single: controller.setFocusLocked(false)
    }
  }
}

/// Confirmation card shown after a scan (single) or for an uncertain bulk card.
struct ScryReviewSheet: View {
  let card: CardRecord
  let tier: ScryPriceTier
  /// The card's foil-aware value (`model.scanTierPriceUSD`), matching `tier` and
  /// the detail screen. `nil` hides the price line.
  var priceUSD: Double?
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
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(tier.hasBorder ? (tier.accentColor ?? .clear) : .clear, lineWidth: 3)
        )
        .shadow(color: tier.hasBorder ? (tier.accentColor ?? .clear).opacity(0.6) : .clear, radius: 12)

      VStack(spacing: 4) {
        Text(card.name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
        Text("\(card.setName) · \(card.setCode.uppercased()) \(card.collectorNumber)")
          .font(.subheadline).foregroundStyle(.secondary)
        if let price = priceUSD {
          Text(price, format: .currency(code: "USD"))
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tier.accentColor ?? .primary)
            .padding(.top, 2)
        }
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
          .tint(tier.accentColor)

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

enum ScryReviewKind { case single, bulkUncertain }

/// Shown when camera access is denied — routes the user to Settings.
struct ScryPermissionDeniedView: View {
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
