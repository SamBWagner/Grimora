import GrimoraCore

enum ListNameAction {
    case create(adding: CardRecord?, selectAfterCreate: Bool)
    case createWithCardIDs([CardRecord.ID], selectAfterCreate: Bool)
    case createFromSearch
    case rename(CardListRecord)
    case createCategory(listID: CardListRecord.ID)
    case renameCategory(CardListCategoryRecord)

    var title: String {
        switch self {
        case .create, .createWithCardIDs, .createFromSearch:
            "New List"
        case .rename:
            "Rename List"
        case .createCategory:
            "New Category"
        case .renameCategory:
            "Rename Category"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .create, .createWithCardIDs, .createFromSearch, .createCategory:
            "Create"
        case .rename, .renameCategory:
            "Rename"
        }
    }
}
