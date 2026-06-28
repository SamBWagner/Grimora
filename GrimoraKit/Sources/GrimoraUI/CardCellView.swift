import Foundation
import GrimoraCore
import SwiftUI

let cardArtworkAspectRatio: CGFloat = 0.716

struct CardCellView: View {
    private static let rotatedArtworkGridOverflowAllowance: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var hasOverflowingArtwork = false

    var card: CardRecord
    var showsArtworkControls = true
    var onArtworkOverflowChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardArtworkView(
                card: card,
                showsControls: showsArtworkControls,
                maximumVisualWidthExpansion: Self.rotatedArtworkGridOverflowAllowance,
                onVisualOverflowChange: updateArtworkOverflow
            )
                .shadow(
                    color: isHovered ? palette.shadow.color : palette.shadow.color.opacity(0.75),
                    radius: isHovered ? 8 : 5,
                    x: 0,
                    y: isHovered ? 5 : 3
                )

            CardIdentityLabel(card: card)
        }
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.cardSurface.color.opacity(isHovered ? 1 : 0.88))
        }
        .grimoraGridCardInteraction(isHovered: $isHovered)
        .zIndex(hasOverflowingArtwork ? 10 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.hasExistingDisplayImage ? "card-cell-\(card.id)" : "text-only-card-cell-\(card.id)")
    }

    private var palette: GrimoraPalette {
        .cached(for: colorScheme)
    }

    private func updateArtworkOverflow(_ isOverflowing: Bool) {
        if hasOverflowingArtwork != isOverflowing {
            hasOverflowingArtwork = isOverflowing
        }
        onArtworkOverflowChange(isOverflowing)
    }
}

struct CardArtworkView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedVariantID: CardArtworkVariant.ID?
    @State private var includesLandscapeRotation = false
    @State private var displayedRotationDegrees: Double?
    @State private var flipAngleDegrees: Double = 0
    @State private var artworkOpacity: Double = 1
    @State private var activeTransition: CardArtworkActiveTransition?
    @State private var transitionOutgoingVariant: CardArtworkVariant?
    @State private var transitionIncomingVariant: CardArtworkVariant?
    @State private var transitionProgress: Double = 0
    @State private var isTransitioning = false
    @State private var transitionTask: Task<Void, Never>?

    var card: CardRecord
    var cornerRadius: CGFloat = 8
    var preferredQuality: CardImageQuality = .normal
    var fallbackImagePath: String?
    var accessibilityHidden = true
    var showsControls = true
    var showsPreviewLoadingIndicator = false
    /// When true, the self-animating holographic foil shimmer is drawn over the artwork.
    var isFoil = false
    /// Sheen strength for the foil shimmer. Defaults to the full detail-pane look; grids pass
    /// a restrained value so a dense wall of foils doesn't read as noisy.
    var foilIntensity: Double = 1.0
    var maximumVisualWidthExpansion: CGFloat?
    var onVisualOverflowChange: (Bool) -> Void = { _ in }
    var onLandscapeLayoutChange: (Bool) -> Void = { _ in }

    static let controlHitSize = CGSize(width: 54, height: 54)

    @ViewBuilder
    var body: some View {
        artworkContent
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var artworkContent: some View {
        presentedArtwork
        .overlay(alignment: .bottomTrailing) {
            cycleButton
        }
        .onChange(of: card.id) { _, _ in
            resetVariantSelection()
        }
        .onChange(of: variantIDs) { _, _ in
            keepSelectedVariantValid()
        }
        .onChange(of: hasVisualOverflow) { _, hasOverflow in
            onVisualOverflowChange(hasOverflow)
        }
        .onChange(of: usesLandscapeArtworkLayout) { _, usesLandscapeLayout in
            onLandscapeLayoutChange(usesLandscapeLayout)
        }
        .onAppear {
            onVisualOverflowChange(hasVisualOverflow)
            onLandscapeLayoutChange(usesLandscapeArtworkLayout)
        }
        .onDisappear {
            onVisualOverflowChange(false)
            onLandscapeLayoutChange(false)
        }
    }

    @ViewBuilder
    private var presentedArtwork: some View {
        if let activeTransition,
           let transitionOutgoingVariant,
           let transitionIncomingVariant {
            switch activeTransition {
            case .flip:
                CardArtworkFlipTransitionView(
                    outgoingRotationDegrees: transitionOutgoingVariant.rotation.degrees,
                    incomingRotationDegrees: transitionIncomingVariant.rotation.degrees,
                    progress: transitionProgress,
                    usesLandscapeLayout: usesLandscapeArtworkLayout,
                    maximumVisualWidthExpansion: maximumVisualWidthExpansion
                ) {
                    artwork(for: transitionOutgoingVariant)
                } incoming: {
                    artwork(for: transitionIncomingVariant)
                }
            case .crossfade:
                CardArtworkCrossfadeTransitionView(
                    outgoingRotationDegrees: transitionOutgoingVariant.rotation.degrees,
                    incomingRotationDegrees: transitionIncomingVariant.rotation.degrees,
                    progress: transitionProgress,
                    usesLandscapeLayout: usesLandscapeArtworkLayout,
                    maximumVisualWidthExpansion: maximumVisualWidthExpansion
                ) {
                    artwork(for: transitionOutgoingVariant)
                } incoming: {
                    artwork(for: transitionIncomingVariant)
                }
            }
        } else {
            CardArtworkMotionContainer(
                rotationDegrees: effectiveRotationDegrees,
                flipAngleDegrees: flipAngleDegrees,
                opacity: artworkOpacity,
                usesLandscapeLayout: usesLandscapeArtworkLayout,
                maximumVisualWidthExpansion: maximumVisualWidthExpansion
            ) {
                artwork(for: selectedVariant)
            }
        }
    }

    @ViewBuilder
    private func artwork(for variant: CardArtworkVariant?) -> some View {
        if let variant, let path = variant.imagePath ?? fallbackPath(for: variant) {
            CardArtworkVariantImage(
                path: path,
                cornerRadius: cornerRadius,
                accessibilityHidden: accessibilityHidden,
                onImageSizeChange: handleImageSizeChange
            )
            .overlay { foilOverlay }
        } else if variants.isEmpty, let fallbackImagePath {
            CardArtworkVariantImage(
                path: fallbackImagePath,
                cornerRadius: cornerRadius,
                accessibilityHidden: accessibilityHidden,
                onImageSizeChange: handleImageSizeChange
            )
            .overlay { foilOverlay }
        } else {
            TextOnlyCardArtView(
                card: card,
                palette: palette,
                showsLoadingIndicator: showsPreviewLoadingIndicator
            )
        }
    }

    @ViewBuilder
    private var foilOverlay: some View {
        if isFoil {
            CardFoilShimmerOverlay(
                cornerRadius: cornerRadius,
                seed: card.foilSeed,
                intensity: foilIntensity
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var variants: [CardArtworkVariant] {
        CardArtworkPresentationResolver.variants(
            for: card,
            preferredQuality: preferredQuality,
            includesLandscapeRotation: includesLandscapeRotation
        )
    }

    private var variantIDs: [CardArtworkVariant.ID] {
        variants.map(\.id)
    }

    private var selectedVariant: CardArtworkVariant? {
        if let selectedVariantID,
           let selected = variants.first(where: { $0.id == selectedVariantID }) {
            return selected
        }

        return variants.first
    }

    @ViewBuilder
    private var cycleButton: some View {
        if showsControls, variants.count > 1, let nextVariant {
            Button {
                cycleVariant()
            } label: {
                CardArtworkCycleIcon(kind: nextVariant.isRotated ? .rotate : .flip)
                    .foregroundStyle(palette.primaryText.color)
                    .frame(width: 30, height: 30)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(palette.hairline.color, lineWidth: 1)
                    }
                    .shadow(color: palette.shadow.color.opacity(0.28), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help(cycleAccessibilityLabel(for: nextVariant))
            .accessibilityLabel(cycleAccessibilityLabel(for: nextVariant))
            .accessibilityValue(currentVariantAccessibilityValue)
            .accessibilityIdentifier("card-artwork-cycle-\(card.id)")
            .disabled(isTransitioning)
        }
    }

    private var nextVariant: CardArtworkVariant? {
        guard variants.count > 1 else {
            return nil
        }

        let currentID = selectedVariant?.id
        let currentIndex = currentID.flatMap { id in
            variants.firstIndex(where: { $0.id == id })
        } ?? 0
        return variants[(currentIndex + 1) % variants.count]
    }

    private func cycleVariant() {
        guard !isTransitioning,
              let currentVariant = selectedVariant,
              let nextVariant
        else {
            return
        }

        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            await animateTransition(from: currentVariant, to: nextVariant)
        }
    }

    private func resetVariantSelection() {
        transitionTask?.cancel()
        selectedVariantID = nil
        includesLandscapeRotation = false
        displayedRotationDegrees = nil
        flipAngleDegrees = 0
        artworkOpacity = 1
        clearActiveTransition()
        isTransitioning = false
    }

    private func keepSelectedVariantValid() {
        guard let selectedVariantID,
              variants.contains(where: { $0.id == selectedVariantID })
        else {
            self.selectedVariantID = nil
            displayedRotationDegrees = nil
            return
        }
    }

    @MainActor
    private func animateTransition(
        from currentVariant: CardArtworkVariant,
        to targetVariant: CardArtworkVariant
    ) async {
        isTransitioning = true
        let plan = CardArtworkMotionPlan.transition(from: currentVariant, to: targetVariant)

        if reduceMotion {
            await animateReducedMotionTransition(from: currentVariant, to: targetVariant)
        } else {
            switch plan.kind {
            case .none:
                commitVariant(targetVariant)
            case .rotate:
                await animateRotationTransition(from: currentVariant, to: targetVariant, plan: plan)
            case .flip:
                await animateFlipTransition(from: currentVariant, to: targetVariant)
            }
        }

        guard !Task.isCancelled else {
            return
        }

        displayedRotationDegrees = nil
        flipAngleDegrees = 0
        artworkOpacity = 1
        clearActiveTransition()
        isTransitioning = false
    }

    @MainActor
    private func animateRotationTransition(
        from currentVariant: CardArtworkVariant,
        to targetVariant: CardArtworkVariant,
        plan: CardArtworkMotionPlan
    ) async {
        displayedRotationDegrees = currentVariant.rotation.degrees
        withAnimation(.easeInOut(duration: Self.rotationAnimationDuration)) {
            displayedRotationDegrees = currentVariant.rotation.degrees + plan.rotationDeltaDegrees
        }

        guard await sleep(seconds: Self.rotationAnimationDuration) else {
            return
        }

        commitVariant(targetVariant)
    }

    @MainActor
    private func animateFlipTransition(
        from currentVariant: CardArtworkVariant,
        to targetVariant: CardArtworkVariant
    ) async {
        withoutAnimation {
            activeTransition = .flip
            transitionOutgoingVariant = currentVariant
            transitionIncomingVariant = targetVariant
            transitionProgress = 0
        }

        withAnimation(.easeInOut(duration: Self.flipAnimationDuration)) {
            transitionProgress = 1
        }

        guard await sleep(seconds: Self.flipAwayAnimationDuration) else {
            return
        }

        withoutAnimation {
            commitVariant(targetVariant)
        }

        guard await sleep(seconds: Self.flipSettleAnimationDuration) else {
            return
        }
    }

    @MainActor
    private func animateReducedMotionTransition(
        from currentVariant: CardArtworkVariant,
        to targetVariant: CardArtworkVariant
    ) async {
        withoutAnimation {
            activeTransition = .crossfade
            transitionOutgoingVariant = currentVariant
            transitionIncomingVariant = targetVariant
            transitionProgress = 0
        }

        withAnimation(.easeInOut(duration: Self.reducedMotionAnimationDuration)) {
            transitionProgress = 1
        }

        guard await sleep(seconds: Self.reducedMotionAnimationDuration / 2) else {
            return
        }

        withoutAnimation {
            commitVariant(targetVariant)
        }

        _ = await sleep(seconds: Self.reducedMotionAnimationDuration / 2)
    }

    private func commitVariant(_ variant: CardArtworkVariant) {
        selectedVariantID = variant.id
    }

    private func clearActiveTransition() {
        activeTransition = nil
        transitionOutgoingVariant = nil
        transitionIncomingVariant = nil
        transitionProgress = 0
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    private func sleep(seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func fallbackPath(for variant: CardArtworkVariant) -> String? {
        guard variant.source == .card,
              variant.rotation == .none
        else {
            return nil
        }

        return fallbackImagePath
    }

    private func handleImageSizeChange(_ size: CGSize) {
        guard size.width > size.height, !includesLandscapeRotation else {
            return
        }

        includesLandscapeRotation = true
    }

    private func cycleAccessibilityLabel(for variant: CardArtworkVariant) -> String {
        if variant.isRotated {
            return "Rotate card art"
        }

        return "Show \(variant.title)"
    }

    private var currentVariantAccessibilityValue: String {
        guard let selectedVariant else {
            return "No artwork variant"
        }

        return "Showing \(selectedVariant.id)"
    }

    private var effectiveRotationDegrees: Double {
        displayedRotationDegrees ?? selectedVariant?.rotation.degrees ?? 0
    }

    private var usesLandscapeArtworkLayout: Bool {
        reservesLandscapeArtworkLayout
            || activeArtworkUsesLandscapeLayout
    }

    private var reservesLandscapeArtworkLayout: Bool {
        variants.first.map { cardArtworkIsQuarterTurn($0.rotation.degrees) } == true
    }

    private var activeArtworkUsesLandscapeLayout: Bool {
        cardArtworkIsQuarterTurn(effectiveRotationDegrees)
            || transitionOutgoingVariant.map { cardArtworkIsQuarterTurn($0.rotation.degrees) } == true
            || transitionIncomingVariant.map { cardArtworkIsQuarterTurn($0.rotation.degrees) } == true
    }

    private var hasVisualOverflow: Bool {
        false
    }

    private var palette: GrimoraPalette {
        .cached(for: colorScheme)
    }

    private static let rotationAnimationDuration: TimeInterval = 0.18
    private static let flipAwayAnimationDuration: TimeInterval = 0.14
    private static let flipSettleAnimationDuration: TimeInterval = 0.16
    private static let flipAnimationDuration = flipAwayAnimationDuration + flipSettleAnimationDuration
    private static let reducedMotionAnimationDuration: TimeInterval = 0.12
}

private enum CardArtworkActiveTransition {
    case flip
    case crossfade
}

private enum CardArtworkCycleIconKind {
    case flip
    case rotate
}

private struct CardArtworkCycleIcon: View {
    var kind: CardArtworkCycleIconKind

    var body: some View {
        ZStack {
            switch kind {
            case .rotate:
                Image(systemName: "rotate.right.fill")
                    .font(.system(size: 14, weight: .bold))
            case .flip:
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(lineWidth: 1.7)
                    .frame(width: 13, height: 18)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 8.5, weight: .heavy))
                    .offset(y: 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CardArtworkMotionContainer<Content: View>: View {
    @Environment(\.cardArtworkViewportFrame) private var cardArtworkViewportFrame

    var rotationDegrees: Double
    var flipAngleDegrees: Double
    var opacity: Double
    var usesLandscapeLayout: Bool
    var maximumVisualWidthExpansion: CGFloat?
    let content: Content

    init(
        rotationDegrees: Double,
        flipAngleDegrees: Double,
        opacity: Double,
        usesLandscapeLayout: Bool,
        maximumVisualWidthExpansion: CGFloat?,
        @ViewBuilder content: () -> Content
    ) {
        self.rotationDegrees = rotationDegrees
        self.flipAngleDegrees = flipAngleDegrees
        self.opacity = opacity
        self.usesLandscapeLayout = usesLandscapeLayout
        self.maximumVisualWidthExpansion = maximumVisualWidthExpansion
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let sourceSize = cardArtworkSourceSize(
                forVisualSize: proxy.size,
                rotationDegrees: rotationDegrees,
                usesLandscapeLayout: usesLandscapeLayout
            )
            let overflowTransform = cardArtworkOverflowTransform(
                for: sourceSize,
                frame: proxy.frame(in: .global),
                rotationDegrees: rotationDegrees,
                viewportFrame: resolvedCardArtworkViewportFrame(cardArtworkViewportFrame),
                maximumVisualWidth: maximumVisualWidth(for: proxy.size)
            )

            content
                .frame(width: sourceSize.width, height: sourceSize.height)
                .scaleEffect(overflowTransform.scale)
                .rotationEffect(.degrees(rotationDegrees))
                .cardArtworkFlipRotation(flipAngleDegrees)
                .opacity(opacity)
                .position(
                    x: proxy.size.width / 2 + overflowTransform.offsetX,
                    y: proxy.size.height / 2
                )
        }
        .aspectRatio(
            cardArtworkVisualAspectRatio(
                baseAspectRatio: cardArtworkAspectRatio,
                usesLandscapeLayout: usesLandscapeLayout
            ),
            contentMode: .fit
        )
    }

    private func maximumVisualWidth(for size: CGSize) -> CGFloat? {
        maximumVisualWidthExpansion.map { size.width + $0 }
    }
}

private struct CardArtworkFlipTransitionView<Outgoing: View, Incoming: View>: View {
    @Environment(\.cardArtworkViewportFrame) private var cardArtworkViewportFrame

    var outgoingRotationDegrees: Double
    var incomingRotationDegrees: Double
    var progress: Double
    var usesLandscapeLayout: Bool
    var maximumVisualWidthExpansion: CGFloat?
    let outgoing: Outgoing
    let incoming: Incoming

    init(
        outgoingRotationDegrees: Double,
        incomingRotationDegrees: Double,
        progress: Double,
        usesLandscapeLayout: Bool,
        maximumVisualWidthExpansion: CGFloat?,
        @ViewBuilder outgoing: () -> Outgoing,
        @ViewBuilder incoming: () -> Incoming
    ) {
        self.outgoingRotationDegrees = outgoingRotationDegrees
        self.incomingRotationDegrees = incomingRotationDegrees
        self.progress = progress
        self.usesLandscapeLayout = usesLandscapeLayout
        self.maximumVisualWidthExpansion = maximumVisualWidthExpansion
        self.outgoing = outgoing()
        self.incoming = incoming()
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportFrame = resolvedCardArtworkViewportFrame(cardArtworkViewportFrame)
            let outgoingSourceSize = sourceSize(
                for: proxy.size,
                rotationDegrees: outgoingRotationDegrees
            )
            let incomingSourceSize = sourceSize(
                for: proxy.size,
                rotationDegrees: incomingRotationDegrees
            )
            let outgoingTransform = cardArtworkOverflowTransform(
                for: outgoingSourceSize,
                frame: proxy.frame(in: .global),
                rotationDegrees: outgoingRotationDegrees,
                viewportFrame: viewportFrame,
                maximumVisualWidth: maximumVisualWidth(for: proxy.size)
            )
            let incomingTransform = cardArtworkOverflowTransform(
                for: incomingSourceSize,
                frame: proxy.frame(in: .global),
                rotationDegrees: incomingRotationDegrees,
                viewportFrame: viewportFrame,
                maximumVisualWidth: maximumVisualWidth(for: proxy.size)
            )

            ZStack {
                transitionLayer(
                    outgoing,
                    size: outgoingSourceSize,
                    rotationDegrees: outgoingRotationDegrees,
                    flipDegrees: outgoingFlipDegrees,
                    opacity: progress <= 0.52 ? 1 : 0,
                    transform: outgoingTransform
                )

                transitionLayer(
                    incoming,
                    size: incomingSourceSize,
                    rotationDegrees: incomingRotationDegrees,
                    flipDegrees: incomingFlipDegrees,
                    opacity: progress >= 0.48 ? 1 : 0,
                    transform: incomingTransform
                )
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(
            cardArtworkVisualAspectRatio(
                baseAspectRatio: cardArtworkAspectRatio,
                usesLandscapeLayout: usesLandscapeLayout
            ),
            contentMode: .fit
        )
    }

    private var outgoingFlipDegrees: Double {
        -90 * min(max(progress / 0.5, 0), 1)
    }

    private var incomingFlipDegrees: Double {
        90 * (1 - min(max((progress - 0.5) / 0.5, 0), 1))
    }

    private func transitionLayer<Layer: View>(
        _ layer: Layer,
        size: CGSize,
        rotationDegrees: Double,
        flipDegrees: Double,
        opacity: Double,
        transform: CardArtworkOverflowTransform
    ) -> some View {
        layer
            .frame(width: size.width, height: size.height)
            .scaleEffect(transform.scale)
            .rotationEffect(.degrees(rotationDegrees))
            .cardArtworkFlipRotation(flipDegrees)
            .opacity(opacity)
            .offset(x: transform.offsetX)
    }

    private func maximumVisualWidth(for size: CGSize) -> CGFloat? {
        maximumVisualWidthExpansion.map { size.width + $0 }
    }

    private func sourceSize(
        for visualSize: CGSize,
        rotationDegrees: Double
    ) -> CGSize {
        cardArtworkSourceSize(
            forVisualSize: visualSize,
            rotationDegrees: rotationDegrees,
            usesLandscapeLayout: usesLandscapeLayout
        )
    }
}

private struct CardArtworkCrossfadeTransitionView<Outgoing: View, Incoming: View>: View {
    @Environment(\.cardArtworkViewportFrame) private var cardArtworkViewportFrame

    var outgoingRotationDegrees: Double
    var incomingRotationDegrees: Double
    var progress: Double
    var usesLandscapeLayout: Bool
    var maximumVisualWidthExpansion: CGFloat?
    let outgoing: Outgoing
    let incoming: Incoming

    init(
        outgoingRotationDegrees: Double,
        incomingRotationDegrees: Double,
        progress: Double,
        usesLandscapeLayout: Bool,
        maximumVisualWidthExpansion: CGFloat?,
        @ViewBuilder outgoing: () -> Outgoing,
        @ViewBuilder incoming: () -> Incoming
    ) {
        self.outgoingRotationDegrees = outgoingRotationDegrees
        self.incomingRotationDegrees = incomingRotationDegrees
        self.progress = progress
        self.usesLandscapeLayout = usesLandscapeLayout
        self.maximumVisualWidthExpansion = maximumVisualWidthExpansion
        self.outgoing = outgoing()
        self.incoming = incoming()
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportFrame = resolvedCardArtworkViewportFrame(cardArtworkViewportFrame)
            let outgoingSourceSize = sourceSize(
                for: proxy.size,
                rotationDegrees: outgoingRotationDegrees
            )
            let incomingSourceSize = sourceSize(
                for: proxy.size,
                rotationDegrees: incomingRotationDegrees
            )
            let outgoingTransform = cardArtworkOverflowTransform(
                for: outgoingSourceSize,
                frame: proxy.frame(in: .global),
                rotationDegrees: outgoingRotationDegrees,
                viewportFrame: viewportFrame,
                maximumVisualWidth: maximumVisualWidth(for: proxy.size)
            )
            let incomingTransform = cardArtworkOverflowTransform(
                for: incomingSourceSize,
                frame: proxy.frame(in: .global),
                rotationDegrees: incomingRotationDegrees,
                viewportFrame: viewportFrame,
                maximumVisualWidth: maximumVisualWidth(for: proxy.size)
            )

            ZStack {
                crossfadeLayer(
                    outgoing,
                    size: outgoingSourceSize,
                    rotationDegrees: outgoingRotationDegrees,
                    opacity: 1 - progress,
                    transform: outgoingTransform
                )

                crossfadeLayer(
                    incoming,
                    size: incomingSourceSize,
                    rotationDegrees: incomingRotationDegrees,
                    opacity: progress,
                    transform: incomingTransform
                )
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(
            cardArtworkVisualAspectRatio(
                baseAspectRatio: cardArtworkAspectRatio,
                usesLandscapeLayout: usesLandscapeLayout
            ),
            contentMode: .fit
        )
    }

    private func crossfadeLayer<Layer: View>(
        _ layer: Layer,
        size: CGSize,
        rotationDegrees: Double,
        opacity: Double,
        transform: CardArtworkOverflowTransform
    ) -> some View {
        layer
            .frame(width: size.width, height: size.height)
            .scaleEffect(transform.scale)
            .rotationEffect(.degrees(rotationDegrees))
            .opacity(opacity)
            .offset(x: transform.offsetX)
    }

    private func maximumVisualWidth(for size: CGSize) -> CGFloat? {
        maximumVisualWidthExpansion.map { size.width + $0 }
    }

    private func sourceSize(
        for visualSize: CGSize,
        rotationDegrees: Double
    ) -> CGSize {
        cardArtworkSourceSize(
            forVisualSize: visualSize,
            rotationDegrees: rotationDegrees,
            usesLandscapeLayout: usesLandscapeLayout
        )
    }
}

private extension View {
    @ViewBuilder
    func cardArtworkFlipRotation(_ degrees: Double) -> some View {
        #if os(visionOS)
        rotation3DEffect(
            .degrees(degrees),
            axis: (x: 0, y: 1, z: 0)
        )
        #else
        rotation3DEffect(
            .degrees(degrees),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        #endif
    }
}

private struct CardArtworkVariantImage: View {
    var path: String
    var cornerRadius: CGFloat
    var accessibilityHidden: Bool
    var onImageSizeChange: (CGSize) -> Void

    var body: some View {
        baseImage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var baseImage: some View {
        LocalCardImage(
            path: path,
            cornerRadius: cornerRadius,
            accessibilityHidden: accessibilityHidden,
            onImageSizeChange: onImageSizeChange
        )
    }
}

struct CardIdentityLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    var card: CardRecord
    var nameFont: Font = .callout.weight(.semibold)
    var metadataFont: Font = .caption
    var nameLineLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.name)
                .font(nameFont)
                .lineLimit(nameLineLimit)
                .foregroundStyle(palette.primaryText.color)
                .minimumScaleFactor(0.82)

            Text("\(card.setCode.uppercased()) #\(card.collectorNumber)")
                .font(metadataFont)
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var palette: GrimoraPalette {
        .cached(for: colorScheme)
    }
}

private struct TextOnlyCardArtView: View {
    var card: CardRecord
    var palette: GrimoraPalette
    var showsLoadingIndicator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(4)
                .minimumScaleFactor(0.78)

            Text(card.typeLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(3)

            Spacer(minLength: 0)

            Text("\(card.setCode.uppercased()) #\(card.collectorNumber)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(0.716, contentMode: .fit)
        .background(palette.placeholderFill.color.opacity(0.65))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if showsLoadingIndicator {
                previewLoadingBadge
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier(showsLoadingIndicator ? "loading-card-art-\(card.id)" : "text-only-card-art-\(card.id)")
    }

    private var previewLoadingBadge: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)

            Text("Loading preview")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(palette.secondaryText.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading card preview")
    }
}

extension CardRecord {
    var isAwaitingDisplayImage: Bool {
        !hasExistingDisplayImage && hasRemoteDisplayImageSource
    }

    var displayImageAccessibilityValue: String {
        if hasExistingDisplayImage {
            return "Image"
        }

        if hasRemoteDisplayImageSource, !Self.remoteDisplayImagesAreDisabled {
            return "Loading Image"
        }

        return "Text Only"
    }

    private static var remoteDisplayImagesAreDisabled: Bool {
        ProcessInfo.processInfo.environment["GRIMORA_DISABLE_NETWORK"] == "1"
    }

    private var hasRemoteDisplayImageSource: Bool {
        let topLevelSources = [
            smallImageURL,
            normalImageURL,
            largeImageURL
        ]
        let faceSources = faces.flatMap { face in
            [
                face.smallImageURL,
                face.normalImageURL,
                face.largeImageURL
            ]
        }

        return (topLevelSources + faceSources).contains { value in
            guard let value else {
                return false
            }

            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
