import GrimoraCore

enum CollectionNameAction {
    case create(adding: CardRecord?, selectAfterCreate: Bool)
    case createWithCardIDs([CardRecord.ID], selectAfterCreate: Bool)
    case createFromSearch
    case rename(CardCollectionRecord)
    case createCategory(listID: CardCollectionRecord.ID)
    case renameCategory(CardCollectionCategoryRecord)

    var title: String {
        switch self {
        case .create, .createWithCardIDs, .createFromSearch:
            "New Collection"
        case .rename:
            "Rename Collection"
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
