import SwiftUI

/// The stamped mana-symbol layer of the mana-foil treatment. Tiles the app's own mana glyphs
/// (the same SF Symbols `ManaCostView` uses) in diagonal rows and embosses each one — a light
/// copy offset up-left, a dark copy offset down-right — so they read as raised stamps pressed
/// into the light-gradient foil drawn beneath (`grimoraFoilManaGradient`). Static (the symbols
/// don't animate); the foil sheen underneath provides the motion. Tuned values are baked in.
struct ManaFoilStampOverlay: View {
    var cornerRadius: CGFloat
    /// Master strength (1.0 detail / lower for grids) — scales how pronounced the emboss reads.
    var intensity: Double

    // The mana glyphs, matching `ManaCostSymbol.systemImageName` (W, U, B, R, G).
    private static let symbols = ["sun.max.fill", "drop.fill", "skull.fill", "flame.fill", "leaf.fill"]
    private static let patternScale = 4.5   // symbols across the card width
    private static let symbolFraction = 0.75 // symbol size relative to a cell
    private static let baseStrength = 0.35
    private static let resolveSize: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            let cell = size.width / Self.patternScale
            guard cell > 1 else { return }
            let scale = (cell * Self.symbolFraction) / Self.resolveSize
            let strength = Self.baseStrength * intensity
            let rows = Int((size.height / cell).rounded(.up)) + 1
            let columns = Int(Self.patternScale.rounded(.up)) + 1
            for row in 0...rows {
                for column in 0...columns {
                    let index = ((column + row * 2) % 5 + 5) % 5
                    guard let light = context.resolveSymbol(id: "L\(index)"),
                          let dark = context.resolveSymbol(id: "D\(index)") else { continue }
                    let centerX = (Double(column) + (row % 2 == 1 ? 0.5 : 0.0)) * cell
                    let centerY = Double(row) * cell
                    var tile = context
                    tile.translateBy(x: centerX, y: centerY)
                    tile.scaleBy(x: scale, y: scale)

                    var highlight = tile
                    highlight.blendMode = .plusLighter
                    highlight.opacity = strength * 0.9
                    highlight.draw(light, at: CGPoint(x: -1.1, y: -1.1), anchor: .center)

                    var shadow = tile
                    shadow.blendMode = .multiply
                    shadow.opacity = strength * 0.7
                    shadow.draw(dark, at: CGPoint(x: 1.1, y: 1.1), anchor: .center)
                }
            }
        } symbols: {
            ForEach(0..<5, id: \.self) { index in
                manaImage(index, tint: .white).tag("L\(index)")
                manaImage(index, tint: .black).tag("D\(index)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func manaImage(_ index: Int, tint: Color) -> some View {
        Image(systemName: Self.symbols[index])
            .resizable()
            .scaledToFit()
            .frame(width: Self.resolveSize, height: Self.resolveSize)
            .foregroundStyle(tint)
    }
}
