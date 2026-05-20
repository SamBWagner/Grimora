import CoreGraphics
import GrimoraCore
import SwiftUI

#if os(iOS)
@preconcurrency import UIKit
#endif

struct CardArtworkOverflowTransform: Equatable {
    var scale: CGFloat
    var offsetX: CGFloat
}

func cardArtworkOverflowTransform(
    for size: CGSize,
    frame: CGRect,
    rotationDegrees: Double,
    viewportFrame: CGRect?,
    viewportInset: CGFloat = 10,
    maximumVisualWidth: CGFloat? = nil
) -> CardArtworkOverflowTransform {
    guard cardArtworkIsQuarterTurn(rotationDegrees),
          size.height > 0,
          frame.midX.isFinite,
          let viewportFrame,
          viewportFrame.width.isFinite,
          viewportFrame.width > 0
    else {
        return CardArtworkOverflowTransform(scale: 1, offsetX: 0)
    }

    let minimumViewportX = viewportFrame.minX + viewportInset
    let maximumViewportX = viewportFrame.maxX - viewportInset
    var availableWidth = max(1, maximumViewportX - minimumViewportX)
    if let maximumVisualWidth, maximumVisualWidth.isFinite, maximumVisualWidth > 0 {
        availableWidth = min(availableWidth, maximumVisualWidth)
    }
    let scale = min(availableWidth / size.height, 1)
    let visualWidth = size.height * scale
    let minimumCenterX = minimumViewportX + (visualWidth / 2)
    let maximumCenterX = maximumViewportX - (visualWidth / 2)

    guard minimumCenterX <= maximumCenterX else {
        return CardArtworkOverflowTransform(scale: scale, offsetX: 0)
    }

    let clampedCenterX = min(max(frame.midX, minimumCenterX), maximumCenterX)
    return CardArtworkOverflowTransform(scale: scale, offsetX: clampedCenterX - frame.midX)
}

func cardArtworkReservedLayoutWidth(
    baseWidth: CGFloat,
    aspectRatio: CGFloat,
    hasVisualOverflow: Bool
) -> CGFloat {
    guard hasVisualOverflow,
          baseWidth.isFinite,
          baseWidth > 0,
          aspectRatio.isFinite,
          aspectRatio > 0
    else {
        return baseWidth
    }

    return max(baseWidth, baseWidth / aspectRatio)
}

func cardArtworkVisualAspectRatio(
    baseAspectRatio: CGFloat,
    usesLandscapeLayout: Bool
) -> CGFloat {
    guard usesLandscapeLayout,
          baseAspectRatio.isFinite,
          baseAspectRatio > 0
    else {
        return baseAspectRatio
    }

    return 1 / baseAspectRatio
}

func cardArtworkSourceSize(
    forVisualSize visualSize: CGSize,
    usesLandscapeLayout: Bool
) -> CGSize {
    guard usesLandscapeLayout else {
        return visualSize
    }

    return CGSize(width: visualSize.height, height: visualSize.width)
}

func cardArtworkSourceSize(
    forVisualSize visualSize: CGSize,
    rotationDegrees: Double,
    usesLandscapeLayout: Bool,
    baseAspectRatio: CGFloat = cardArtworkAspectRatio
) -> CGSize {
    guard usesLandscapeLayout else {
        return visualSize
    }

    guard cardArtworkIsQuarterTurn(rotationDegrees) else {
        guard visualSize.height.isFinite,
              visualSize.height > 0,
              baseAspectRatio.isFinite,
              baseAspectRatio > 0
        else {
            return visualSize
        }

        return CGSize(
            width: visualSize.height * baseAspectRatio,
            height: visualSize.height
        )
    }

    return cardArtworkSourceSize(
        forVisualSize: visualSize,
        usesLandscapeLayout: true
    )
}

@MainActor
func resolvedCardArtworkViewportFrame(_ viewportFrame: CGRect?) -> CGRect? {
    if let viewportFrame {
        return viewportFrame
    }

    #if os(iOS)
    return UIApplication.shared.connectedScenes
        .compactMap { scene -> CGRect? in
            guard let windowScene = scene as? UIWindowScene else {
                return nil
            }

            return windowScene.screen.bounds
        }
        .first
    #else
    return nil
    #endif
}

func cardArtworkIsQuarterTurn(_ rotationDegrees: Double) -> Bool {
    let normalized = cardArtworkNormalizedRotationDegrees(rotationDegrees)
    return abs(normalized - 90) < 0.001 || abs(normalized - 270) < 0.001
}

func cardUsesDefaultLandscapeArtworkLayout(_ card: CardRecord) -> Bool {
    guard let defaultVariant = CardArtworkPresentationResolver.variants(for: card).first else {
        return false
    }

    return cardArtworkIsQuarterTurn(defaultVariant.rotation.degrees)
}

private func cardArtworkNormalizedRotationDegrees(_ rotationDegrees: Double) -> Double {
    let normalized = rotationDegrees.truncatingRemainder(dividingBy: 360)
    return normalized < 0 ? normalized + 360 : normalized
}

private struct CardArtworkViewportFrameEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

extension EnvironmentValues {
    var cardArtworkViewportFrame: CGRect? {
        get { self[CardArtworkViewportFrameEnvironmentKey.self] }
        set { self[CardArtworkViewportFrameEnvironmentKey.self] = newValue }
    }
}

private struct CardArtworkViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct CardArtworkViewportModifier: ViewModifier {
    @State private var viewportFrame: CGRect?

    func body(content: Content) -> some View {
        content
            .environment(\.cardArtworkViewportFrame, viewportFrame)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CardArtworkViewportFramePreferenceKey.self,
                        value: sanitized(proxy.frame(in: .global))
                    )
                }
            }
            .onPreferenceChange(CardArtworkViewportFramePreferenceKey.self) { frame in
                viewportFrame = frame
            }
    }

    private func sanitized(_ frame: CGRect) -> CGRect? {
        guard frame.minX.isFinite,
              frame.maxX.isFinite,
              frame.width.isFinite,
              frame.width > 0
        else {
            return nil
        }

        return frame
    }
}

extension View {
    func cardArtworkViewport() -> some View {
        modifier(CardArtworkViewportModifier())
    }
}
