import GrimoraCore

public struct SearchRefinementGroup: Identifiable, Sendable {
    public var title: String
    public var refinements: [SearchRefinement]

    public var id: String { title }

    public init(title: String, refinements: [SearchRefinement]) {
        self.title = title
        self.refinements = refinements
    }
}
