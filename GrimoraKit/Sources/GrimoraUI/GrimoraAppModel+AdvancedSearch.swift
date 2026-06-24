import Foundation
import GrimoraCore

extension GrimoraAppModel {
    /// Runs the query described by an ``AdvancedSearchBuilder`` through the normal
    /// Scryfall submit path (S1), so it records history, honours always-included
    /// terms, and behaves identically to a typed query. No-op for an empty form.
    public func applyAdvancedSearch(_ builder: AdvancedSearchBuilder) async {
        let query = builder.scryfallQuery
        guard !query.isEmpty else {
            return
        }

        closeSelectedCard()
        setSearchDraft(query)
        await submitSearch()
    }
}
