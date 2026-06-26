import SwiftUI

/// Framed artwork well for a dashboard list tile: a fixed-aspect, rounded,
/// hairline-bordered container with a platform-tuned shadow, wrapping either the
/// list's cover image or a placeholder.
struct CardCollectionOverviewTileArtwork: View {
    var item: CardCollectionOverviewItem
    var isSystemList: Bool
    var palette: GrimoraPalette
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat

    private static let artworkAspectRatio: CGFloat = 8.0 / 5.0

    var body: some View {
        Color.clear
            .aspectRatio(Self.artworkAspectRatio, contentMode: .fit)
            .overlay {
                CardCollectionOverviewTileArtworkContent(
                    item: item,
                    isSystemList: isSystemList,
                    palette: palette
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }
}

/// The image-or-placeholder content inside a tile's artwork well.
private struct CardCollectionOverviewTileArtworkContent: View {
    var item: CardCollectionOverviewItem
    var isSystemList: Bool
    var palette: GrimoraPalette

    @ViewBuilder
    var body: some View {
        if let imagePath = item.topCard?.listOverviewImagePath {
            LocalCardImage(
                path: imagePath,
                cornerRadius: 8,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.placeholderFill.color)

                Image(systemName: isSystemList ? "star" : "rectangle.stack")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityHidden(true)
            }
        }
    }
}
