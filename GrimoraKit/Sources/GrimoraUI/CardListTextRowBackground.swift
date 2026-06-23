import GrimoraCore
import SwiftUI

/// Row background for a card list text row: a colour-identity wash derived from
/// the card, with an accent overlay when the row is the active detail. Pure
/// presentation driven only by the card and palette.
struct CardListTextRowBackground: View {
    var card: CardRecord?
    var palette: GrimoraPalette
    var isActiveDetail: Bool

    var body: some View {
        ZStack {
            colorIdentityBackground
            if isActiveDetail {
                palette.accent.color
                    .opacity(palette.appBackground.red < 0.5 ? 0.22 : 0.14)
            }
        }
    }

    @ViewBuilder
    private var colorIdentityBackground: some View {
        switch colorIdentityStyle {
        case .colorless:
            rowColorlessColor
                .opacity(rowColorlessBackgroundOpacity)
        case let .mono(symbol):
            rowColor(for: symbol)
                .opacity(rowBackgroundOpacity)
        case let .pair(left, right):
            LinearGradient(
                colors: [
                    rowColor(for: left).opacity(rowBackgroundOpacity),
                    rowColor(for: right).opacity(rowBackgroundOpacity)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .gold:
            rowGoldColor
                .opacity(rowBackgroundOpacity)
        }
    }

    private var colorIdentityStyle: CardListTextRowColorIdentityStyle {
        CardListTextRowColorIdentityStyle(card: card)
    }

    private var rowBackgroundOpacity: Double {
        palette.appBackground.red < 0.5 ? 0.18 : 0.11
    }

    private var rowGoldColor: Color {
        Color(red: 0.86, green: 0.66, blue: 0.24)
    }

    private var rowColorlessColor: Color {
        Color(red: 0.54, green: 0.54, blue: 0.50)
    }

    private var rowColorlessBackgroundOpacity: Double {
        palette.appBackground.red < 0.5 ? 0.16 : 0.09
    }

    private func rowColor(for symbol: String) -> Color {
        switch symbol {
        case "W":
            return Color(red: 0.86, green: 0.78, blue: 0.56)
        case "U":
            return Color(red: 0.18, green: 0.48, blue: 0.86)
        case "B":
            return Color(red: 0.30, green: 0.24, blue: 0.36)
        case "R":
            return Color(red: 0.86, green: 0.24, blue: 0.18)
        case "G":
            return Color(red: 0.22, green: 0.62, blue: 0.32)
        default:
            return Color.clear
        }
    }
}
