import Foundation

extension Compiler {
    func landShortcutSQL(_ value: String) -> String? {
        landShortcutSQLByName[value]
    }

    var landShortcutSQLByName: [String: String] {
        [
            "bikeland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%cycling%'",
            "cycleland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%cycling%'",
            "bicycleland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%cycling%'",
            "bondland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more opponents%'",
            "crowdland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more opponents%'",
            "bbdland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more opponents%'",
            "battlebondland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more opponents%'",
            "bounceland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%return a land you control%'",
            "karoo": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%return a land you control%'",
            "canopyland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%sacrifice%' AND oracle_text_key LIKE '%draw a card%'",
            "canland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%sacrifice%' AND oracle_text_key LIKE '%draw a card%'",
            "checkland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%unless you control%'",
            "creatureland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%becomes%creature%'",
            "manland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%becomes%creature%'",
            "dual": "type_line_key LIKE '%land%' AND type_line_key LIKE '%plains%' AND type_line_key LIKE '%island%' OR type_line_key LIKE '%land%' AND type_line_key LIKE '%swamp%' AND type_line_key LIKE '%mountain%'",
            "fastland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or fewer other lands%'",
            "fetchland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%search your library%' AND oracle_text_key LIKE '%land card%'",
            "filterland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%add two mana%'",
            "gainland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%gain 1 life%'",
            "painland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%deals 1 damage to you%'",
            "pathway": "type_line_key LIKE '%land%' AND name_key LIKE '%pathway%'",
            "scryland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%scry 1%'",
            "surveilland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%surveil 1%'",
            "shadowland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%reveal%'",
            "snarl": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%reveal%'",
            "shockland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%pay 2 life%'",
            "slowland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more other lands%'",
            "storageland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%storage counter%'",
            "tangoland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more basic lands%'",
            "battleland": "type_line_key LIKE '%land%' AND oracle_text_key LIKE '%two or more basic lands%'",
            "tricycleland": "type_line_key LIKE '%land%' AND color_identity_count = 3 AND oracle_text_key LIKE '%cycling%'",
            "trikeland": "type_line_key LIKE '%land%' AND color_identity_count = 3 AND oracle_text_key LIKE '%cycling%'",
            "triome": "type_line_key LIKE '%land%' AND color_identity_count = 3 AND oracle_text_key LIKE '%cycling%'",
            "triland": "type_line_key LIKE '%land%' AND color_identity_count = 3"
        ]
    }
}
