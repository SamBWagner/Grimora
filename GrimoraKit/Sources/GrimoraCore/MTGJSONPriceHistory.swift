import Foundation
import CZlib

public struct MTGJSONPriceHistoryMeta: Codable, Equatable, Sendable {
  public var date: String
  public var version: String

  public init(date: String, version: String) {
    self.date = date
    self.version = version
  }
}

public struct MTGJSONPriceImportSummary: Equatable, Sendable {
  public var mappedCards: Int
  public var importedPricePoints: Int

  public init(mappedCards: Int, importedPricePoints: Int) {
    self.mappedCards = mappedCards
    self.importedPricePoints = importedPricePoints
  }
}

public final class MTGJSONPriceHistoryClient: Sendable {
  public static let metaURL = URL(string: "https://mtgjson.com/api/v5/Meta.json")!
  public static let allIdentifiersURL = URL(string: "https://mtgjson.com/api/v5/AllIdentifiers.json.gz")!
  public static let allPrintingsURL = allIdentifiersURL
  public static let allPricesTodayURL = URL(string: "https://mtgjson.com/api/v5/AllPricesToday.json.gz")!
  public static let allPricesURL = URL(string: "https://mtgjson.com/api/v5/AllPrices.json.gz")!

  private let network: NetworkClient
  private let decoder: JSONDecoder

  public init(network: NetworkClient, decoder: JSONDecoder = JSONDecoder()) {
    self.network = network
    self.decoder = decoder
  }

  public func fetchMeta() async throws -> MTGJSONPriceHistoryMeta {
    let data = try await network.data(from: Self.metaURL, purpose: .priceHistoryDownload)
    return try decoder.decode(MTGJSONMetaEnvelope.self, from: data).meta
  }

  public func downloadAllPrintings(
    to destination: URL,
    progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
  ) async throws {
    try await network.download(
      from: Self.allPrintingsURL,
      to: destination,
      purpose: .priceHistoryDownload,
      progress: progress
    )
  }

  public func downloadAllPrices(
    to destination: URL,
    progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
  ) async throws {
    try await network.download(
      from: Self.allPricesURL,
      to: destination,
      purpose: .priceHistoryDownload,
      progress: progress
    )
  }

  public func downloadAllPricesToday(
    to destination: URL,
    progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
  ) async throws {
    try await network.download(
      from: Self.allPricesTodayURL,
      to: destination,
      purpose: .priceHistoryDownload,
      progress: progress
    )
  }
}

public final class MTGJSONPriceHistoryImporter: Sendable {
  private let database: CardDatabase
  private let decoder: JSONDecoder

  public init(database: CardDatabase, decoder: JSONDecoder = JSONDecoder()) {
    self.database = database
    self.decoder = decoder
  }

  public func importHistory(
    meta: MTGJSONPriceHistoryMeta,
    allPrintingsGzipURL: URL,
    allPricesGzipURL: URL,
    temporaryDirectory: URL,
    progress: (@Sendable (ImportProgress) async -> Void)? = nil
  ) async throws -> MTGJSONPriceImportSummary {
    let printingsJSONURL = temporaryDirectory
      .appendingPathComponent("mtgjson-all-printings-\(meta.date.fileSafeComponent).json")
    let pricesJSONURL = temporaryDirectory
      .appendingPathComponent("mtgjson-all-prices-\(meta.date.fileSafeComponent).json")
    try MTGJSONGzip.decompressFile(at: allPrintingsGzipURL, to: printingsJSONURL)
    try MTGJSONGzip.decompressFile(at: allPricesGzipURL, to: pricesJSONURL)
    defer {
      try? FileManager.default.removeItem(at: printingsJSONURL)
      try? FileManager.default.removeItem(at: pricesJSONURL)
    }

    return try await importHistory(
      meta: meta,
      allPrintingsJSONURL: printingsJSONURL,
      allPricesJSONURL: pricesJSONURL,
      progress: progress
    )
  }

  public func importCurrentPrices(
    meta: MTGJSONPriceHistoryMeta,
    allPrintingsGzipURL: URL,
    allPricesTodayGzipURL: URL,
    temporaryDirectory: URL,
    progress: (@Sendable (ImportProgress) async -> Void)? = nil
  ) async throws -> MTGJSONPriceImportSummary {
    let printingsJSONURL = temporaryDirectory
      .appendingPathComponent("mtgjson-all-printings-\(meta.date.fileSafeComponent).json")
    let pricesJSONURL = temporaryDirectory
      .appendingPathComponent("mtgjson-all-prices-today-\(meta.date.fileSafeComponent).json")
    try MTGJSONGzip.decompressFile(at: allPrintingsGzipURL, to: printingsJSONURL)
    try MTGJSONGzip.decompressFile(at: allPricesTodayGzipURL, to: pricesJSONURL)
    defer {
      try? FileManager.default.removeItem(at: printingsJSONURL)
      try? FileManager.default.removeItem(at: pricesJSONURL)
    }

    return try await importCurrentPrices(
      meta: meta,
      allPrintingsJSONURL: printingsJSONURL,
      allPricesTodayJSONURL: pricesJSONURL,
      progress: progress
    )
  }

  public func importHistory(
    meta: MTGJSONPriceHistoryMeta,
    allPrintingsJSONURL: URL,
    allPricesJSONURL: URL,
    progress: (@Sendable (ImportProgress) async -> Void)? = nil
  ) async throws -> MTGJSONPriceImportSummary {
    let localCardIDs = try database.localCardIDSet()
    guard !localCardIDs.isEmpty else {
      return MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
    }

    await progress?(.buildingPriceIDMap)
    let printingsSize = Self.fileSize(at: allPrintingsJSONURL)
    await progress?(.buildingPriceIDMapProgress(scannedBytes: 0, totalBytes: printingsSize, mappedCards: 0))
    let mappingsByUUID = try await MTGJSONAllPrintingsScanner.mappingsByMTGJSONUUID(
      in: allPrintingsJSONURL,
      localCardIDs: localCardIDs,
      decoder: decoder
    ) { scannedBytes, mappedCards in
      await progress?(
        .buildingPriceIDMapProgress(
          scannedBytes: scannedBytes,
          totalBytes: printingsSize,
          mappedCards: mappedCards
        )
      )
    }
    await progress?(
      .buildingPriceIDMapProgress(
        scannedBytes: printingsSize ?? 0,
        totalBytes: printingsSize,
        mappedCards: mappingsByUUID.count
      )
    )

    await progress?(.importingPriceHistory)
    let pricesSize = Self.fileSize(at: allPricesJSONURL)
    await progress?(
      .importingPriceHistoryProgress(scannedBytes: 0, totalBytes: pricesSize, importedPricePoints: 0)
    )
    let minimumDate = Self.minimumHistoryDate(for: meta.date, days: 90)
    let summary = try database.replaceCardValueHistory(meta: meta, mappingsByMTGJSONUUID: mappingsByUUID) {
      writer in
      var importedPricePoints = 0
      let wantedUUIDs = Set(mappingsByUUID.keys)
      try MTGJSONAllPricesScanner.forEachPriceObject(in: allPricesJSONURL, wantedUUIDs: wantedUUIDs) {
        uuid,
        objectData in
        guard let cardID = mappingsByUUID[uuid] else {
          return
        }
        let prices = try decoder.decode(MTGJSONPriceFormats.self, from: objectData)
        for finish in CardValueFinish.allCases {
          let points = prices.tcgplayerRetailPrices(for: finish)
          for (date, price) in points where price >= 0 && Self.includesHistoryDate(date, minimumDate: minimumDate) {
            try writer.insert(
              cardID: cardID,
              provider: .tcgplayer,
              finish: finish,
              date: date,
              price: price
            )
            importedPricePoints += 1
          }
        }
      }
      return importedPricePoints
    }
    await progress?(
      .importingPriceHistoryProgress(
        scannedBytes: pricesSize ?? 0,
        totalBytes: pricesSize,
        importedPricePoints: summary.importedPricePoints
      )
    )
    return summary
  }

  public func importCompactHistory(
    meta: MTGJSONPriceHistoryMeta,
    allPrintingsGzipURL: URL,
    allPricesGzipURL: URL,
    temporaryDirectory: URL,
    progress: (@Sendable (ImportProgress) async -> Void)? = nil
  ) async throws -> MTGJSONPriceImportSummary {
    let printingsJSONURL = temporaryDirectory
      .appendingPathComponent("mtgjson-all-printings-\(meta.date.fileSafeComponent).json")
    let pricesJSONURL = temporaryDirectory
      .appendingPathComponent("mtgjson-all-prices-\(meta.date.fileSafeComponent).json")
    try GzipArchive.decompressFile(at: allPrintingsGzipURL, to: printingsJSONURL)
    try GzipArchive.decompressFile(at: allPricesGzipURL, to: pricesJSONURL)
    defer {
      try? FileManager.default.removeItem(at: printingsJSONURL)
      try? FileManager.default.removeItem(at: pricesJSONURL)
    }

    await progress?(.buildingPriceIDMap)
    await progress?(.importingPriceHistory)

    let dates = try Self.compactHistoryDates(endingAt: meta.date, days: 90)
    let summary = try database.replaceCompactCardValueHistory(
      meta: meta,
      importMappings: { insertMapping in
        try MTGJSONAllPrintingsScanner.forEachMapping(
          in: printingsJSONURL,
          decoder: decoder,
          body: insertMapping
        )
      },
      importSeries: { cardIDForUUID, insertSeries in
        try MTGJSONAllPricesScanner.forEachPriceObject(in: pricesJSONURL) { uuid, objectData in
          guard let cardID = try cardIDForUUID(uuid) else {
            return
          }
          #if canImport(Darwin)
          let prices = try autoreleasepool {
            try decoder.decode(MTGJSONPriceFormats.self, from: objectData)
          }
          #else
          let prices = try decoder.decode(MTGJSONPriceFormats.self, from: objectData)
          #endif
          for finish in CardValueFinish.allCases {
            let values = prices.tcgplayerRetailPrices(for: finish)
            let encoded = dates.map { date -> Int32 in
              guard let price = values[date], price >= 0 else {
                return CompactCardValueSeries.missingPrice
              }
              let cents = (price * 100).rounded()
              guard cents <= Double(Int32.max) else {
                return CompactCardValueSeries.missingPrice
              }
              return Int32(cents)
            }
            guard encoded.contains(where: { $0 != CompactCardValueSeries.missingPrice }) else {
              continue
            }
            try insertSeries(
              CompactCardValueSeries(
                cardID: cardID,
                finish: finish,
                startDate: dates[0],
                endDate: dates[dates.count - 1],
                pricesInCents: encoded
              )
            )
          }
        }
      }
    )
    await progress?(.priceHistoryReady(pricePointCount: summary.importedPricePoints))
    return summary
  }

  public func importCurrentPrices(
    meta: MTGJSONPriceHistoryMeta,
    allPrintingsJSONURL: URL,
    allPricesTodayJSONURL: URL,
    progress: (@Sendable (ImportProgress) async -> Void)? = nil
  ) async throws -> MTGJSONPriceImportSummary {
    let localCardIDs = try database.localCardIDSet()
    guard !localCardIDs.isEmpty else {
      return MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
    }

    await progress?(.buildingPriceIDMap)
    let printingsSize = Self.fileSize(at: allPrintingsJSONURL)
    await progress?(.buildingPriceIDMapProgress(scannedBytes: 0, totalBytes: printingsSize, mappedCards: 0))
    let mappingsByUUID = try await MTGJSONAllPrintingsScanner.mappingsByMTGJSONUUID(
      in: allPrintingsJSONURL,
      localCardIDs: localCardIDs,
      decoder: decoder
    ) { scannedBytes, mappedCards in
      await progress?(
        .buildingPriceIDMapProgress(
          scannedBytes: scannedBytes,
          totalBytes: printingsSize,
          mappedCards: mappedCards
        )
      )
    }
    await progress?(
      .buildingPriceIDMapProgress(
        scannedBytes: printingsSize ?? 0,
        totalBytes: printingsSize,
        mappedCards: mappingsByUUID.count
      )
    )

    await progress?(.importingPriceHistory)
    let pricesSize = Self.fileSize(at: allPricesTodayJSONURL)
    await progress?(
      .importingPriceHistoryProgress(scannedBytes: 0, totalBytes: pricesSize, importedPricePoints: 0)
    )
    var pricePoints: [CardValueImportPoint] = []
    try await MTGJSONAllPricesScanner.forEachPriceObjectReportingProgress(
      in: allPricesTodayJSONURL,
      wantedUUIDs: Set(mappingsByUUID.keys)
    ) { scannedBytes in
      await progress?(
        .importingPriceHistoryProgress(
          scannedBytes: scannedBytes,
          totalBytes: pricesSize,
          importedPricePoints: pricePoints.count
        )
      )
    } body: { uuid, objectData in
      guard let cardID = mappingsByUUID[uuid] else {
        return
      }
      let prices = try decoder.decode(MTGJSONPriceFormats.self, from: objectData)
      for finish in CardValueFinish.allCases {
        guard let current = Self.currentPricePoint(in: prices.tcgplayerRetailPrices(for: finish)) else {
          continue
        }
        pricePoints.append(
          CardValueImportPoint(
            cardID: cardID,
            provider: .tcgplayer,
            finish: finish,
            date: current.date,
            price: current.price
          )
        )
      }
    }
    let summary = try database.upsertCurrentCardValues(
      meta: meta,
      mappingsByMTGJSONUUID: mappingsByUUID,
      pricePoints: pricePoints
    )
    await progress?(
      .importingPriceHistoryProgress(
        scannedBytes: pricesSize ?? 0,
        totalBytes: pricesSize,
        importedPricePoints: summary.importedPricePoints
      )
    )
    return summary
  }

  public func importHistoryToStaging(
    meta: MTGJSONPriceHistoryMeta,
    mappingsByMTGJSONUUID: [String: CardRecord.ID],
    allPricesJSONURL: URL,
    jobID: String,
    progress: (@Sendable (ImportProgress) async -> Void)? = nil
  ) async throws -> MTGJSONPriceImportSummary {
    guard !mappingsByMTGJSONUUID.isEmpty else {
      try database.prepareValueHistoryStaging(jobID: jobID)
      return MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
    }

    try database.prepareValueHistoryStaging(
      jobID: jobID,
      mappingsByMTGJSONUUID: mappingsByMTGJSONUUID
    )

    await progress?(.importingPriceHistory)
    let pricesSize = Self.fileSize(at: allPricesJSONURL)
    await progress?(
      .importingPriceHistoryProgress(scannedBytes: 0, totalBytes: pricesSize, importedPricePoints: 0)
    )
    let minimumDate = Self.minimumHistoryDate(for: meta.date, days: 90)
    var pendingPoints: [CardValueImportPoint] = []
    var importedPricePoints = 0
    try await MTGJSONAllPricesScanner.forEachPriceObjectReportingProgress(
      in: allPricesJSONURL,
      wantedUUIDs: Set(mappingsByMTGJSONUUID.keys)
    ) { scannedBytes in
      if !pendingPoints.isEmpty {
        let batch = pendingPoints
        pendingPoints.removeAll(keepingCapacity: true)
        try self.database.appendStagedCardValuePoints(jobID: jobID, points: batch)
        importedPricePoints += batch.count
      }
      await progress?(
        .importingPriceHistoryProgress(
          scannedBytes: scannedBytes,
          totalBytes: pricesSize,
          importedPricePoints: importedPricePoints
        )
      )
    } body: { uuid, objectData in
      guard let cardID = mappingsByMTGJSONUUID[uuid] else {
        return
      }
      let prices = try decoder.decode(MTGJSONPriceFormats.self, from: objectData)
      for finish in CardValueFinish.allCases {
        let points = prices.tcgplayerRetailPrices(for: finish)
        for (date, price) in points where price >= 0 && Self.includesHistoryDate(date, minimumDate: minimumDate) {
          pendingPoints.append(
            CardValueImportPoint(
              cardID: cardID,
              provider: .tcgplayer,
              finish: finish,
              date: date,
              price: price
            )
          )
        }
      }
    }
    if !pendingPoints.isEmpty {
      try database.appendStagedCardValuePoints(jobID: jobID, points: pendingPoints)
      importedPricePoints += pendingPoints.count
    }
    let summary = try database.stagedValueHistorySummary(jobID: jobID)
    await progress?(
      .importingPriceHistoryProgress(
        scannedBytes: pricesSize ?? 0,
        totalBytes: pricesSize,
        importedPricePoints: summary.importedPricePoints
      )
    )
    return summary
  }

  private static func currentPricePoint(in points: [String: Double]) -> (date: String, price: Double)? {
    points
      .filter { $0.value >= 0 }
      .max { lhs, rhs in lhs.key < rhs.key }
      .map { (date: $0.key, price: $0.value) }
  }

  private static func includesHistoryDate(_ date: String, minimumDate: String?) -> Bool {
    guard let minimumDate else {
      return true
    }
    return date >= minimumDate
  }

  private static func minimumHistoryDate(for metaDate: String, days: Int) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: metaDate),
      let cutoff = calendar.date(byAdding: .day, value: -days, to: date)
    else {
      return nil
    }
    return formatter.string(from: cutoff)
  }

  private static func fileSize(at url: URL) -> Int64? {
    guard let size = try? FileManager.default
      .attributesOfItem(atPath: url.path)[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  private static func compactHistoryDates(endingAt value: String, days: Int) throws -> [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    guard let endDate = formatter.date(from: value),
      let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)
    else {
      throw CatalogStorageError.invalidCatalog("MTGJSON metadata date is invalid: \(value)")
    }
    return (0...days).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: startDate).map(formatter.string)
    }
  }
}

private struct MTGJSONMetaEnvelope: Decodable {
  var meta: MTGJSONPriceHistoryMeta
}

private struct MTGJSONCardIdentity: Decodable {
  var uuid: String?
  var identifiers: Identifiers?

  struct Identifiers: Decodable {
    var scryfallID: String?

    enum CodingKeys: String, CodingKey {
      case scryfallID = "scryfallId"
    }
  }
}

private struct MTGJSONCardIdentifierPayload: Decodable {
  var identifiers: MTGJSONCardIdentity.Identifiers?
}

private struct MTGJSONSetCards: Decodable {
  var cards: [MTGJSONCardIdentity]?
}

private struct MTGJSONPriceFormats: Decodable {
  var paper: MTGJSONPaperPrices?

  func tcgplayerRetailPrices(for finish: CardValueFinish) -> [String: Double] {
    guard let retail = paper?.tcgplayer?.retail else {
      return [:]
    }
    switch finish {
    case .normal:
      return retail.normal ?? [:]
    case .foil:
      return retail.foil ?? [:]
    case .etched:
      return retail.etched ?? [:]
    }
  }
}

private struct MTGJSONPaperPrices: Decodable {
  var tcgplayer: MTGJSONProviderPrices?
}

private struct MTGJSONProviderPrices: Decodable {
  var retail: MTGJSONRetailPrices?
}

private struct MTGJSONRetailPrices: Decodable {
  var normal: [String: Double]?
  var foil: [String: Double]?
  var etched: [String: Double]?
}

enum MTGJSONAllPrintingsScanner {
  static func forEachMapping(
    in url: URL,
    decoder: JSONDecoder = JSONDecoder(),
    body: (String, CardRecord.ID) throws -> Void
  ) throws {
    try MTGJSONDataObjectScanner.forEachObject(in: url) { objectKey, objectData in
      if let card = try? decoder.decode(MTGJSONCardIdentifierPayload.self, from: objectData),
        let scryfallID = card.identifiers?.scryfallID
      {
        try body(objectKey, scryfallID)
        return
      }

      let set = try decoder.decode(MTGJSONSetCards.self, from: objectData)
      for card in set.cards ?? [] {
        guard let mtgjsonUUID = card.uuid,
          let scryfallID = card.identifiers?.scryfallID
        else {
          continue
        }
        try body(mtgjsonUUID, scryfallID)
      }
    }
  }

  static func mappingsByMTGJSONUUID(
    in url: URL,
    localCardIDs: Set<CardRecord.ID>,
    decoder: JSONDecoder = JSONDecoder(),
    progress: ((Int64, Int) async -> Void)? = nil
  ) async throws -> [String: CardRecord.ID] {
    var mappings: [String: CardRecord.ID] = [:]
    try await MTGJSONDataObjectScanner.forEachObjectReportingProgress(
      in: url,
      progress: { scannedBytes in
        await progress?(scannedBytes, mappings.count)
      }
    ) { objectKey, objectData in
      if let card = try? decoder.decode(MTGJSONCardIdentifierPayload.self, from: objectData),
        let scryfallID = card.identifiers?.scryfallID,
        localCardIDs.contains(scryfallID)
      {
        mappings[objectKey] = scryfallID
        return
      }

      let set = try decoder.decode(MTGJSONSetCards.self, from: objectData)
      for card in set.cards ?? [] {
        guard let mtgjsonUUID = card.uuid,
          let scryfallID = card.identifiers?.scryfallID,
          localCardIDs.contains(scryfallID)
        else {
          continue
        }
        mappings[mtgjsonUUID] = scryfallID
      }
    }
    return mappings
  }

  static func forEachCardObject(in url: URL, body: (Data) throws -> Void) async throws {
    let scanner = try JSONFileByteScanner(url: url)
    var pendingCardsKey = false
    var waitingForCardsColon = false
    var waitingForCardsArray = false
    var inCardsArray = false
    var cardsArrayDepth = 0
    var objectCollector: JSONObjectCollector?

    try await scanner.scanStringsAndBytes(progress: nil) { event in
      if var collector = objectCollector {
        if let objectData = collector.consume(event.byte) {
          objectCollector = nil
          try body(objectData)
        } else {
          objectCollector = collector
        }
        return
      }

      if let stringValue = event.stringValue, !inCardsArray, stringValue == "cards" {
        pendingCardsKey = true
        waitingForCardsColon = true
        waitingForCardsArray = false
        return
      }

      guard !event.isInsideString else {
        return
      }

      let byte = event.byte
      if pendingCardsKey {
        if byte.isJSONWhitespace {
          return
        }
        if waitingForCardsColon, byte == UInt8(ascii: ":") {
          waitingForCardsColon = false
          waitingForCardsArray = true
          return
        }
        if waitingForCardsArray, byte == UInt8(ascii: "[") {
          pendingCardsKey = false
          waitingForCardsArray = false
          inCardsArray = true
          cardsArrayDepth = 1
          return
        }
        pendingCardsKey = false
        waitingForCardsColon = false
        waitingForCardsArray = false
      }

      guard inCardsArray else {
        return
      }

      if byte == UInt8(ascii: "[") {
        cardsArrayDepth += 1
      } else if byte == UInt8(ascii: "]") {
        cardsArrayDepth -= 1
        if cardsArrayDepth <= 0 {
          inCardsArray = false
          cardsArrayDepth = 0
        }
      } else if cardsArrayDepth == 1, byte == UInt8(ascii: "{") {
        objectCollector = JSONObjectCollector(openingByte: byte)
      }
    }
  }
}

enum MTGJSONAllPricesScanner {
  static func forEachPriceObject(
    in url: URL,
    body: (String, Data) throws -> Void
  ) throws {
    try MTGJSONDataObjectScanner.forEachObject(in: url, body: body)
  }

  static func forEachPriceObject(
    in url: URL,
    wantedUUIDs: Set<String>,
    body: (String, Data) throws -> Void
  ) throws {
    try MTGJSONDataObjectScanner.forEachObject(
      in: url,
      wantedKeys: wantedUUIDs,
      body: body
    )
  }

  static func forEachPriceObjectReportingProgress(
    in url: URL,
    wantedUUIDs: Set<String>,
    progress: ((Int64) async throws -> Void)? = nil,
    body: (String, Data) throws -> Void
  ) async throws {
    try await MTGJSONDataObjectScanner.forEachObjectReportingProgress(
      in: url,
      wantedKeys: wantedUUIDs,
      progress: progress,
      body: body
    )
  }
}

enum MTGJSONDataObjectScanner {
  static func forEachObject(
    in url: URL,
    wantedKeys: Set<String>? = nil,
    body: (String, Data) throws -> Void
  ) throws {
    let scanner = try JSONFileByteScanner(url: url)
    var pendingDataKey = false
    var waitingForDataColon = false
    var waitingForDataObject = false
    var inDataObject = false
    var dataObjectDepth = 0
    var pendingObjectKey: String?
    var waitingForObjectKeyColon = false
    var objectCollector: JSONObjectCollector?
    var skipCollector: JSONSkipObjectCollector?

    try scanner.scanStringsAndBytes { event in
      if var collector = objectCollector {
        if let objectData = collector.consume(event.byte) {
          let key = pendingObjectKey
          objectCollector = nil
          pendingObjectKey = nil
          waitingForObjectKeyColon = false
          if let key {
            try body(key, objectData)
          }
        } else {
          objectCollector = collector
        }
        return
      }

      if var collector = skipCollector {
        if collector.consume(event.byte) {
          skipCollector = nil
          pendingObjectKey = nil
          waitingForObjectKeyColon = false
        } else {
          skipCollector = collector
        }
        return
      }

      if let stringValue = event.stringValue {
        if !inDataObject, stringValue == "data" {
          pendingDataKey = true
          waitingForDataColon = true
          waitingForDataObject = false
          return
        }

        if inDataObject, dataObjectDepth == 1, pendingObjectKey == nil {
          pendingObjectKey = stringValue
          waitingForObjectKeyColon = true
          return
        }
      }

      guard !event.isInsideString else {
        return
      }

      let byte = event.byte
      if pendingDataKey {
        if byte.isJSONWhitespace {
          return
        }
        if waitingForDataColon, byte == UInt8(ascii: ":") {
          waitingForDataColon = false
          waitingForDataObject = true
          return
        }
        if waitingForDataObject, byte == UInt8(ascii: "{") {
          pendingDataKey = false
          waitingForDataObject = false
          inDataObject = true
          dataObjectDepth = 1
          return
        }
        pendingDataKey = false
        waitingForDataColon = false
        waitingForDataObject = false
      }

      guard inDataObject else {
        return
      }

      if pendingObjectKey != nil, waitingForObjectKeyColon {
        if byte.isJSONWhitespace {
          return
        }
        if byte == UInt8(ascii: ":") {
          waitingForObjectKeyColon = false
          return
        }
        pendingObjectKey = nil
        waitingForObjectKeyColon = false
      } else if let key = pendingObjectKey {
        if byte.isJSONWhitespace {
          return
        }
        if byte == UInt8(ascii: "{") {
          if wantedKeys?.contains(key) ?? true {
            objectCollector = JSONObjectCollector(openingByte: byte)
          } else {
            skipCollector = JSONSkipObjectCollector(openingByte: byte)
          }
          return
        }
        pendingObjectKey = nil
      }

      if byte == UInt8(ascii: "{") {
        dataObjectDepth += 1
      } else if byte == UInt8(ascii: "}") {
        dataObjectDepth -= 1
        if dataObjectDepth <= 0 {
          inDataObject = false
          dataObjectDepth = 0
        }
      }
    }
  }

  static func forEachObjectReportingProgress(
    in url: URL,
    wantedKeys: Set<String>? = nil,
    progress: ((Int64) async throws -> Void)? = nil,
    body: (String, Data) throws -> Void
  ) async throws {
    let scanner = try JSONFileByteScanner(url: url)
    var pendingDataKey = false
    var waitingForDataColon = false
    var waitingForDataObject = false
    var inDataObject = false
    var dataObjectDepth = 0
    var pendingObjectKey: String?
    var waitingForObjectKeyColon = false
    var objectCollector: JSONObjectCollector?
    var skipCollector: JSONSkipObjectCollector?

    try await scanner.scanStringsAndBytes(progress: progress) { event in
      if var collector = objectCollector {
        if let objectData = collector.consume(event.byte) {
          let key = pendingObjectKey
          objectCollector = nil
          pendingObjectKey = nil
          waitingForObjectKeyColon = false
          if let key {
            try body(key, objectData)
          }
        } else {
          objectCollector = collector
        }
        return
      }

      if var collector = skipCollector {
        if collector.consume(event.byte) {
          skipCollector = nil
          pendingObjectKey = nil
          waitingForObjectKeyColon = false
        } else {
          skipCollector = collector
        }
        return
      }

      if let stringValue = event.stringValue {
        if !inDataObject, stringValue == "data" {
          pendingDataKey = true
          waitingForDataColon = true
          waitingForDataObject = false
          return
        }

        if inDataObject, dataObjectDepth == 1, pendingObjectKey == nil {
          pendingObjectKey = stringValue
          waitingForObjectKeyColon = true
          return
        }
      }

      guard !event.isInsideString else {
        return
      }

      let byte = event.byte
      if pendingDataKey {
        if byte.isJSONWhitespace {
          return
        }
        if waitingForDataColon, byte == UInt8(ascii: ":") {
          waitingForDataColon = false
          waitingForDataObject = true
          return
        }
        if waitingForDataObject, byte == UInt8(ascii: "{") {
          pendingDataKey = false
          waitingForDataObject = false
          inDataObject = true
          dataObjectDepth = 1
          return
        }
        pendingDataKey = false
        waitingForDataColon = false
        waitingForDataObject = false
      }

      guard inDataObject else {
        return
      }

      if pendingObjectKey != nil, waitingForObjectKeyColon {
        if byte.isJSONWhitespace {
          return
        }
        if byte == UInt8(ascii: ":") {
          waitingForObjectKeyColon = false
          return
        }
        pendingObjectKey = nil
        waitingForObjectKeyColon = false
      } else if let key = pendingObjectKey {
        if byte.isJSONWhitespace {
          return
        }
        if byte == UInt8(ascii: "{") {
          if wantedKeys?.contains(key) ?? true {
            objectCollector = JSONObjectCollector(openingByte: byte)
          } else {
            skipCollector = JSONSkipObjectCollector(openingByte: byte)
          }
          return
        }
        pendingObjectKey = nil
      }

      if byte == UInt8(ascii: "{") {
        dataObjectDepth += 1
      } else if byte == UInt8(ascii: "}") {
        dataObjectDepth -= 1
        if dataObjectDepth <= 0 {
          inDataObject = false
          dataObjectDepth = 0
        }
      }
    }
  }
}

private struct JSONScanEvent {
  var byte: UInt8
  var isInsideString: Bool
  var stringValue: String?
}

private final class JSONFileByteScanner {
  private let handle: FileHandle

  init(url: URL) throws {
    self.handle = try FileHandle(forReadingFrom: url)
  }

  deinit {
    try? handle.close()
  }

  func scanStringsAndBytes(_ body: (JSONScanEvent) throws -> Void) throws {
    var isInsideString = false
    var isEscapingString = false
    var tokenBytes: [UInt8] = []
    let chunkSize = 256 * 1024

    while true {
      let chunk = try handle.read(upToCount: chunkSize) ?? Data()
      if chunk.isEmpty {
        break
      }

      for byte in chunk {
        if isInsideString {
          if isEscapingString {
            isEscapingString = false
            if tokenBytes.count < 128 {
              tokenBytes.append(byte)
            }
            try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
            continue
          }

          if byte == UInt8(ascii: "\\") {
            isEscapingString = true
            try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
            continue
          }

          if byte == UInt8(ascii: "\"") {
            isInsideString = false
            let value = String(data: Data(tokenBytes), encoding: .utf8)
            tokenBytes.removeAll(keepingCapacity: true)
            try body(JSONScanEvent(byte: byte, isInsideString: false, stringValue: value))
            continue
          }

          if tokenBytes.count < 128 {
            tokenBytes.append(byte)
          }
          try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
          continue
        }

        if byte == UInt8(ascii: "\"") {
          isInsideString = true
          isEscapingString = false
          tokenBytes.removeAll(keepingCapacity: true)
          try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
        } else {
          try body(JSONScanEvent(byte: byte, isInsideString: false, stringValue: nil))
        }
      }
    }
  }

  func scanStringsAndBytes(
    progress: ((Int64) async throws -> Void)?,
    _ body: (JSONScanEvent) throws -> Void
  ) async throws {
    var isInsideString = false
    var isEscapingString = false
    var tokenBytes: [UInt8] = []
    let chunkSize = 256 * 1024
    let progressIntervalBytes: Int64 = 4 * 1024 * 1024
    var scannedBytes: Int64 = 0
    var lastProgressBytes: Int64 = 0

    while true {
      let chunk = try handle.read(upToCount: chunkSize) ?? Data()
      if chunk.isEmpty {
        break
      }
      scannedBytes += Int64(chunk.count)

      for byte in chunk {
        if isInsideString {
          if isEscapingString {
            isEscapingString = false
            if tokenBytes.count < 128 {
              tokenBytes.append(byte)
            }
            try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
            continue
          }

          if byte == UInt8(ascii: "\\") {
            isEscapingString = true
            try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
            continue
          }

          if byte == UInt8(ascii: "\"") {
            isInsideString = false
            let value = String(data: Data(tokenBytes), encoding: .utf8)
            tokenBytes.removeAll(keepingCapacity: true)
            try body(JSONScanEvent(byte: byte, isInsideString: false, stringValue: value))
            continue
          }

          if tokenBytes.count < 128 {
            tokenBytes.append(byte)
          }
          try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
          continue
        }

        if byte == UInt8(ascii: "\"") {
          isInsideString = true
          isEscapingString = false
          tokenBytes.removeAll(keepingCapacity: true)
          try body(JSONScanEvent(byte: byte, isInsideString: true, stringValue: nil))
        } else {
          try body(JSONScanEvent(byte: byte, isInsideString: false, stringValue: nil))
        }
      }

      if scannedBytes - lastProgressBytes >= progressIntervalBytes {
        lastProgressBytes = scannedBytes
        try await progress?(scannedBytes)
      }
    }

    if scannedBytes != lastProgressBytes {
      try await progress?(scannedBytes)
    }
  }
}

private struct JSONObjectCollector {
  private var data = Data()
  private var depth = 0
  private var isInsideString = false
  private var isEscapingString = false

  init(openingByte: UInt8) {
    data.append(openingByte)
    depth = 1
  }

  mutating func consume(_ byte: UInt8) -> Data? {
    data.append(byte)

    if isInsideString {
      if isEscapingString {
        isEscapingString = false
      } else if byte == UInt8(ascii: "\\") {
        isEscapingString = true
      } else if byte == UInt8(ascii: "\"") {
        isInsideString = false
      }
      return nil
    }

    if byte == UInt8(ascii: "\"") {
      isInsideString = true
    } else if byte == UInt8(ascii: "{") {
      depth += 1
    } else if byte == UInt8(ascii: "}") {
      depth -= 1
      if depth == 0 {
        return data
      }
    }
    return nil
  }
}

private struct JSONSkipObjectCollector {
  private var depth = 0
  private var isInsideString = false
  private var isEscapingString = false

  init(openingByte: UInt8) {
    depth = openingByte == UInt8(ascii: "{") ? 1 : 0
  }

  mutating func consume(_ byte: UInt8) -> Bool {
    if isInsideString {
      if isEscapingString {
        isEscapingString = false
      } else if byte == UInt8(ascii: "\\") {
        isEscapingString = true
      } else if byte == UInt8(ascii: "\"") {
        isInsideString = false
      }
      return false
    }

    if byte == UInt8(ascii: "\"") {
      isInsideString = true
    } else if byte == UInt8(ascii: "{") {
      depth += 1
    } else if byte == UInt8(ascii: "}") {
      depth -= 1
    }
    return depth == 0
  }
}

public enum GzipArchive {
  public static func compressFile(at source: URL, to destination: URL) throws {
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    _ = FileManager.default.createFile(atPath: destination.path, contents: nil)

    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    defer {
      try? input.close()
      try? output.close()
    }

    var stream = z_stream()
    let initStatus = deflateInit2_(
      &stream,
      Z_BEST_COMPRESSION,
      Z_DEFLATED,
      MAX_WBITS + 16,
      MAX_MEM_LEVEL,
      Z_DEFAULT_STRATEGY,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else {
      throw MTGJSONPriceHistoryError.gzipDeflateFailed(initStatus)
    }
    defer { deflateEnd(&stream) }

    let inputChunkSize = 256 * 1024
    let outputChunkSize = 256 * 1024
    var finished = false
    while !finished {
      let inputData = try input.read(upToCount: inputChunkSize) ?? Data()
      let flush = inputData.isEmpty ? Z_FINISH : Z_NO_FLUSH
      try inputData.withUnsafeBytes { inputBuffer in
        stream.next_in = UnsafeMutablePointer(
          mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
        )
        stream.avail_in = uInt(inputData.count)

        repeat {
          var outputBytes = [UInt8](repeating: 0, count: outputChunkSize)
          let status = outputBytes.withUnsafeMutableBytes { outputBuffer -> Int32 in
            stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(outputChunkSize)
            let status = deflate(&stream, flush)
            let produced = outputChunkSize - Int(stream.avail_out)
            if produced > 0, let outputBase = outputBuffer.baseAddress {
              output.write(Data(bytes: outputBase, count: produced))
            }
            return status
          }
          if status == Z_STREAM_END {
            finished = true
            break
          }
          guard status == Z_OK else {
            throw MTGJSONPriceHistoryError.gzipDeflateFailed(status)
          }
        } while stream.avail_in > 0 || stream.avail_out == 0
      }
    }
  }

  public static func decompressFile(at source: URL, to destination: URL) throws {
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    _ = FileManager.default.createFile(atPath: destination.path, contents: nil)

    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    defer {
      try? input.close()
      try? output.close()
    }

    var stream = z_stream()
    let initStatus = inflateInit2_(
      &stream,
      MAX_WBITS + 16,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else {
      throw MTGJSONPriceHistoryError.gzipInflateFailed(initStatus)
    }
    defer { inflateEnd(&stream) }

    let inputChunkSize = 64 * 1024
    let outputChunkSize = 256 * 1024
    var didFinish = false

    while !didFinish {
      let inputData = try input.read(upToCount: inputChunkSize) ?? Data()
      if inputData.isEmpty {
        break
      }

      try inputData.withUnsafeBytes { inputBuffer in
        guard let inputBase = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
          return
        }
        stream.next_in = UnsafeMutablePointer(mutating: inputBase)
        stream.avail_in = uInt(inputData.count)

        repeat {
          var outputBytes = [UInt8](repeating: 0, count: outputChunkSize)
          let status = outputBytes.withUnsafeMutableBytes { outputBuffer -> Int32 in
            stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(outputChunkSize)
            let status = inflate(&stream, Z_NO_FLUSH)
            let produced = outputChunkSize - Int(stream.avail_out)
            if produced > 0, let outputBase = outputBuffer.baseAddress {
              output.write(Data(bytes: outputBase, count: produced))
            }
            return status
          }

          if status == Z_STREAM_END {
            didFinish = true
            break
          }
          guard status == Z_OK else {
            throw MTGJSONPriceHistoryError.gzipInflateFailed(status)
          }
        } while stream.avail_out == 0
      }
    }

    guard didFinish else {
      throw MTGJSONPriceHistoryError.gzipStreamEndedEarly
    }
  }
}

enum MTGJSONGzip {
  static func decompressFile(at source: URL, to destination: URL) throws {
    try GzipArchive.decompressFile(at: source, to: destination)
  }
}

public enum MTGJSONPriceHistoryError: Error, Equatable, Sendable {
  case gzipDeflateFailed(Int32)
  case gzipInflateFailed(Int32)
  case gzipStreamEndedEarly
  case missingCurrentPriceMappings
}

private extension UInt8 {
  var isJSONWhitespace: Bool {
    self == UInt8(ascii: " ")
      || self == UInt8(ascii: "\n")
      || self == UInt8(ascii: "\r")
      || self == UInt8(ascii: "\t")
  }
}

private extension String {
  var fileSafeComponent: String {
    map { character in
      character.isLetter || character.isNumber ? character : "-"
    }
    .reduce(into: "") { $0.append($1) }
  }
}
