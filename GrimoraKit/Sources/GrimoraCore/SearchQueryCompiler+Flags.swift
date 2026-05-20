import Foundation

extension Compiler {
    func compileHas(_ value: String, original: String) throws -> CompiledClause {
        switch value {
        case "watermark":
            return CompiledClause(sql: "watermark IS NOT NULL AND watermark != ''")
        case "indicator":
            return CompiledClause(sql: "color_indicator_key != ''")
        default:
            throw QueryError.unsupported(query: query, token: original)
        }
    }

    func compileNew(_ value: String, original: String) throws -> CompiledClause {
        switch value {
        case "art":
            return CompiledClause(sql: "is_new_art = 1")
        case "artist":
            return CompiledClause(sql: "is_new_artist = 1")
        case "flavor":
            return CompiledClause(sql: "is_new_flavor = 1")
        case "rarity":
            return CompiledClause(sql: "is_new_rarity = 1")
        case "frame":
            return CompiledClause(sql: "is_new_frame = 1")
        case "language":
            return CompiledClause(sql: "is_new_language = 1")
        default:
            throw QueryError.unsupported(query: query, token: original)
        }
    }

    func compileFlag(_ value: String, original: String) throws -> CompiledClause {
        switch value {
        case "split", "flip", "transform", "meld", "leveler", "modal_dfc", "mdfc":
            let layout = value == "mdfc" ? "modal_dfc" : value
            return CompiledClause(sql: "layout_key = ?", bindings: [.text(layout)])
        case "dfc", "tdfc":
            return CompiledClause(sql: "layout_key IN ('transform', 'modal_dfc', 'double_faced_token')")
        case "meldpart":
            return CompiledClause(sql: "layout_key = 'meld'")
        case "meldresult":
            return CompiledClause(sql: "layout_key = 'meld_result'")
        case "spell":
            return CompiledClause(sql: "type_line_key NOT LIKE '%land%'")
        case "permanent":
            return CompiledClause(sql: permanentTypeSQL())
        case "historic":
            return CompiledClause(sql: "(type_line_key LIKE '%legendary%' OR type_line_key LIKE '%artifact%' OR type_line_key LIKE '%saga%')")
        case "party":
            return CompiledClause(sql: partySQL())
        case "outlaw":
            return CompiledClause(sql: outlawSQL())
        case "modal":
            return CompiledClause(sql: "(oracle_text_key LIKE '%choose one%' OR oracle_text_key LIKE '%choose two%' OR layout_key IN ('split', 'modal_dfc'))")
        case "vanilla":
            return CompiledClause(sql: "oracle_text_key = '' AND type_line_key LIKE '%creature%'")
        case "frenchvanilla":
            return CompiledClause(sql: "type_line_key LIKE '%creature%' AND keywords_key != ''")
        case "bear":
            return CompiledClause(sql: "type_line_key LIKE '%creature%' AND mana_value = 2 AND power_value = 2 AND toughness_value = 2")
        case "manland":
            return CompiledClause(sql: "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%becomes%creature%'")
        case "funny":
            return CompiledClause(sql: "(set_type = 'funny' OR border_color = 'silver' OR security_stamp = 'acorn')")
        case "booster":
            return CompiledClause(sql: "is_booster = 1")
        case "planeswalker_deck", "league", "buyabox", "giftbox", "intro_pack", "gameday", "prerelease", "release", "fnm", "judge_gift", "arena_league", "player_rewards", "media_insert", "instore", "convention", "set_promo", "datestamped":
            return compileListContains(column: "promo_types_key", value: value)
        case "commander", "brawler", "duelcommander", "oathbreaker":
            return CompiledClause(sql: "(type_line_key LIKE '%legendary%creature%' OR oracle_text_key LIKE '%can be your commander%')")
        case "companion", "partner":
            return CompiledClause(sql: "keywords_key LIKE ? OR oracle_text_key LIKE ?", bindings: [.text("%|\(value)|%"), .text("%\(value)%")])
        case "gamechanger":
            return CompiledClause(sql: "is_game_changer = 1")
        case "newinpauper":
            return CompiledClause(sql: "rarity = 'common' AND is_new_rarity = 1")
        case "reserved":
            return CompiledClause(sql: "is_reserved = 1")
        case "digital":
            return CompiledClause(sql: "is_digital = 1")
        case "alchemy":
            return CompiledClause(sql: "is_alchemy = 1")
        case "rebalanced":
            return CompiledClause(sql: "promo_types_key LIKE '%|rebalanced|%' OR name_key LIKE 'a-%'")
        case "promo":
            return CompiledClause(sql: "is_promo = 1")
        case "spotlight":
            return CompiledClause(sql: "is_story_spotlight = 1")
        case "scryfallpreview":
            return compileListContains(column: "promo_types_key", value: "scryfallpreview")
        case "full":
            return CompiledClause(sql: "is_full_art = 1")
        case "foil":
            return CompiledClause(sql: "is_foil = 1")
        case "nonfoil":
            return CompiledClause(sql: "is_nonfoil = 1")
        case "etched":
            return CompiledClause(sql: "finishes_key LIKE '%|etched|%' OR frame_effects_key LIKE '%|etched|%'")
        case "glossy":
            return compileListContains(column: "finishes_key", value: "glossy")
        case "hires":
            return CompiledClause(sql: "is_high_resolution = 1")
        case "universesbeyond", "ub":
            return CompiledClause(sql: "is_universes_beyond = 1")
        case "default":
            return CompiledClause(sql: "is_base_printing = 1")
        case "atypical":
            return CompiledClause(sql: "is_base_printing = 0")
        case "new":
            return CompiledClause(sql: "is_reprint = 0")
        case "old":
            return CompiledClause(sql: "is_reprint = 1")
        case "reprint":
            return CompiledClause(sql: "is_reprint = 1")
        case "unique":
            return CompiledClause(sql: "print_count = 1")
        case "hybrid":
            return CompiledClause(sql: "mana_cost LIKE '%/%'")
        case "phyrexian":
            return CompiledClause(sql: "mana_cost LIKE '%/P}%'")
        case "colorshifted", "masterpiece":
            return compileListContains(column: "frame_effects_key", value: value)
        default:
            if let shortcut = try compileStandaloneShortcut(value) {
                return shortcut
            }
            throw QueryError.unsupported(query: query, token: original)
        }
    }

    func compileStandaloneShortcut(_ value: String) throws -> CompiledClause? {
        if let colors = colorNicknames[value] {
            return try compileColor(column: "colors_key", countColumn: "color_count", op: ">=", value: colors, original: value)
        }
        if ["w", "u", "b", "r", "g", "white", "blue", "black", "red", "green", "colorless", "multicolor"].contains(value) {
            return try compileColor(column: "colors_key", countColumn: "color_count", op: value == "multicolor" ? ">" : ">=", value: value, original: value)
        }
        if let sql = landShortcutSQL(value) { return CompiledClause(sql: sql) }
        return nil
    }

    func permanentTypeSQL() -> String {
        "(type_line_key LIKE '%artifact%' OR type_line_key LIKE '%battle%' OR type_line_key LIKE '%creature%' OR type_line_key LIKE '%enchantment%' OR type_line_key LIKE '%land%' OR type_line_key LIKE '%planeswalker%')"
    }

    func partySQL() -> String {
        "(type_line_key LIKE '%cleric%' OR type_line_key LIKE '%rogue%' OR type_line_key LIKE '%warrior%' OR type_line_key LIKE '%wizard%')"
    }

    func outlawSQL() -> String {
        "(type_line_key LIKE '%assassin%' OR type_line_key LIKE '%mercenary%' OR type_line_key LIKE '%pirate%' OR type_line_key LIKE '%rogue%' OR type_line_key LIKE '%warlock%')"
    }

}
