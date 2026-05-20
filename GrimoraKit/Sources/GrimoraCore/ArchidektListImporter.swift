import Foundation

public struct ArchidektCardReference: Equatable, Sendable {
    public var quantity: Int
    public var name: String
    public var setCode: String?
    public var collectorNumber: String?
    public var categories: [String]
    public var scryfallID: String?
    public var sourceDescription: String

    public init(
        quantity: Int,
        name: String,
        setCode: String? = nil,
        collectorNumber: String? = nil,
        categories: [String] = [],
        scryfallID: String? = nil,
        sourceDescription: String
    ) {
        self.quantity = quantity
        self.name = name
        self.setCode = setCode
        self.collectorNumber = collectorNumber
        self.categories = categories
        self.scryfallID = scryfallID
        self.sourceDescription = sourceDescription
    }
}

public struct ArchidektSkippedLine: Equatable, Sendable {
    public var lineNumber: Int?
    public var text: String
    public var reason: String

    public init(lineNumber: Int?, text: String, reason: String) {
        self.lineNumber = lineNumber
        self.text = text
        self.reason = reason
    }
}

public struct ArchidektDeckImport: Equatable, Sendable {
    public var name: String?
    public var cards: [ArchidektCardReference]
    public var skippedLines: [ArchidektSkippedLine]

    public init(
        name: String? = nil,
        cards: [ArchidektCardReference],
        skippedLines: [ArchidektSkippedLine] = []
    ) {
        self.name = name
        self.cards = cards
        self.skippedLines = skippedLines
    }
}

public enum ArchidektListParser {
    public static func parse(_ text: String) -> ArchidektDeckImport {
        var cards: [ArchidektCardReference] = []
        var skippedLines: [ArchidektSkippedLine] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            guard let card = parseLine(trimmedLine) else {
                skippedLines.append(
                    ArchidektSkippedLine(
                        lineNumber: lineNumber,
                        text: trimmedLine,
                        reason: "Line did not match Archidekt export format."
                    ))
                continue
            }

            cards.append(card)
        }

        return ArchidektDeckImport(cards: cards, skippedLines: skippedLines)
    }

    public static func deckID(from source: String) -> Int? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return nil
        }

        let pattern = #"(?:archidekt\.com/(?:api/)?decks/)(\d+)"#
        guard let match = firstMatch(pattern: pattern, in: trimmed),
              let idRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }

        return Int(trimmed[idRange])
    }

    static func normalizedCategories(from rawValue: String?) -> [String] {
        guard let rawValue else {
            return []
        }

        return rawValue
            .split(separator: ",")
            .map { rawCategory in
                let withoutPosition = replacingMatches(
                    in: String(rawCategory),
                    pattern: #"\{[^}]*\}"#,
                    with: ""
                )
                return withoutPosition.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func parseLine(_ rawLine: String) -> ArchidektCardReference? {
        let lineWithoutLabels = replacingMatches(in: rawLine, pattern: #"\^[^^]*\^"#, with: "")
        let lineWithoutFoilMarkers = replacingMatches(in: lineWithoutLabels, pattern: #"\s+\*[^*]+\*"#, with: "")
        let line = lineWithoutFoilMarkers.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\s*(\d+)\s*x?\s+(.+?)\s+\(([A-Za-z0-9_]+)\)\s+([^\s\[]+)\s*(?:\[([^\]]*)\])?\s*$"#
        guard let match = firstMatch(pattern: pattern, in: line),
              let quantityRange = Range(match.range(at: 1), in: line),
              let nameRange = Range(match.range(at: 2), in: line),
              let setRange = Range(match.range(at: 3), in: line),
              let collectorRange = Range(match.range(at: 4), in: line),
              let quantity = Int(line[quantityRange])
        else {
            return nil
        }

        let categories: [String]
        if match.range(at: 5).location != NSNotFound,
           let categoryRange = Range(match.range(at: 5), in: line)
        {
            categories = normalizedCategories(from: String(line[categoryRange]))
        } else {
            categories = []
        }

        let name = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let setCode = String(line[setRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let collectorNumber = String(line[collectorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard quantity > 0, !name.isEmpty, !setCode.isEmpty, !collectorNumber.isEmpty else {
            return nil
        }

        return ArchidektCardReference(
            quantity: quantity,
            name: name,
            setCode: setCode,
            collectorNumber: collectorNumber,
            categories: categories,
            sourceDescription: rawLine
        )
    }

    private static func firstMatch(pattern: String, in source: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.firstMatch(in: source, range: range)
    }

    private static func replacingMatches(in source: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: replacement
        )
    }
}

public final class ArchidektDeckClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://archidekt.com")!

    private let network: NetworkClient
    private let decoder: JSONDecoder
    private let baseURL: URL

    public init(
        network: NetworkClient,
        decoder: JSONDecoder = JSONDecoder(),
        baseURL: URL = ArchidektDeckClient.defaultBaseURL
    ) {
        self.network = network
        self.decoder = decoder
        self.baseURL = baseURL
    }

    public func fetchDeck(from source: String) async throws -> ArchidektDeckImport {
        guard let deckID = ArchidektListParser.deckID(from: source) else {
            throw ArchidektDeckClientError.missingDeckID
        }
        return try await fetchDeck(id: deckID)
    }

    public func fetchDeck(id deckID: Int) async throws -> ArchidektDeckImport {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("decks")
            .appendingPathComponent(String(deckID))
            .appendingPathComponent("")
        let data = try await network.data(from: url, purpose: .deckImport)
        let response = try decoder.decode(ArchidektDeckResponse.self, from: data)
        return response.deckImport
    }
}

public enum ArchidektDeckClientError: Error, Equatable, Sendable {
    case missingDeckID
}

private struct ArchidektDeckResponse: Decodable {
    var name: String
    var cards: [ArchidektDeckCard]

    var deckImport: ArchidektDeckImport {
        ArchidektDeckImport(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name,
            cards: cards.compactMap(\.cardReference)
        )
    }
}

private struct ArchidektDeckCard: Decodable {
    var quantity: Int
    var categories: [String]?
    var card: ArchidektCard?

    var cardReference: ArchidektCardReference? {
        guard let card else {
            return nil
        }
        let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let setCode = card.edition?.editioncode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let collectorNumber = card.collectorNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scryfallID = card.uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourceDescription: String
        if let setCode, !setCode.isEmpty, !collectorNumber.isEmpty {
            sourceDescription = "\(quantity)x \(name) (\(setCode)) \(collectorNumber)"
        } else {
            sourceDescription = "\(quantity)x \(name)"
        }

        guard quantity > 0, !name.isEmpty else {
            return nil
        }

        return ArchidektCardReference(
            quantity: quantity,
            name: name,
            setCode: setCode?.isEmpty == false ? setCode : nil,
            collectorNumber: collectorNumber.isEmpty ? nil : collectorNumber,
            categories: ArchidektListParser.normalizedCategories(from: (categories ?? []).joined(separator: ",")),
            scryfallID: scryfallID.isEmpty ? nil : scryfallID,
            sourceDescription: sourceDescription
        )
    }
}

private struct ArchidektCard: Decodable {
    var uid: String?
    var displayName: String?
    var collectorNumber: String?
    var edition: ArchidektEdition?
    var oracleCard: ArchidektOracleCard?

    var name: String {
        oracleCard?.name ?? displayName ?? ""
    }
}

private struct ArchidektEdition: Decodable {
    var editioncode: String
}

private struct ArchidektOracleCard: Decodable {
    var name: String
}
