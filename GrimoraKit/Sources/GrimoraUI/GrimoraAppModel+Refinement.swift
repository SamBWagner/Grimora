import Foundation
import GrimoraCore

extension GrimoraAppModel {
    public func refineCurrentSearch(with refinement: SearchRefinement) {
        let currentQuery = currentRefinementQuery
        setSearchInputMode(.scryfall)
        setSearchDraft(SearchQuery.appending(refinement, to: currentQuery))
    }

    public func refinementState(for refinement: SearchRefinement) -> SearchRefinementState {
        SearchQuery.state(for: refinement, in: currentRefinementQuery)
    }

    public func applySearchRefinements(_ updates: [SearchRefinementUpdate]) {
        let updatedQuery = SearchQuery.applying(updates, to: currentRefinementQuery)
        setSearchInputMode(.scryfall)
        setSearchDraft(updatedQuery)
    }

    public func addHiddenTerm(_ refinement: SearchRefinement) {
        let excluded = refinement.withIntent(.exclude)
        guard !hiddenSearchTerms.contains(where: { $0.id == excluded.id }) else {
            return
        }
        hiddenSearchTerms.append(excluded)
        hiddenSearchTermsStore.save(hiddenSearchTerms)
        hiddenSearchTermsDidChange(reason: "hidden-search-term-added")
    }

    public func removeHiddenTerm(_ refinement: SearchRefinement) {
        let previousCount = hiddenSearchTerms.count
        hiddenSearchTerms.removeAll { $0.id == refinement.withIntent(.exclude).id }
        guard hiddenSearchTerms.count != previousCount else {
            return
        }
        hiddenSearchTermsStore.save(hiddenSearchTerms)
        hiddenSearchTermsDidChange(reason: "hidden-search-term-removed")
    }

    public func clearHiddenTerms() {
        guard !hiddenSearchTerms.isEmpty else {
            return
        }
        hiddenSearchTerms = []
        hiddenSearchTermsStore.clear()
        hiddenSearchTermsDidChange(reason: "hidden-search-terms-cleared")
    }

    public func candidateRefinements(for card: CardRecord) -> [SearchRefinementGroup] {
        var groups: [SearchRefinementGroup] = []

        let keywords = card.keywords
            .map { SearchRefinement.forKeyword($0) }
            .uniquedByID()
        if !keywords.isEmpty {
            groups.append(SearchRefinementGroup(title: "Keywords", refinements: keywords))
        }

        let typeWords = card.typeLine
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { SearchRefinement.forTypeWord($0) }
            .uniquedByID()
        if !typeWords.isEmpty {
            groups.append(SearchRefinementGroup(title: "Type", refinements: typeWords))
        }

        groups.append(
            SearchRefinementGroup(
                title: "Color Identity",
                refinements: [.forColorIdentity(card.colorIdentity)]
            )
        )

        if let manaValue = card.manaValue {
            groups.append(
                SearchRefinementGroup(
                    title: "Mana Value",
                    refinements: [.forManaValue(manaValue)]
                )
            )
        }

        if !card.rarity.isEmpty {
            groups.append(
                SearchRefinementGroup(
                    title: "Rarity",
                    refinements: [.forRarity(card.rarity)]
                )
            )
        }

        if !card.setCode.isEmpty {
            groups.append(
                SearchRefinementGroup(
                    title: "Set",
                    refinements: [.forSet(code: card.setCode, name: card.setName)]
                )
            )
        }

        return groups
    }

    func effectiveSearchText(_ submitted: String) -> String {
        let hiddenQuery = hiddenSearchTerms.reduce(submitted) { query, refinement in
            SearchQuery.appending(refinement.withIntent(.exclude), to: query)
        }
        return defaultSearchConfiguration.searchText(includingAlwaysIncluded: hiddenQuery)
    }

    func applySyncedHiddenSearchTerms(_ refinements: [SearchRefinement]) {
        hiddenSearchTerms = SearchRefinement.normalizedHiddenTerms(refinements)
        hiddenSearchTermsStore.save(hiddenSearchTerms)
    }

    private func hiddenSearchTermsDidChange(reason: String) {
        reloadSearch()
        guard !isApplyingCloudSyncState else {
            return
        }
        markCloudSyncSearchSettingsChanged()
        if cloudSyncMode == .enabled {
            try? database.recordLocalSyncSnapshotChange(reason: reason)
            pushCloudSyncChangesIfNeeded()
        }
    }

    private var currentRefinementQuery: String {
        searchInputMode == .scryfall
            ? submittedSearchText
            : (generatedSearchQuery ?? "")
    }
}

private extension Array where Element == SearchRefinement {
    func uniquedByID() -> [SearchRefinement] {
        var seen: Set<SearchRefinement.ID> = []
        return filter { seen.insert($0.id).inserted }
    }
}
