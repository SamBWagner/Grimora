import SwiftUI

struct ManaCostView: View {
    var manaCost: String
    var palette: GrimoraPalette
    var symbolSize: CGFloat = 18

    private var symbols: [ManaCostSymbol] {
        ManaCostSymbolParser.symbols(in: manaCost)
    }

    var body: some View {
        if !symbols.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    ManaSymbolView(
                        symbol: symbol,
                        palette: palette,
                        size: symbolSize
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mana cost \(ManaCostSymbolParser.accessibilityText(for: manaCost))")
        }
    }
}

struct ManaSymbolView: View {
    var symbol: ManaCostSymbol
    var palette: GrimoraPalette
    var size: CGFloat

    var body: some View {
        ZStack {
            symbolBackground

            Circle()
                .strokeBorder(symbol.borderColor, lineWidth: 0.75)

            symbolContent
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var symbolBackground: some View {
        switch symbol.background {
        case let .solid(color):
            Circle()
                .fill(color)
        case let .gradient(colors):
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    @ViewBuilder
    private var symbolContent: some View {
        if let systemImage = symbol.systemImageName {
            Image(systemName: systemImage)
                .font(.system(size: size * symbol.imageScale, weight: .bold))
                .foregroundStyle(symbol.foregroundColor)
                .accessibilityHidden(true)
        } else {
            Text(symbol.displayText)
                .font(.system(size: size * symbol.textScale, weight: .heavy, design: .rounded))
                .foregroundStyle(symbol.foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(width: size * 0.82, height: size * 0.82)
                .accessibilityHidden(true)
        }
    }
}

struct ManaCostSymbol: Equatable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    var displayText: String {
        switch rawValue {
        case "T":
            return "T"
        case "Q":
            return "Q"
        case "E":
            return "E"
        default:
            return rawValue.replacingOccurrences(of: "/", with: "\u{2044}")
        }
    }

    var systemImageName: String? {
        guard components.count == 1 else {
            return nil
        }

        switch rawValue {
        case "W":
            return "sun.max.fill"
        case "U":
            return "drop.fill"
        case "B":
            return "skull.fill"
        case "R":
            return "flame.fill"
        case "G":
            return "leaf.fill"
        default:
            return nil
        }
    }

    var background: ManaSymbolBackground {
        let colors = components.compactMap(Self.componentColor)
        if colors.count > 1 {
            return .gradient(colors)
        }

        if let color = colors.first {
            return .solid(color)
        }

        switch rawValue {
        case "S":
            return .solid(Color(red: 0.82, green: 0.90, blue: 0.96))
        default:
            return .solid(Color(red: 0.68, green: 0.68, blue: 0.64))
        }
    }

    var foregroundColor: Color {
        switch rawValue {
        case "W", "S":
            return Color(red: 0.16, green: 0.14, blue: 0.10)
        default:
            if components.contains("W"), components.count == 1 {
                return Color(red: 0.16, green: 0.14, blue: 0.10)
            }
            return Color(red: 0.96, green: 0.94, blue: 0.88)
        }
    }

    var borderColor: Color {
        switch rawValue {
        case "W":
            return Color(red: 0.50, green: 0.43, blue: 0.28).opacity(0.75)
        case "S":
            return Color(red: 0.42, green: 0.56, blue: 0.68).opacity(0.7)
        default:
            return Color.black.opacity(0.35)
        }
    }

    var textScale: CGFloat {
        switch displayText.count {
        case 0...1:
            return 0.66
        case 2:
            return 0.56
        case 3:
            return 0.45
        default:
            return 0.36
        }
    }

    var imageScale: CGFloat {
        switch rawValue {
        case "B":
            return 0.62
        default:
            return 0.64
        }
    }

    private var components: [String] {
        rawValue
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).uppercased() }
    }

    private static func componentColor(_ component: String) -> Color? {
        switch component {
        case "W":
            return Color(red: 0.92, green: 0.84, blue: 0.60)
        case "U":
            return Color(red: 0.16, green: 0.48, blue: 0.82)
        case "B":
            return Color(red: 0.18, green: 0.17, blue: 0.17)
        case "R":
            return Color(red: 0.82, green: 0.20, blue: 0.14)
        case "G":
            return Color(red: 0.20, green: 0.56, blue: 0.26)
        default:
            return nil
        }
    }
}

enum ManaSymbolBackground {
    case solid(Color)
    case gradient([Color])
}

enum ManaCostSymbolParser {
    static func symbols(in manaCost: String) -> [ManaCostSymbol] {
        let trimmed = manaCost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var symbols: [ManaCostSymbol] = []
        var token = ""
        var isInsideSymbol = false

        for character in trimmed {
            switch character {
            case "{":
                if isInsideSymbol, !token.isEmpty {
                    symbols.append(ManaCostSymbol(rawValue: token))
                }
                token = ""
                isInsideSymbol = true
            case "}":
                if isInsideSymbol, !token.isEmpty {
                    symbols.append(ManaCostSymbol(rawValue: token))
                }
                token = ""
                isInsideSymbol = false
            default:
                if isInsideSymbol {
                    token.append(character)
                }
            }
        }

        if symbols.isEmpty {
            return [ManaCostSymbol(rawValue: trimmed)]
        }
        return symbols
    }

    static func accessibilityText(for manaCost: String) -> String {
        let symbols = symbols(in: manaCost)
        guard !symbols.isEmpty else {
            return "none"
        }

        return symbols
            .map { accessibilityText(for: $0) }
            .joined(separator: " ")
    }

    private static func accessibilityText(for symbol: ManaCostSymbol) -> String {
        let rawValue = symbol.rawValue
        let parts = rawValue
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).uppercased() }

        if parts.count > 1 {
            if parts.contains("P"), let coloredPart = parts.first(where: { $0 != "P" }) {
                return "\(accessibilityName(for: coloredPart)) phyrexian"
            }
            return parts
                .map { accessibilityName(for: $0) }
                .joined(separator: " ")
        }

        return accessibilityName(for: rawValue)
    }

    private static func accessibilityName(for symbol: String) -> String {
        switch symbol {
        case "W":
            return "white"
        case "U":
            return "blue"
        case "B":
            return "black"
        case "R":
            return "red"
        case "G":
            return "green"
        case "C":
            return "colorless"
        case "S":
            return "snow"
        case "T":
            return "tap"
        case "Q":
            return "untap"
        case "E":
            return "energy"
        case "X", "Y", "Z":
            return symbol
        default:
            return symbol
        }
    }
}
