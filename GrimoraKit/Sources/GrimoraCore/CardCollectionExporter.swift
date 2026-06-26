import Foundation

public enum CardCollectionExportFormat: String, CaseIterable, Identifiable, Sendable {
    case text
    case csv
    case arena
    case mtgoDek
    case deckRegistrationPDF
    case edhrecArticle
    case grimoraArchive

    public var id: Self { self }

    public var displayTitle: String {
        switch self {
        case .text:
            "Text"
        case .csv:
            "CSV"
        case .arena:
            "Arena"
        case .mtgoDek:
            "MTGO.dek"
        case .deckRegistrationPDF:
            "Deck Registration PDF"
        case .edhrecArticle:
            "EDHREC Article"
        case .grimoraArchive:
            "Grimora Archive"
        }
    }

    public var fileExtension: String {
        switch self {
        case .text, .arena, .edhrecArticle:
            "txt"
        case .csv:
            "csv"
        case .mtgoDek:
            "dek"
        case .deckRegistrationPDF:
            "pdf"
        case .grimoraArchive:
            "grimoralist"
        }
    }

    public var supportsCopy: Bool {
        switch self {
        case .deckRegistrationPDF, .grimoraArchive:
            false
        case .text, .csv, .arena, .mtgoDek, .edhrecArticle:
            true
        }
    }

    public var supportsDownload: Bool {
        switch self {
        case .text, .csv, .mtgoDek, .deckRegistrationPDF, .grimoraArchive:
            true
        case .arena, .edhrecArticle:
            false
        }
    }
}

public enum CardCollectionExportTextSectionHeader: String, CaseIterable, Identifiable, Sendable {
    case none
    case generic
    case cardType

    public var id: Self { self }

    public var displayTitle: String {
        switch self {
        case .none:
            "No section header"
        case .generic:
            "Generic"
        case .cardType:
            "Card type"
        }
    }
}

public enum CardCollectionExportCSVColumn: String, CaseIterable, Identifiable, Sendable {
    case quantity
    case category
    case name
    case setName
    case setCode
    case collectorNumber
    case price
    case rarity
    case color
    case manaValue
    case types
    case cardText
    case scryfallID

    public var id: Self { self }

    public var displayTitle: String {
        switch self {
        case .quantity:
            "Quantity"
        case .category:
            "Category"
        case .name:
            "Name"
        case .setName:
            "Set name"
        case .setCode:
            "Set code"
        case .collectorNumber:
            "Collector number"
        case .price:
            "Price"
        case .rarity:
            "Rarity"
        case .color:
            "Color"
        case .manaValue:
            "Mana value"
        case .types:
            "Types"
        case .cardText:
            "Card text"
        case .scryfallID:
            "Scryfall ID"
        }
    }
}

public enum CardCollectionDeckRegistrationSortMode: String, CaseIterable, Identifiable, Sendable {
    case alphabetical
    case manaValue
    case color
    case type

    public var id: Self { self }

    public var displayTitle: String {
        switch self {
        case .alphabetical:
            "Alphabetical"
        case .manaValue:
            "Mana value"
        case .color:
            "Color"
        case .type:
            "Type"
        }
    }
}

public struct CardCollectionDeckRegistrationFields: Equatable, Sendable {
    public var deckName: String
    public var date: String
    public var firstName: String
    public var lastName: String
    public var designer: String
    public var dciNumber: String
    public var location: String
    public var eventName: String

    public init(
        deckName: String = "",
        date: String = "",
        firstName: String = "",
        lastName: String = "",
        designer: String = "",
        dciNumber: String = "",
        location: String = "",
        eventName: String = ""
    ) {
        self.deckName = deckName
        self.date = date
        self.firstName = firstName
        self.lastName = lastName
        self.designer = designer
        self.dciNumber = dciNumber
        self.location = location
        self.eventName = eventName
    }
}

public struct CardCollectionExportConfiguration: Equatable, Sendable {
    public var format: CardCollectionExportFormat
    public var textIncludesXInQuantity: Bool
    public var textIncludesSetCode: Bool
    public var textIncludesCollectorNumber: Bool
    public var textUsesFrontNameOnlyForMDFC: Bool
    public var textSectionHeader: CardCollectionExportTextSectionHeader
    public var csvColumns: [CardCollectionExportCSVColumn]
    public var csvIncludesHeaderRow: Bool
    public var deckRegistrationFields: CardCollectionDeckRegistrationFields
    public var deckRegistrationSortMode: CardCollectionDeckRegistrationSortMode

    public init(
        format: CardCollectionExportFormat = .text,
        textIncludesXInQuantity: Bool = true,
        textIncludesSetCode: Bool = true,
        textIncludesCollectorNumber: Bool = true,
        textUsesFrontNameOnlyForMDFC: Bool = false,
        textSectionHeader: CardCollectionExportTextSectionHeader = .none,
        csvColumns: [CardCollectionExportCSVColumn] = CardCollectionExportCSVColumn.allCases,
        csvIncludesHeaderRow: Bool = true,
        deckRegistrationFields: CardCollectionDeckRegistrationFields = CardCollectionDeckRegistrationFields(),
        deckRegistrationSortMode: CardCollectionDeckRegistrationSortMode = .alphabetical
    ) {
        self.format = format
        self.textIncludesXInQuantity = textIncludesXInQuantity
        self.textIncludesSetCode = textIncludesSetCode
        self.textIncludesCollectorNumber = textIncludesCollectorNumber
        self.textUsesFrontNameOnlyForMDFC = textUsesFrontNameOnlyForMDFC
        self.textSectionHeader = textSectionHeader
        self.csvColumns = csvColumns
        self.csvIncludesHeaderRow = csvIncludesHeaderRow
        self.deckRegistrationFields = deckRegistrationFields
        self.deckRegistrationSortMode = deckRegistrationSortMode
    }

    public static func defaultConfiguration(format: CardCollectionExportFormat = .text) -> Self {
        Self(format: format)
    }
}

public struct CardCollectionExportResult: Equatable, Sendable {
    public var format: CardCollectionExportFormat
    public var content: String?
    public var data: Data?
    public var preview: String
    public var filename: String
    public var selectedCardCount: Int
    public var uniqueCardCount: Int
    public var warnings: [String]

    public var isCopyable: Bool {
        format.supportsCopy && content != nil
    }

    public var isDownloadable: Bool {
        format.supportsDownload && fileData != nil
    }

    public var fileData: Data? {
        data ?? content?.data(using: .utf8)
    }

    public init(
        format: CardCollectionExportFormat,
        content: String? = nil,
        data: Data? = nil,
        preview: String,
        filename: String,
        selectedCardCount: Int,
        uniqueCardCount: Int,
        warnings: [String] = []
    ) {
        self.format = format
        self.content = content
        self.data = data
        self.preview = preview
        self.filename = filename
        self.selectedCardCount = selectedCardCount
        self.uniqueCardCount = uniqueCardCount
        self.warnings = warnings
    }
}

public enum CardCollectionExporter {
    public static func export(
        list: CardCollectionRecord,
        entries: [CardCollectionEntryRecord],
        categories: [CardCollectionCategoryRecord] = [],
        configuration: CardCollectionExportConfiguration,
        date: Date = Date()
    ) -> CardCollectionExportResult {
        let categoryAggregation = aggregate(entries, categories: categories)
        let flatAggregation = aggregate(entries)
        var warnings = categoryAggregation.warnings
        let filename = fileName(for: list, format: configuration.format)
        let selectedCardCount = categoryAggregation.cards.reduce(0) { $0 + $1.quantity }
        let uniqueCardCount = categoryAggregation.cards.count
        let usesCategories = !categories.isEmpty
        if configuration.format != .grimoraArchive && hasDescription(list) {
            warnings.append("List descriptions are only preserved by Grimora Archive export.")
        }

        switch configuration.format {
        case .text:
            let output = usesCategories
                ? categoryTextOutput(
                    for: categoryAggregation.sections,
                    configuration: configuration
                )
                : textOutput(for: categoryAggregation.cards, configuration: configuration)
            return CardCollectionExportResult(
                format: configuration.format,
                content: output,
                preview: output,
                filename: filename,
                selectedCardCount: selectedCardCount,
                uniqueCardCount: uniqueCardCount,
                warnings: warnings
            )
        case .csv:
            let output = csvOutput(for: categoryAggregation.cards, configuration: configuration)
            return CardCollectionExportResult(
                format: configuration.format,
                content: output,
                preview: output,
                filename: filename,
                selectedCardCount: selectedCardCount,
                uniqueCardCount: uniqueCardCount,
                warnings: warnings
            )
        case .arena:
            let arena = arenaOutput(for: flatAggregation.cards)
            warnings.append(contentsOf: arena.warnings)
            if usesCategories {
                warnings.append("Categories were omitted because Arena export is a flat deck format.")
            }
            return CardCollectionExportResult(
                format: configuration.format,
                content: arena.output,
                preview: arena.output,
                filename: filename,
                selectedCardCount: flatAggregation.cards.reduce(0) { $0 + $1.quantity },
                uniqueCardCount: flatAggregation.cards.count,
                warnings: warnings
            )
        case .mtgoDek:
            let mtgo = mtgoDeckOutput(for: flatAggregation.cards)
            warnings.append(contentsOf: mtgo.warnings)
            if usesCategories {
                warnings.append("Categories were omitted because MTGO.dek export is a flat deck format.")
            }
            return CardCollectionExportResult(
                format: configuration.format,
                content: mtgo.output,
                preview: mtgo.output,
                filename: filename,
                selectedCardCount: flatAggregation.cards.reduce(0) { $0 + $1.quantity },
                uniqueCardCount: flatAggregation.cards.count,
                warnings: warnings
            )
        case .deckRegistrationPDF:
            let lines = deckRegistrationLines(
                for: list,
                cards: categoryAggregation.cards,
                sections: usesCategories ? categoryAggregation.sections : [],
                configuration: configuration,
                date: date
            )
            let preview = lines.joined(separator: "\n")
            return CardCollectionExportResult(
                format: configuration.format,
                data: SimplePDFBuilder.make(lines: lines),
                preview: preview,
                filename: filename,
                selectedCardCount: selectedCardCount,
                uniqueCardCount: uniqueCardCount,
                warnings: warnings
            )
        case .edhrecArticle:
            let output = edhrecArticleOutput(
                for: list,
                cards: categoryAggregation.cards,
                sections: usesCategories ? categoryAggregation.sections : []
            )
            return CardCollectionExportResult(
                format: configuration.format,
                content: output,
                preview: output,
                filename: filename,
                selectedCardCount: selectedCardCount,
                uniqueCardCount: uniqueCardCount,
                warnings: warnings
            )
        case .grimoraArchive:
            let document = CardCollectionArchiveCoder.document(
                list: list,
                entries: entries,
                categories: categories
            )
            let archiveSelectedCardCount = entries.reduce(0) { $0 + $1.quantity }
            let archiveUniqueCardCount = Set(entries.map(\.cardID)).count
            let preview = grimoraArchivePreview(
                list: list,
                entries: entries,
                categories: categories,
                uniqueCardCount: archiveUniqueCardCount
            )
            do {
                return CardCollectionExportResult(
                    format: configuration.format,
                    data: try CardCollectionArchiveCoder.encode(document),
                    preview: preview,
                    filename: filename,
                    selectedCardCount: archiveSelectedCardCount,
                    uniqueCardCount: archiveUniqueCardCount
                )
            } catch {
                return CardCollectionExportResult(
                    format: configuration.format,
                    preview: preview,
                    filename: filename,
                    selectedCardCount: archiveSelectedCardCount,
                    uniqueCardCount: archiveUniqueCardCount,
                    warnings: ["Could not create Grimora archive."]
                )
            }
        }
    }

    private struct AggregatedCard {
        var card: CardRecord
        var quantity: Int
        var firstIndex: Int
        var categoryName: String?
    }

    private struct AggregatedCategorySection {
        var title: String
        var cards: [AggregatedCard]
    }

    private static func aggregate(_ entries: [CardCollectionEntryRecord]) -> (
        cards: [AggregatedCard], warnings: [String]
    ) {
        var cards: [AggregatedCard] = []
        var indexByCardID: [String: Int] = [:]
        var warnings: [String] = []

        for (index, entry) in entries.enumerated() {
            guard let card = entry.card else {
                warnings.append("Skipped \(entry.cardID) because that print is not available locally.")
                continue
            }

            if let existingIndex = indexByCardID[card.id] {
                cards[existingIndex].quantity += entry.quantity
            } else {
                indexByCardID[card.id] = cards.count
                cards.append(AggregatedCard(card: card, quantity: entry.quantity, firstIndex: index, categoryName: nil))
            }
        }

        return (cards, warnings)
    }

    private static func aggregate(
        _ entries: [CardCollectionEntryRecord],
        categories: [CardCollectionCategoryRecord]
    ) -> (cards: [AggregatedCard], sections: [AggregatedCategorySection], warnings: [String]) {
        let knownCategories = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var cardsBySection: [String: [AggregatedCard]] = [:]
        var indexBySectionAndCardID: [String: [String: Int]] = [:]
        var warnings: [String] = []

        for (index, entry) in entries.enumerated() {
            guard let card = entry.card else {
                warnings.append("Skipped \(entry.cardID) because that print is not available locally.")
                continue
            }

            let category = entry.categoryID.flatMap { knownCategories[$0] }
            let sectionKey = category?.id ?? ""
            let sectionTitle = category?.name ?? (categories.isEmpty ? nil : "Uncategorized")
            var cards = cardsBySection[sectionKey] ?? []
            var indexByCardID = indexBySectionAndCardID[sectionKey] ?? [:]

            if let existingIndex = indexByCardID[card.id] {
                cards[existingIndex].quantity += entry.quantity
            } else {
                indexByCardID[card.id] = cards.count
                cards.append(
                    AggregatedCard(
                        card: card,
                        quantity: entry.quantity,
                        firstIndex: index,
                        categoryName: sectionTitle
                    )
                )
            }

            cardsBySection[sectionKey] = cards
            indexBySectionAndCardID[sectionKey] = indexByCardID
        }

        var sections: [AggregatedCategorySection] = []
        if let cards = cardsBySection[""], !cards.isEmpty {
            sections.append(AggregatedCategorySection(title: "Uncategorized", cards: cards))
        }
        for category in categories {
            guard let cards = cardsBySection[category.id], !cards.isEmpty else {
                continue
            }
            sections.append(AggregatedCategorySection(title: category.name, cards: cards))
        }

        if categories.isEmpty {
            let cards = cardsBySection[""] ?? []
            return (cards, [], warnings)
        }

        return (sections.flatMap(\.cards), sections, warnings)
    }

    private static func textOutput(
        for cards: [AggregatedCard],
        configuration: CardCollectionExportConfiguration
    ) -> String {
        switch configuration.textSectionHeader {
        case .none:
            return cards.map { textLine(for: $0, configuration: configuration) }.joined(separator: "\n")
        case .generic:
            let lines = cards.map { textLine(for: $0, configuration: configuration) }
            return (["Mainboard"] + lines).joined(separator: "\n")
        case .cardType:
            var lines: [String] = []
            for section in CardTypeSection.allCases {
                let sectionCards = cards.filter { CardTypeSection(card: $0.card) == section }
                guard !sectionCards.isEmpty else {
                    continue
                }

                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append(section.title)
                lines.append(contentsOf: sectionCards.map { textLine(for: $0, configuration: configuration) })
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func categoryTextOutput(
        for sections: [AggregatedCategorySection],
        configuration: CardCollectionExportConfiguration
    ) -> String {
        var lines: [String] = []
        for section in sections {
            if !lines.isEmpty {
                lines.append("")
            }
            lines.append(section.title)
            lines.append(contentsOf: section.cards.map { textLine(for: $0, configuration: configuration) })
        }
        return lines.joined(separator: "\n")
    }

    private static func textLine(
        for card: AggregatedCard,
        configuration: CardCollectionExportConfiguration
    ) -> String {
        let quantity = configuration.textIncludesXInQuantity ? "\(card.quantity)x" : "\(card.quantity)"
        var line = "\(quantity) \(exportName(for: card.card, frontNameOnlyForMDFC: configuration.textUsesFrontNameOnlyForMDFC))"

        if configuration.textIncludesSetCode, !card.card.setCode.isEmpty {
            line += " (\(card.card.setCode.lowercased()))"
        }

        if configuration.textIncludesCollectorNumber, !card.card.collectorNumber.isEmpty {
            line += " \(card.card.collectorNumber)"
        }

        return line
    }

    private static func csvOutput(
        for cards: [AggregatedCard],
        configuration: CardCollectionExportConfiguration
    ) -> String {
        let columns = configuration.csvColumns
        guard !columns.isEmpty else {
            return ""
        }

        var rows: [[String]] = []

        if configuration.csvIncludesHeaderRow {
            rows.append(columns.map { $0.displayTitle })
        }

        rows.append(contentsOf: cards.map { card in
            columns.map { csvValue(for: $0, card: card) }
        })

        return rows.map { row in
            row.map(csvEscaped).joined(separator: ",")
        }
        .joined(separator: "\n")
    }

    private static func csvValue(
        for column: CardCollectionExportCSVColumn,
        card: AggregatedCard
    ) -> String {
        switch column {
        case .quantity:
            return "\(card.quantity)"
        case .category:
            return card.categoryName ?? ""
        case .name:
            return exportName(for: card.card, frontNameOnlyForMDFC: false)
        case .setName:
            return card.card.setName
        case .setCode:
            return card.card.setCode
        case .collectorNumber:
            return card.card.collectorNumber
        case .price:
            return formattedPrice(for: card.card)
        case .rarity:
            return card.card.rarity
        case .color:
            let colors = card.card.colors.isEmpty ? card.card.colorIdentity : card.card.colors
            return colors.joined()
        case .manaValue:
            return card.card.manaValue.map(decimalString) ?? ""
        case .types:
            return card.card.typeLine
        case .cardText:
            return card.card.oracleText
        case .scryfallID:
            return card.card.id
        }
    }

    private static func arenaOutput(for cards: [AggregatedCard]) -> (
        output: String, warnings: [String]
    ) {
        var lines = ["Deck"]
        var warnings: [String] = []

        for card in cards {
            let games = Set(card.card.games.map { $0.lowercased() })
            guard games.contains("arena") else {
                warnings.append("Skipped \(card.card.name) because it is not marked as available on Arena.")
                continue
            }

            let name = exportName(for: card.card, frontNameOnlyForMDFC: true)
            lines.append("\(card.quantity) \(name)\(setCollectorSuffix(for: card.card, setCodeUppercased: true))")
        }

        if lines.count == 1, !cards.isEmpty {
            warnings.append("No cards marked as available on Arena were exported.")
        }

        return (lines.joined(separator: "\n"), warnings)
    }

    private static func mtgoDeckOutput(for cards: [AggregatedCard]) -> (
        output: String, warnings: [String]
    ) {
        var lines = [
            #"<?xml version="1.0" encoding="utf-8"?>"#,
            #"<Deck xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">"#,
            "  <NetDeckID>0</NetDeckID>",
            "  <PreconstructedDeckID>0</PreconstructedDeckID>",
        ]
        var warnings: [String] = []

        for card in cards {
            let catIDAttribute: String
            if let mtgoID = card.card.mtgoID {
                catIDAttribute = #" CatID="\#(mtgoID)""#
            } else {
                catIDAttribute = ""
                warnings.append("\(card.card.name) does not have an MTGO ID yet; exported by name only.")
            }

            let name = xmlEscaped(exportName(for: card.card, frontNameOnlyForMDFC: false))
            lines.append(
                #"  <Cards\#(catIDAttribute) Quantity="\#(card.quantity)" Sideboard="false" Name="\#(name)" />"#
            )
        }

        lines.append("</Deck>")
        return (lines.joined(separator: "\n"), warnings)
    }

    private static func deckRegistrationLines(
        for list: CardCollectionRecord,
        cards: [AggregatedCard],
        sections: [AggregatedCategorySection],
        configuration: CardCollectionExportConfiguration,
        date: Date
    ) -> [String] {
        let fields = configuration.deckRegistrationFields
        let deckName = nonEmpty(fields.deckName) ?? list.name
        let registrationDate = nonEmpty(fields.date) ?? deckRegistrationDateString(for: date)
        let sortedCards = sortedDeckRegistrationCards(cards, sortMode: configuration.deckRegistrationSortMode)

        let header = [
            "Deck Registration",
            "Deck name: \(deckName)",
            "Date: \(registrationDate)",
            "First name: \(fields.firstName)",
            "Last name: \(fields.lastName)",
            "Designer: \(fields.designer)",
            "DCI #: \(fields.dciNumber)",
            "Location: \(fields.location)",
            "Event name: \(fields.eventName)",
            "",
            "Cards",
        ]

        guard !sections.isEmpty else {
            return header + sortedCards.map(deckRegistrationLine)
        }

        var lines = header
        for section in sections {
            let sortedSectionCards = sortedDeckRegistrationCards(
                section.cards,
                sortMode: configuration.deckRegistrationSortMode
            )
            guard !sortedSectionCards.isEmpty else {
                continue
            }
            lines.append(section.title)
            lines.append(contentsOf: sortedSectionCards.map(deckRegistrationLine))
        }
        return lines
    }

    private static func edhrecArticleOutput(
        for list: CardCollectionRecord,
        cards: [AggregatedCard],
        sections: [AggregatedCategorySection]
    ) -> String {
        let title = list.name.isEmpty ? "Card List" : list.name
        let lines: [String]
        if sections.isEmpty {
            lines = cards.map(edhrecArticleLine)
        } else {
            var groupedLines: [String] = []
            for section in sections {
                if !groupedLines.isEmpty {
                    groupedLines.append("")
                }
                groupedLines.append("## \(section.title)")
                groupedLines.append(contentsOf: section.cards.map(edhrecArticleLine))
            }
            lines = groupedLines
        }
        return (["# \(title)", ""] + lines).joined(separator: "\n")
    }

    private static func deckRegistrationLine(for card: AggregatedCard) -> String {
        "\(card.quantity) \(exportName(for: card.card, frontNameOnlyForMDFC: true))\(setCollectorSuffix(for: card.card, setCodeUppercased: true))"
    }

    private static func edhrecArticleLine(for card: AggregatedCard) -> String {
        "\(card.quantity) \(exportName(for: card.card, frontNameOnlyForMDFC: true))"
    }

    private static func grimoraArchivePreview(
        list: CardCollectionRecord,
        entries: [CardCollectionEntryRecord],
        categories: [CardCollectionCategoryRecord],
        uniqueCardCount: Int
    ) -> String {
        [
            "Grimora List Archive",
            "List: \(list.name.isEmpty ? "Card List" : list.name)",
            "Cards: \(entries.reduce(0) { $0 + $1.quantity })",
            "Unique cards: \(uniqueCardCount)",
            "Categories: \(categories.count)",
            "Description: \(hasDescription(list) ? "Included" : "Empty")",
        ].joined(separator: "\n")
    }

    private static func sortedDeckRegistrationCards(
        _ cards: [AggregatedCard],
        sortMode: CardCollectionDeckRegistrationSortMode
    ) -> [AggregatedCard] {
        cards.sorted { lhs, rhs in
            switch sortMode {
            case .alphabetical:
                return sortByName(lhs, rhs)
            case .manaValue:
                let lhsMana = lhs.card.manaValue ?? .greatestFiniteMagnitude
                let rhsMana = rhs.card.manaValue ?? .greatestFiniteMagnitude
                if lhsMana != rhsMana {
                    return lhsMana < rhsMana
                }
                return sortByName(lhs, rhs)
            case .color:
                if lhs.card.colorSortKey != rhs.card.colorSortKey {
                    return lhs.card.colorSortKey < rhs.card.colorSortKey
                }
                return sortByName(lhs, rhs)
            case .type:
                let lhsSection = CardTypeSection(card: lhs.card)
                let rhsSection = CardTypeSection(card: rhs.card)
                if lhsSection != rhsSection {
                    return lhsSection.rawValue < rhsSection.rawValue
                }
                return sortByName(lhs, rhs)
            }
        }
    }

    private static func sortByName(_ lhs: AggregatedCard, _ rhs: AggregatedCard) -> Bool {
        let lhsName = exportSortKey(exportName(for: lhs.card, frontNameOnlyForMDFC: true))
        let rhsName = exportSortKey(exportName(for: rhs.card, frontNameOnlyForMDFC: true))
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.firstIndex < rhs.firstIndex
    }

    private static func exportSortKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func exportName(
        for card: CardRecord,
        frontNameOnlyForMDFC: Bool
    ) -> String {
        guard
            frontNameOnlyForMDFC,
            card.layout.lowercased() == "modal_dfc",
            let firstFaceName = card.faces.first?.name,
            !firstFaceName.isEmpty
        else {
            return card.name
        }

        return firstFaceName
    }

    private static func setCollectorSuffix(
        for card: CardRecord,
        setCodeUppercased: Bool
    ) -> String {
        var suffix = ""
        if !card.setCode.isEmpty {
            let setCode = setCodeUppercased ? card.setCode.uppercased() : card.setCode.lowercased()
            suffix += " (\(setCode))"
        }
        if !card.collectorNumber.isEmpty {
            suffix += " \(card.collectorNumber)"
        }
        return suffix
    }

    private static func formattedPrice(for card: CardRecord) -> String {
        if let price = card.priceUSD {
            return decimalString(price)
        }
        if let price = card.priceEUR {
            return decimalString(price)
        }
        if let price = card.priceTIX {
            return decimalString(price)
        }
        return ""
    }

    private static func decimalString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func fileName(for list: CardCollectionRecord, format: CardCollectionExportFormat) -> String {
        let title = nonEmpty(list.name) ?? "Card List"
        return "\(sanitizedFileName(title)).\(format.fileExtension)"
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: #"/\?%*|"<>"#)
            .union(.newlines)
            .union(.controlCharacters)
        let components = value.components(separatedBy: disallowed).filter { !$0.isEmpty }
        let name = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Card List" : name
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hasDescription(_ list: CardCollectionRecord) -> Bool {
        list.descriptionRTFDData != nil || nonEmpty(list.descriptionPlainText) != nil
    }

    private static func deckRegistrationDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private enum CardTypeSection: Int, CaseIterable {
        case creatures
        case planeswalkers
        case battles
        case artifacts
        case enchantments
        case instants
        case sorceries
        case lands
        case other

        init(card: CardRecord) {
            let typeLine = card.typeLine.lowercased()
            if typeLine.contains("creature") {
                self = .creatures
            } else if typeLine.contains("planeswalker") {
                self = .planeswalkers
            } else if typeLine.contains("battle") {
                self = .battles
            } else if typeLine.contains("artifact") {
                self = .artifacts
            } else if typeLine.contains("enchantment") {
                self = .enchantments
            } else if typeLine.contains("instant") {
                self = .instants
            } else if typeLine.contains("sorcery") {
                self = .sorceries
            } else if typeLine.contains("land") {
                self = .lands
            } else {
                self = .other
            }
        }

        var title: String {
            switch self {
            case .creatures:
                "Creatures"
            case .planeswalkers:
                "Planeswalkers"
            case .battles:
                "Battles"
            case .artifacts:
                "Artifacts"
            case .enchantments:
                "Enchantments"
            case .instants:
                "Instants"
            case .sorceries:
                "Sorceries"
            case .lands:
                "Lands"
            case .other:
                "Other"
            }
        }
    }
}

private enum SimplePDFBuilder {
    static func make(lines: [String]) -> Data {
        let pages = pages(from: lines)
        let pageObjectIDs = pages.indices.map { 4 + ($0 * 2) }
        let contentObjectIDs = pages.indices.map { 5 + ($0 * 2) }

        var objects: [String] = [
            "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
            "2 0 obj\n<< /Type /Pages /Kids [\(pageObjectIDs.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pages.count) >>\nendobj\n",
            "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n",
        ]

        for (index, pageLines) in pages.enumerated() {
            let pageObjectID = pageObjectIDs[index]
            let contentObjectID = contentObjectIDs[index]
            let stream = contentStream(lines: pageLines)
            let streamLength = stream.data(using: .utf8)?.count ?? 0

            objects.append(
                "\(pageObjectID) 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents \(contentObjectID) 0 R >>\nendobj\n"
            )
            objects.append(
                "\(contentObjectID) 0 obj\n<< /Length \(streamLength) >>\nstream\n\(stream)\nendstream\nendobj\n"
            )
        }

        var output = Data()
        append("%PDF-1.4\n", to: &output)
        var offsets: [Int] = [0]

        for object in objects {
            offsets.append(output.count)
            append(object, to: &output)
        }

        let xrefOffset = output.count
        append("xref\n0 \(objects.count + 1)\n", to: &output)
        append("0000000000 65535 f \n", to: &output)
        for offset in offsets.dropFirst() {
            append(String(format: "%010d 00000 n \n", offset), to: &output)
        }
        append(
            "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n",
            to: &output
        )

        return output
    }

    private static func pages(from lines: [String]) -> [[String]] {
        let wrappedLines = (lines.isEmpty ? [""] : lines).flatMap { wrap($0) }
        let linesPerPage = 48
        var pages: [[String]] = []
        var index = 0

        while index < wrappedLines.count {
            let endIndex = min(index + linesPerPage, wrappedLines.count)
            pages.append(Array(wrappedLines[index..<endIndex]))
            index = endIndex
        }

        return pages.isEmpty ? [[""]] : pages
    }

    private static func wrap(_ line: String, maxLength: Int = 88) -> [String] {
        guard line.count > maxLength else {
            return [line]
        }

        var lines: [String] = []
        var currentLine = ""

        for wordSubstring in line.split(separator: " ") {
            let word = String(wordSubstring)
            if currentLine.isEmpty {
                currentLine = word
            } else if currentLine.count + word.count + 1 <= maxLength {
                currentLine += " \(word)"
            } else {
                lines.append(currentLine)
                currentLine = word
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [line] : lines
    }

    private static func contentStream(lines: [String]) -> String {
        var commands = [
            "BT",
            "/F1 11 Tf",
            "50 742 Td",
        ]

        for (index, line) in lines.enumerated() {
            if index > 0 {
                commands.append("0 -14 Td")
            }
            commands.append("(\(pdfEscaped(line))) Tj")
        }

        commands.append("ET")
        return commands.joined(separator: "\n")
    }

    private static func pdfEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func append(_ string: String, to data: inout Data) {
        data.append(string.data(using: .utf8) ?? Data())
    }
}
