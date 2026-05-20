import CoreTransferable
import Foundation
import GrimoraCore
import UniformTypeIdentifiers

struct CardShareImage: Equatable, Transferable {
    var data: Data
    var filename: String
    var contentType: UTType

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .image) { shareImage in
            shareImage.data
        }
        .suggestedFileName { shareImage in
            shareImage.filename
        }
    }
}

struct CardShareContent: Equatable {
    var card: CardRecord

    var scryfallURL: URL {
        let setCode = Self.encodedPathSegment(card.setCode.lowercased())
        let collectorNumber = Self.encodedPathSegment(card.collectorNumber)
        return URL(string: "https://scryfall.com/card/\(setCode)/\(collectorNumber)")!
    }

    var imageShareItem: CardShareImage? {
        if let localPath = firstNonEmpty([
            card.largeImagePath,
            card.normalImagePath,
            card.smallImagePath,
            card.faces.first?.largeImagePath,
            card.faces.first?.normalImagePath,
            card.faces.first?.smallImagePath
        ]) {
            let url = Self.fileURL(from: localPath)
            guard let data = try? Data(contentsOf: url),
                  let contentType = Self.imageContentType(for: data, pathExtension: url.pathExtension)
            else {
                return nil
            }

            return CardShareImage(
                data: data,
                filename: Self.imageFilename(for: card, contentType: contentType),
                contentType: contentType
            )
        }

        return nil
    }

    var detailsMarkdown: String {
        var sections: [String] = []
        sections.append(headerSection)

        if !card.faces.isEmpty {
            sections.append(faceSection)
        } else if !card.oracleText.isEmpty {
            sections.append(card.oracleText)
        }

        if let flavorText = trimmed(card.flavorText), !flavorText.isEmpty {
            sections.append("_\(flavorText)_")
        }

        sections.append(printingSection)
        return sections.joined(separator: "\n\n")
    }

    private var headerSection: String {
        var lines = ["# \(card.name)"]
        appendField("Mana Cost", card.manaCost, to: &lines)
        appendField("Type", card.typeLine, to: &lines)
        appendField("Keywords", card.keywords.joined(separator: ", "), to: &lines)
        return lines.joined(separator: "\n")
    }

    private var faceSection: String {
        card.faces
            .map { face in
                var lines = ["## \(face.name)"]
                appendField("Type", face.typeLine, to: &lines)
                if !face.oracleText.isEmpty {
                    lines.append("")
                    lines.append(face.oracleText)
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    private var printingSection: String {
        var lines = ["## Printing"]
        appendBullet("Set", "\(card.setName) (\(card.setCode.uppercased()) #\(card.collectorNumber))", to: &lines)
        appendBullet("Rarity", card.rarity.capitalized, to: &lines)
        appendBullet("Released", card.releasedAt, to: &lines)
        appendBullet("Language", card.language?.uppercased(), to: &lines)
        appendBullet("Artist", card.artist, fallback: "Unknown", to: &lines)
        appendBullet("Mana Value", Self.number(card.manaValue), fallback: "Unknown", to: &lines)

        if let power = card.power, let toughness = card.toughness {
            appendBullet("Power/Toughness", "\(power)/\(toughness)", to: &lines)
        }

        appendBullet("Loyalty", card.loyalty, to: &lines)
        appendBullet("Colors", card.colors.joined(separator: ", "), to: &lines)
        appendBullet("Color Identity", card.colorIdentity.joined(separator: ", "), to: &lines)
        appendBullet("Produced Mana", card.producedMana.joined(separator: ", "), to: &lines)
        appendBullet("Games", card.games.map(\.capitalized).joined(separator: ", "), to: &lines)
        appendBullet("Finishes", card.finishes.map(\.capitalized).joined(separator: ", "), to: &lines)
        appendBullet("Prices", priceSummary, to: &lines)
        appendBullet("EDHREC", card.edhrecRank.map(String.init), fallback: "Unranked", to: &lines)
        appendBullet("Scryfall", scryfallURL.absoluteString, to: &lines)
        return lines.joined(separator: "\n")
    }

    private var priceSummary: String {
        [
            "USD \(Self.price(card.priceUSD))",
            "EUR \(Self.price(card.priceEUR))",
            "TIX \(Self.price(card.priceTIX))"
        ].joined(separator: " | ")
    }

    private func appendField(_ label: String, _ value: String?, to lines: inout [String]) {
        guard let value = trimmed(value), !value.isEmpty else {
            return
        }

        lines.append("**\(label):** \(value)")
    }

    private func appendBullet(
        _ label: String,
        _ value: String?,
        fallback: String? = nil,
        to lines: inout [String]
    ) {
        if let value = trimmed(value), !value.isEmpty {
            lines.append("- **\(label):** \(value)")
        } else if let fallback {
            lines.append("- **\(label):** \(fallback)")
        }
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { trimmed($0) }.first { !$0.isEmpty }
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func price(_ value: Double?) -> String {
        guard let value else {
            return "Unknown"
        }

        return priceFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func number(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }

        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func fileURL(from storedPath: String) -> URL {
        if let url = URL(string: storedPath), url.isFileURL {
            return url
        }

        return URL(fileURLWithPath: storedPath)
    }

    private static func imageContentType(for data: Data, pathExtension: String) -> UTType? {
        let bytes = [UInt8](data.prefix(16))

        if bytes.starts(with: [0xff, 0xd8, 0xff]) {
            return .jpeg
        }

        if bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
            return .png
        }

        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return .gif
        }

        if bytes.count >= 12,
           Array(bytes[0..<4]) == Array("RIFF".utf8),
           Array(bytes[8..<12]) == Array("WEBP".utf8),
           let webP = UTType(filenameExtension: "webp")
        {
            return webP
        }

        if !pathExtension.isEmpty,
           let type = UTType(filenameExtension: pathExtension),
           type.conforms(to: .image)
        {
            return type
        }

        return nil
    }

    private static func imageFilename(for card: CardRecord, contentType: UTType) -> String {
        let fallbackExtension = contentType.preferredFilenameExtension ?? "jpg"
        let rawName = "\(card.name) \(card.setCode.uppercased()) \(card.collectorNumber)"
        let sanitizedName = rawName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>#"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedName.isEmpty ? "Card Image" : sanitizedName
        return "\(baseName).\(fallbackExtension)"
    }

    private static func encodedPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
