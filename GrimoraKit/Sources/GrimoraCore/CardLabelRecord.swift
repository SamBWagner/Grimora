import Foundation

/// A curated, fixed set of colours a label can use. Stored as its `rawValue` token in the
/// `card_labels.color` column (not a raw hex string) so pips stay crisp, on-brand, and correct in
/// both light and dark — the concrete `Color` per scheme is resolved in GrimoraUI, mirroring
/// `RarityColor`. Decoding is tolerant: an unknown token (e.g. from a newer app version) falls back
/// to `.grey` via `init(token:)`.
public enum LabelColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case green
    case red
    case blue
    case amber
    case purple
    case orange
    case teal
    case pink
    case grey

    public var id: Self { self }

    /// Maps a stored token to a colour, defaulting unknown/absent tokens to `.grey` so a label
    /// never fails to load just because its colour token isn't recognised.
    public init(token: String?) {
        self = token.flatMap(LabelColor.init(rawValue:)) ?? .grey
    }

    /// A human-readable name for the colour, used in pickers and accessibility.
    public var displayName: String {
        switch self {
        case .green: "Green"
        case .red: "Red"
        case .blue: "Blue"
        case .amber: "Amber"
        case .purple: "Purple"
        case .orange: "Orange"
        case .teal: "Teal"
        case .pink: "Pink"
        case .grey: "Grey"
        }
    }
}

/// A user-defined, colored label that can be attached to cards in a collection as free-form status
/// metadata (e.g. "On the way", "Owned"). Modeled on `CardCollectionCategoryRecord`, but with a
/// colour and an optional list scope: `listID == nil` means the label is **global** (available in
/// every collection); a non-nil `listID` means it is **list-local** to that collection until the
/// user exports it. Assignments (which entries carry the label) live on the entry as `labelIDs`.
public struct CardLabelRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    /// The collection this label is scoped to, or `nil` when the label is global (instance-wide).
    public var listID: String?
    public var name: String
    public var color: LabelColor
    public var position: Int
    public var createdAt: Date
    public var updatedAt: Date

    /// True when the label is available in every collection (not scoped to a single list).
    public var isGlobal: Bool { listID == nil }

    public init(
        id: String,
        listID: String? = nil,
        name: String,
        color: LabelColor,
        position: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.listID = listID
        self.name = name
        self.color = color
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case listID
        case name
        case color
        case position
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        listID = try container.decodeIfPresent(String.self, forKey: .listID)
        name = try container.decode(String.self, forKey: .name)
        color = LabelColor(token: try container.decodeIfPresent(String.self, forKey: .color))
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(listID, forKey: .listID)
        try container.encode(name, forKey: .name)
        try container.encode(color.rawValue, forKey: .color)
        try container.encode(position, forKey: .position)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public extension CardLabelRecord {
    /// The stable, well-known id prefix for built-in default labels. Fixed ids let every device
    /// seed the *same* rows so a cross-device union merge collapses to one set instead of N copies
    /// (the same trick the Favourites list uses with `grimora-favourites`).
    static let builtInIDPrefix = "grimora-label-"

    /// The built-in default labels seeded into a fresh instance. All **global**, all editable /
    /// recolorable / deletable by the user. Seeded with fixed ids and (by default) an **epoch**
    /// timestamp so any real user edit or delete always out-ranks the seed under last-writer-wins.
    static func defaultLabels(seededAt: Date = Date(timeIntervalSince1970: 0)) -> [CardLabelRecord] {
        let specs: [(id: String, name: String, color: LabelColor)] = [
            ("owned", "Owned", .green),
            ("missing", "Missing", .red),
            ("on-the-way", "On the way", .blue),
            ("ordered", "Ordered", .amber),
            ("wishlist", "Wishlist", .purple),
            ("for-trade", "For trade", .orange),
        ]
        return specs.enumerated().map { index, spec in
            CardLabelRecord(
                id: builtInIDPrefix + spec.id,
                listID: nil,
                name: spec.name,
                color: spec.color,
                position: index,
                createdAt: seededAt,
                updatedAt: seededAt
            )
        }
    }

    /// Whether this label is one of the built-in defaults (by id). Used only for optional UI cues
    /// like a "Default" marker or "Reset defaults"; built-ins are otherwise ordinary editable rows.
    var isBuiltInDefault: Bool { id.hasPrefix(Self.builtInIDPrefix) }
}
