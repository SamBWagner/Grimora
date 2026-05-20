import Foundation

public enum FilterPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case universesBeyond
    case alchemy
    case realCards

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .universesBeyond:
            "Universes Beyond"
        case .alchemy:
            "Alchemy"
        case .realCards:
            "Real Cards"
        }
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .universesBeyond:
            "filter-universes-beyond"
        case .alchemy:
            "filter-alchemy"
        case .realCards:
            "filter-real-cards"
        }
    }
}

