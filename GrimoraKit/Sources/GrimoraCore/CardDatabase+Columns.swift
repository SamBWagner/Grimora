import Foundation

extension CardDatabase {
  static let insertCardColumns: [String] = [
    "id", "oracle_id", "name", "name_key", "display_name_key", "lang", "released_at",
    "set_code", "set_name", "set_type", "collector_number", "collector_number_number",
    "rarity", "rarity_rank", "artist", "artist_key", "artist_count", "illustration_count",
    "edhrec_rank", "penny_rank", "mtgo_id", "mana_cost", "mana_value", "power", "power_value",
    "toughness", "toughness_value", "loyalty", "loyalty_value", "price_usd", "price_tix",
    "price_eur", "color_sort_key", "colors_key", "color_identity_key", "produced_mana_key",
    "color_indicator_key", "color_count", "color_identity_count", "produced_mana_count",
    "layout", "layout_key", "type_line", "type_line_key", "oracle_text", "oracle_text_key",
    "keywords_key", "flavor_text", "flavor_text_key", "watermark", "legalities_key",
    "games_key", "finishes_key", "promo_types_key", "frame_effects_key", "artist_ids_key",
    "illustration_id", "border_color", "frame", "security_stamp", "is_digital",
    "is_oversized", "is_universes_beyond", "is_alchemy", "is_real_card", "is_promo",
    "is_variation", "is_booster_fun", "is_base_printing", "is_reserved", "is_game_changer",
    "is_reprint", "is_booster", "is_story_spotlight", "is_full_art", "is_textless",
    "is_foil", "is_nonfoil", "is_high_resolution", "print_count", "set_count",
    "paper_print_count", "paper_set_count", "is_new_art", "is_new_artist", "is_new_flavor",
    "is_new_rarity", "is_new_frame", "is_new_language", "small_image_path",
    "normal_image_path", "large_image_path", "art_crop_image_path", "small_image_url",
    "normal_image_url", "large_image_url", "art_crop_image_url",
  ]

  static let selectCardColumns: [String] = insertCardColumns.filter {
    $0 != "name_key" && $0 != "artist_key"
  }

  static let cardColumns = selectCardColumns.joined(separator: ", ")

  static let additionalCardColumnDefinitions: [(name: String, definition: String)] = [
    ("artist_count", "artist_count INTEGER NOT NULL DEFAULT 0"),
    ("illustration_count", "illustration_count INTEGER NOT NULL DEFAULT 0"),
    ("penny_rank", "penny_rank INTEGER"),
    ("mtgo_id", "mtgo_id INTEGER"),
    ("mana_cost", "mana_cost TEXT NOT NULL DEFAULT ''"),
    ("loyalty", "loyalty TEXT"),
    ("loyalty_value", "loyalty_value REAL"),
    ("colors_key", "colors_key TEXT NOT NULL DEFAULT ''"),
    ("color_identity_key", "color_identity_key TEXT NOT NULL DEFAULT ''"),
    ("produced_mana_key", "produced_mana_key TEXT NOT NULL DEFAULT ''"),
    ("color_indicator_key", "color_indicator_key TEXT NOT NULL DEFAULT ''"),
    ("color_count", "color_count INTEGER NOT NULL DEFAULT 0"),
    ("color_identity_count", "color_identity_count INTEGER NOT NULL DEFAULT 0"),
    ("produced_mana_count", "produced_mana_count INTEGER NOT NULL DEFAULT 0"),
    ("layout_key", "layout_key TEXT NOT NULL DEFAULT ''"),
    ("type_line_key", "type_line_key TEXT NOT NULL DEFAULT ''"),
    ("oracle_text_key", "oracle_text_key TEXT NOT NULL DEFAULT ''"),
    ("keywords_key", "keywords_key TEXT NOT NULL DEFAULT ''"),
    ("flavor_text", "flavor_text TEXT"),
    ("flavor_text_key", "flavor_text_key TEXT NOT NULL DEFAULT ''"),
    ("watermark", "watermark TEXT"),
    ("legalities_key", "legalities_key TEXT NOT NULL DEFAULT ''"),
    ("games_key", "games_key TEXT NOT NULL DEFAULT ''"),
    ("finishes_key", "finishes_key TEXT NOT NULL DEFAULT ''"),
    ("promo_types_key", "promo_types_key TEXT NOT NULL DEFAULT ''"),
    ("frame_effects_key", "frame_effects_key TEXT NOT NULL DEFAULT ''"),
    ("artist_ids_key", "artist_ids_key TEXT NOT NULL DEFAULT ''"),
    ("illustration_id", "illustration_id TEXT"),
    ("border_color", "border_color TEXT"),
    ("frame", "frame TEXT"),
    ("security_stamp", "security_stamp TEXT"),
    ("is_digital", "is_digital INTEGER NOT NULL DEFAULT 0"),
    ("is_oversized", "is_oversized INTEGER NOT NULL DEFAULT 0"),
    ("is_reserved", "is_reserved INTEGER NOT NULL DEFAULT 0"),
    ("is_game_changer", "is_game_changer INTEGER NOT NULL DEFAULT 0"),
    ("is_reprint", "is_reprint INTEGER NOT NULL DEFAULT 0"),
    ("is_booster", "is_booster INTEGER NOT NULL DEFAULT 0"),
    ("is_story_spotlight", "is_story_spotlight INTEGER NOT NULL DEFAULT 0"),
    ("is_full_art", "is_full_art INTEGER NOT NULL DEFAULT 0"),
    ("is_textless", "is_textless INTEGER NOT NULL DEFAULT 0"),
    ("is_foil", "is_foil INTEGER NOT NULL DEFAULT 0"),
    ("is_nonfoil", "is_nonfoil INTEGER NOT NULL DEFAULT 0"),
    ("is_high_resolution", "is_high_resolution INTEGER NOT NULL DEFAULT 0"),
    ("print_count", "print_count INTEGER NOT NULL DEFAULT 1"),
    ("set_count", "set_count INTEGER NOT NULL DEFAULT 1"),
    ("paper_print_count", "paper_print_count INTEGER NOT NULL DEFAULT 0"),
    ("paper_set_count", "paper_set_count INTEGER NOT NULL DEFAULT 0"),
    ("is_new_art", "is_new_art INTEGER NOT NULL DEFAULT 0"),
    ("is_new_artist", "is_new_artist INTEGER NOT NULL DEFAULT 0"),
    ("is_new_flavor", "is_new_flavor INTEGER NOT NULL DEFAULT 0"),
    ("is_new_rarity", "is_new_rarity INTEGER NOT NULL DEFAULT 0"),
    ("is_new_frame", "is_new_frame INTEGER NOT NULL DEFAULT 0"),
    ("is_new_language", "is_new_language INTEGER NOT NULL DEFAULT 0"),
    ("display_name_key", "display_name_key TEXT NOT NULL DEFAULT ''"),
    ("is_base_printing", "is_base_printing INTEGER NOT NULL DEFAULT 0"),
    ("art_crop_image_path", "art_crop_image_path TEXT"),
    ("art_crop_image_url", "art_crop_image_url TEXT"),
  ]

  static func preferredPrintingOrderClause(preferences: Set<SearchPreference>) -> String {
    var clauses: [String] = [
      "CASE WHEN lang = 'en' THEN 0 ELSE 1 END ASC",
      "CASE WHEN is_real_card = 1 THEN 0 ELSE 1 END ASC",
    ]

    if preferences.contains(.promo) {
      clauses.append("CASE WHEN is_promo = 1 THEN 0 ELSE 1 END ASC")
    } else if preferences.contains(.atypical) {
      clauses.append("CASE WHEN is_base_printing = 0 THEN 0 ELSE 1 END ASC")
    } else {
      clauses.append("CASE WHEN is_base_printing = 1 THEN 0 ELSE 1 END ASC")
    }

    if preferences.contains(.notUniversesBeyond) {
      clauses.append("CASE WHEN is_universes_beyond = 0 THEN 0 ELSE 1 END ASC")
    }

    if preferences.contains(.usdLow) {
      clauses.append("price_usd IS NULL ASC")
      clauses.append("price_usd ASC")
    } else if preferences.contains(.usdHigh) {
      clauses.append("price_usd IS NULL ASC")
      clauses.append("price_usd DESC")
    }

    clauses.append(
      """
      CASE
          WHEN small_image_url IS NOT NULL
              OR EXISTS (
                  SELECT 1
                  FROM card_faces
                  WHERE card_faces.card_id = cards.id
                      AND card_faces.small_image_url IS NOT NULL
              )
          THEN 0
          ELSE 1
      END ASC
      """)

    clauses.append("released_at IS NULL ASC")
    clauses.append(preferences.contains(.oldest) ? "released_at ASC" : "released_at DESC")
    clauses.append("set_code ASC")
    clauses.append("collector_number_number IS NULL ASC")
    clauses.append("collector_number_number ASC")
    clauses.append("collector_number ASC")
    clauses.append("id ASC")
    return clauses.joined(separator: ",\n    ")
  }

  static func cardsByAddingDerivedMetadata(_ cards: [CardRecord]) -> [CardRecord] {
    let groups = Dictionary(grouping: cards) { card in
      card.oracleID ?? card.name.sortKey
    }

    return cards.map { card in
      guard let group = groups[card.oracleID ?? card.name.sortKey] else {
        return card
      }

      var updated = card
      let paperPrints = group.filter { containsValue("paper", in: $0.games) }
      updated.printCount = group.count
      updated.setCount = Set(group.map { $0.setCode.lowercased() }).count
      updated.paperPrintCount = paperPrints.count
      updated.paperSetCount = Set(paperPrints.map { $0.setCode.lowercased() }).count
      updated.artistCount = Set(group.compactMap { $0.artist?.sortKey }).count
      updated.illustrationCount = Set(group.compactMap(\.illustrationID)).count

      let earlierCards = group.filter { isEarlier($0, than: card) }
      updated.isNewArt = isFirstNonEmpty(card.illustrationID, before: earlierCards.map(\.illustrationID))
      updated.isNewArtist = isFirstNonEmpty(card.artist?.sortKey, before: earlierCards.map { $0.artist?.sortKey })
      updated.isNewFlavor = isFirstNonEmpty(card.flavorText?.sortKey, before: earlierCards.map { $0.flavorText?.sortKey })
      updated.isNewRarity = isFirstNonEmpty(card.rarity.sortKey, before: earlierCards.map { $0.rarity.sortKey })
      updated.isNewFrame = isFirstNonEmpty(card.frame?.sortKey, before: earlierCards.map { $0.frame?.sortKey })
      updated.isNewLanguage = isFirstNonEmpty(card.language?.sortKey, before: earlierCards.map { $0.language?.sortKey })
      return updated
    }
  }

  static func isEarlier(_ lhs: CardRecord, than rhs: CardRecord) -> Bool {
    switch (lhs.releasedAt, rhs.releasedAt) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
      return lhsDate < rhsDate
    case (nil, _?):
      return true
    case (_?, nil):
      return false
    default:
      break
    }

    if lhs.setCode != rhs.setCode {
      return lhs.setCode < rhs.setCode
    }
    if lhs.collectorNumberNumber != rhs.collectorNumberNumber {
      return (lhs.collectorNumberNumber ?? Int.max) < (rhs.collectorNumberNumber ?? Int.max)
    }
    if lhs.collectorNumber != rhs.collectorNumber {
      return lhs.collectorNumber < rhs.collectorNumber
    }
    return lhs.id < rhs.id
  }

  static func isFirstNonEmpty(_ value: String?, before previousValues: [String?]) -> Bool {
    guard let value, !value.isEmpty else {
      return false
    }
    return !previousValues.compactMap { $0 }.contains(value)
  }

  static func joinedTypeText(_ card: CardRecord) -> String {
    ([card.typeLine] + card.faces.map(\.typeLine)).joined(separator: " ")
  }

  static func joinedOracleText(_ card: CardRecord) -> String {
    ([card.oracleText] + card.faces.map(\.oracleText)).joined(separator: " ")
  }

  static func serializedList(_ values: [String]) -> String {
    let normalized = values
      .map { $0.normalizedSearchKey }
      .filter { !$0.isEmpty }
      .sorted()
    guard !normalized.isEmpty else {
      return ""
    }
    return "|\(normalized.joined(separator: "|"))|"
  }

  static func deserializedList(_ value: String?) -> [String] {
    guard let value, !value.isEmpty else {
      return []
    }
    return value.split(separator: "|").map(String.init)
  }

  static func serializedLegalities(_ legalities: [String: String]) -> String {
    let values = legalities.map { "\($0.key.normalizedSearchKey):\($0.value.normalizedSearchKey)" }.sorted()
    guard !values.isEmpty else {
      return ""
    }
    return "|\(values.joined(separator: "|"))|"
  }

  static func deserializedLegalities(_ value: String?) -> [String: String] {
    deserializedList(value).reduce(into: [:]) { result, item in
      let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
      if parts.count == 2 {
        result[parts[0]] = parts[1]
      }
    }
  }

  static func containsValue(_ needle: String, in values: [String]) -> Bool {
    values.contains { $0.normalizedSearchKey == needle }
  }

}

extension String {
  var sortKey: String {
    normalizedSearchKey
  }

  var normalizedSearchKey: String {
    folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }
}
