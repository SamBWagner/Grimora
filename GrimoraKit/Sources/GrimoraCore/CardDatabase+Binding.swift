import Foundation

extension CardDatabase {
  func bind(_ card: CardRecord, to statement: SQLiteStatement) throws {
    var index: Int32 = 1

    func bind(_ value: String?) throws {
      try statement.bind(value, at: index)
      index += 1
    }

    func bind(_ value: Int?) throws {
      try statement.bind(value, at: index)
      index += 1
    }

    func bind(_ value: Double?) throws {
      try statement.bind(value, at: index)
      index += 1
    }

    func bind(_ value: Bool) throws {
      try statement.bind(value, at: index)
      index += 1
    }

    try bind(card.id)
    try bind(card.oracleID)
    try bind(card.name)
    try bind(card.name.sortKey)
    try bind(card.displayNameKey.isEmpty ? card.name.sortKey : card.displayNameKey)
    try bind(card.language)
    try bind(card.releasedAt)
    try bind(card.setCode.lowercased())
    try bind(card.setName)
    try bind(card.setType.lowercased())
    try bind(card.collectorNumber)
    try bind(card.collectorNumberNumber)
    try bind(card.rarity.lowercased())
    try bind(card.rarityRank)
    try bind(card.artist)
    try bind(card.artist?.sortKey)
    try bind(card.artistCount)
    try bind(card.illustrationCount)
    try bind(card.edhrecRank)
    try bind(card.pennyRank)
    try bind(card.mtgoID)
    try bind(card.manaCost)
    try bind(card.manaValue)
    try bind(card.power)
    try bind(card.powerValue)
    try bind(card.toughness)
    try bind(card.toughnessValue)
    try bind(card.loyalty)
    try bind(card.loyaltyValue)
    try bind(card.priceUSD)
    try bind(card.priceTIX)
    try bind(card.priceEUR)
    try bind(card.colorSortKey)
    try bind(Self.serializedList(card.colors))
    try bind(Self.serializedList(card.colorIdentity))
    try bind(Self.serializedList(card.producedMana))
    try bind(Self.serializedList(card.colorIndicator))
    try bind(card.colors.count)
    try bind(card.colorIdentity.count)
    try bind(card.producedMana.count)
    try bind(card.layout)
    try bind(card.layout.normalizedSearchKey)
    try bind(card.typeLine)
    try bind(Self.joinedTypeText(card).normalizedSearchKey)
    try bind(card.oracleText)
    try bind(Self.joinedOracleText(card).normalizedSearchKey)
    try bind(Self.serializedList(card.keywords))
    try bind(card.flavorText)
    try bind(card.flavorText?.normalizedSearchKey ?? "")
    try bind(card.watermark?.lowercased())
    try bind(Self.serializedLegalities(card.legalities))
    try bind(Self.serializedList(card.games))
    try bind(Self.serializedList(card.finishes))
    try bind(Self.serializedList(card.promoTypes))
    try bind(Self.serializedList(card.frameEffects))
    try bind(Self.serializedList(card.artistIDs))
    try bind(card.illustrationID)
    try bind(card.borderColor?.lowercased())
    try bind(card.frame?.lowercased())
    try bind(card.securityStamp?.lowercased())
    try bind(card.isDigital)
    try bind(card.isOversized)
    try bind(card.isUniversesBeyond)
    try bind(card.isAlchemy)
    try bind(card.isRealCard)
    try bind(card.isPromo)
    try bind(card.isVariation)
    try bind(card.isBoosterFun)
    try bind(card.isBasePrinting)
    try bind(card.isReserved)
    try bind(card.isGameChanger)
    try bind(card.isReprint)
    try bind(card.isBooster)
    try bind(card.isStorySpotlight)
    try bind(card.isFullArt)
    try bind(card.isTextless)
    try bind(card.isFoil)
    try bind(card.isNonfoil)
    try bind(card.isHighResolution)
    try bind(card.printCount)
    try bind(card.setCount)
    try bind(card.paperPrintCount)
    try bind(card.paperSetCount)
    try bind(card.isNewArt)
    try bind(card.isNewArtist)
    try bind(card.isNewFlavor)
    try bind(card.isNewRarity)
    try bind(card.isNewFrame)
    try bind(card.isNewLanguage)
    try bind(card.smallImagePath)
    try bind(card.normalImagePath)
    try bind(card.largeImagePath)
    try bind(card.artCropImagePath)
    try bind(card.smallImageURL)
    try bind(card.normalImageURL)
    try bind(card.largeImageURL)
    try bind(card.artCropImageURL)
  }

  func fetchFaces(for cardID: String) throws -> [CardFaceRecord] {
    let statement = try database.prepare(
      """
      SELECT card_id, face_index, name, type_line, oracle_text,
          small_image_path, normal_image_path, large_image_path,
          art_crop_image_path, small_image_url, normal_image_url, large_image_url,
          art_crop_image_url
      FROM card_faces
      WHERE card_id = ?
      ORDER BY face_index ASC
      """)
    try statement.bind(cardID, at: 1)

    var faces: [CardFaceRecord] = []
    while try statement.step() {
      faces.append(
        CardFaceRecord(
          cardID: statement.string(at: 0) ?? cardID,
          faceIndex: statement.int(at: 1) ?? 0,
          name: statement.string(at: 2) ?? "",
          typeLine: statement.string(at: 3) ?? "",
          oracleText: statement.string(at: 4) ?? "",
          smallImagePath: statement.string(at: 5),
          normalImagePath: statement.string(at: 6),
          largeImagePath: statement.string(at: 7),
          artCropImagePath: statement.string(at: 8),
          smallImageURL: statement.string(at: 9),
          normalImageURL: statement.string(at: 10),
          largeImageURL: statement.string(at: 11),
          artCropImageURL: statement.string(at: 12)
        ))
    }
    return faces
  }

  func hydrateFaces(for cards: inout [CardRecord]) throws {
    guard !cards.isEmpty else {
      return
    }

    let facesByCardID = try fetchFaces(forCardIDs: cards.map(\.id))
    for index in cards.indices {
      cards[index].faces = facesByCardID[cards[index].id] ?? []
    }
  }

  func fetchFaces(forCardIDs cardIDs: [String]) throws -> [String: [CardFaceRecord]] {
    let uniqueCardIDs = Array(Set(cardIDs))
    guard !uniqueCardIDs.isEmpty else {
      return [:]
    }

    let placeholders = Array(repeating: "?", count: uniqueCardIDs.count).joined(separator: ", ")
    let statement = try database.prepare(
      """
      SELECT card_id, face_index, name, type_line, oracle_text,
          small_image_path, normal_image_path, large_image_path,
          art_crop_image_path, small_image_url, normal_image_url, large_image_url,
          art_crop_image_url
      FROM card_faces
      WHERE card_id IN (\(placeholders))
      ORDER BY card_id ASC, face_index ASC
      """)

    for (index, cardID) in uniqueCardIDs.enumerated() {
      try statement.bind(cardID, at: Int32(index + 1))
    }

    var facesByCardID: [String: [CardFaceRecord]] = [:]
    while try statement.step() {
      let cardID = statement.string(at: 0) ?? ""
      facesByCardID[cardID, default: []].append(
        CardFaceRecord(
          cardID: cardID,
          faceIndex: statement.int(at: 1) ?? 0,
          name: statement.string(at: 2) ?? "",
          typeLine: statement.string(at: 3) ?? "",
          oracleText: statement.string(at: 4) ?? "",
          smallImagePath: statement.string(at: 5),
          normalImagePath: statement.string(at: 6),
          largeImagePath: statement.string(at: 7),
          artCropImagePath: statement.string(at: 8),
          smallImageURL: statement.string(at: 9),
          normalImageURL: statement.string(at: 10),
          largeImageURL: statement.string(at: 11),
          artCropImageURL: statement.string(at: 12)
        ))
    }

    return facesByCardID
  }

  /// Batch sibling of `card(id:)`. Hydrates many cards in a handful of queries instead of one
  /// statement (plus a faces query) per id: a chunked `WHERE id IN (...)` fetch followed by a
  /// single batched faces hydration per chunk. Callers must already hold `withDatabaseLock`.
  func cardsByID(forIDs ids: [String]) throws -> [String: CardRecord] {
    let uniqueIDs = Array(Set(ids))
    guard !uniqueIDs.isEmpty else {
      return [:]
    }

    var result: [String: CardRecord] = [:]
    result.reserveCapacity(uniqueIDs.count)

    // Stay safely under SQLite's default SQLITE_MAX_VARIABLE_NUMBER (~999) so very large lists
    // bind their IN-clause across multiple statements. The faces helper is bounded by the same
    // chunk, so it never exceeds the variable limit either.
    let chunkSize = 900
    for start in stride(from: 0, to: uniqueIDs.count, by: chunkSize) {
      let chunk = Array(uniqueIDs[start..<min(start + chunkSize, uniqueIDs.count)])
      let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
      let statement = try database.prepare(
        """
        SELECT \(Self.cardColumns)
        FROM cards
        WHERE id IN (\(placeholders))
        """)
      for (index, id) in chunk.enumerated() {
        try statement.bind(id, at: Int32(index + 1))
      }

      var cards: [CardRecord] = []
      while try statement.step() {
        cards.append(readCard(from: statement))
      }
      try hydrateFaces(for: &cards)
      for card in cards {
        result[card.id] = card
      }
    }

    return result
  }

  func readCard(from statement: SQLiteStatement) -> CardRecord {
    var index: Int32 = 0

    func string() -> String? {
      defer { index += 1 }
      return statement.string(at: index)
    }

    func int() -> Int? {
      defer { index += 1 }
      return statement.int(at: index)
    }

    func double() -> Double? {
      defer { index += 1 }
      return statement.double(at: index)
    }

    func bool() -> Bool {
      defer { index += 1 }
      return statement.bool(at: index)
    }

    let id = string() ?? ""
    let oracleID = string()
    let name = string() ?? ""
    let displayNameKey = string() ?? name.sortKey
    let language = string()
    let releasedAt = string()
    let setCode = string() ?? ""
    let setName = string() ?? ""
    let setType = string() ?? ""
    let collectorNumber = string() ?? ""
    let collectorNumberNumber = int()
    let rarity = string() ?? ""
    let rarityRank = int()
    let artist = string()
    let artistCount = int() ?? 0
    let illustrationCount = int() ?? 0
    let edhrecRank = int()
    let pennyRank = int()
    let mtgoID = int()
    let manaCost = string() ?? ""
    let manaValue = double()
    let power = string()
    let powerValue = double()
    let toughness = string()
    let toughnessValue = double()
    let loyalty = string()
    let loyaltyValue = double()
    let priceUSD = double()
    let priceTIX = double()
    let priceEUR = double()
    let colorSortKey = int() ?? 6
    let colors = Self.deserializedList(string())
    let colorIdentity = Self.deserializedList(string())
    let producedMana = Self.deserializedList(string())
    let colorIndicator = Self.deserializedList(string())
    _ = int()
    _ = int()
    _ = int()
    let layout = string() ?? ""
    _ = string()
    let typeLine = string() ?? ""
    _ = string()
    let oracleText = string() ?? ""
    _ = string()
    let keywords = Self.deserializedList(string())
    let flavorText = string()
    _ = string()
    let watermark = string()
    let legalities = Self.deserializedLegalities(string())
    let games = Self.deserializedList(string())
    let finishes = Self.deserializedList(string())
    let promoTypes = Self.deserializedList(string())
    let frameEffects = Self.deserializedList(string())
    let artistIDs = Self.deserializedList(string())
    let illustrationID = string()
    let borderColor = string()
    let frame = string()
    let securityStamp = string()

    return CardRecord(
      id: id,
      oracleID: oracleID,
      name: name,
      displayNameKey: displayNameKey.isEmpty ? name.sortKey : displayNameKey,
      language: language,
      releasedAt: releasedAt,
      setCode: setCode,
      setName: setName,
      setType: setType,
      collectorNumber: collectorNumber,
      collectorNumberNumber: collectorNumberNumber,
      rarity: rarity,
      rarityRank: rarityRank,
      artist: artist,
      edhrecRank: edhrecRank,
      pennyRank: pennyRank,
      mtgoID: mtgoID,
      manaCost: manaCost,
      manaValue: manaValue,
      power: power,
      powerValue: powerValue,
      toughness: toughness,
      toughnessValue: toughnessValue,
      loyalty: loyalty,
      loyaltyValue: loyaltyValue,
      priceUSD: priceUSD,
      priceTIX: priceTIX,
      priceEUR: priceEUR,
      colorSortKey: colorSortKey,
      colors: colors,
      colorIdentity: colorIdentity,
      producedMana: producedMana,
      colorIndicator: colorIndicator,
      layout: layout,
      typeLine: typeLine,
      oracleText: oracleText,
      keywords: keywords,
      flavorText: flavorText,
      watermark: watermark,
      legalities: legalities,
      games: games,
      finishes: finishes,
      promoTypes: promoTypes,
      frameEffects: frameEffects,
      artistIDs: artistIDs,
      illustrationID: illustrationID,
      borderColor: borderColor,
      frame: frame,
      securityStamp: securityStamp,
      isDigital: bool(),
      isOversized: bool(),
      isUniversesBeyond: bool(),
      isAlchemy: bool(),
      isRealCard: bool(),
      isPromo: bool(),
      isVariation: bool(),
      isBoosterFun: bool(),
      isBasePrinting: bool(),
      isReserved: bool(),
      isGameChanger: bool(),
      isReprint: bool(),
      isBooster: bool(),
      isStorySpotlight: bool(),
      isFullArt: bool(),
      isTextless: bool(),
      isFoil: bool(),
      isNonfoil: bool(),
      isHighResolution: bool(),
      printCount: int() ?? 1,
      setCount: int() ?? 1,
      paperPrintCount: int() ?? 0,
      paperSetCount: int() ?? 0,
      artistCount: artistCount,
      illustrationCount: illustrationCount,
      isNewArt: bool(),
      isNewArtist: bool(),
      isNewFlavor: bool(),
      isNewRarity: bool(),
      isNewFrame: bool(),
      isNewLanguage: bool(),
      smallImagePath: string(),
      normalImagePath: string(),
      largeImagePath: string(),
      artCropImagePath: string(),
      smallImageURL: string(),
      normalImageURL: string(),
      largeImageURL: string(),
      artCropImageURL: string(),
      faces: []
    )
  }
}
