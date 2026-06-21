import Foundation
import GrimoraCore

public final class HiddenSearchTermsStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = GrimoraSearchPreferences.hiddenSearchTermsKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func load() -> [SearchRefinement] {
        guard let data = userDefaults.data(forKey: key),
              let refinements = try? JSONDecoder().decode([SearchRefinement].self, from: data)
        else {
            return []
        }
        return SearchRefinement.normalizedHiddenTerms(refinements)
    }

    public func save(_ refinements: [SearchRefinement]) {
        let normalized = SearchRefinement.normalizedHiddenTerms(refinements)
        guard !normalized.isEmpty,
              let data = try? JSONEncoder().encode(normalized)
        else {
            userDefaults.removeObject(forKey: key)
            return
        }
        userDefaults.set(data, forKey: key)
    }

    public func clear() {
        userDefaults.removeObject(forKey: key)
    }

}
