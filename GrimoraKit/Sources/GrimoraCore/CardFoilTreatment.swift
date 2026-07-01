import Foundation

/// The distinguishable real-world finish/foil *treatment* of a printing — what kind of shimmer
/// (if any) the card should render and how it should be badged.
///
/// This is a derived, display-oriented taxonomy that sits on top of two pieces of Scryfall data
/// the catalog already stores:
///
/// - **`finishes`** — only ever `nonfoil` / `foil` / `etched`. This is the *selectable* axis
///   (`CardValueFinish`, also the pricing axis): a single printing such as MH2 #271 Wonder can
///   exist as all three, and the user picks which they own.
/// - **`promo_types`** — the *special-treatment* axis (`surgefoil`, `halofoil`, `galaxyfoil`, …).
///   These are intrinsic to a printing: the halo-foil Utvara Hellkite is its own collector number
///   (`finishes == ["foil"]`, `promo_types == ["halofoil"]`), so the treatment is read off the
///   printing rather than chosen by the user.
///
/// The two axes are combined by `CardRecord.foilTreatment(for:)`: a `.normal` selection renders
/// `.none`, `.etched` renders `.etched`, and `.foil` renders the printing's special treatment if it
/// has one, otherwise plain `.standard` foil.
public enum CardFoilTreatment: String, CaseIterable, Codable, Equatable, Sendable {
    /// No shimmer — a plain non-foil card.
    case none
    /// Plain holographic foil (the original generic sheen).
    case standard
    /// Matte "etched" foil — a `finishes` value, not a promo type. Same art as the normal printing.
    case etched

    // Special promo-type treatments, layered over a `foil` finish.
    case surge
    case halo
    case galaxy
    case oilSlick
    case confetti
    case ripple
    case fracture
    case mana
    case neonInk
    case stepAndCompleat
    case invisibleInk
    case doubleRainbow
    case rainbow
    case gilded
    case textured
    case embossed
    case raised
    case silver
    case glossy

    /// Human-readable label for badges (e.g. MTG Mate's "Foil" / "Etched" chips).
    public var displayName: String {
        switch self {
        case .none: ""
        case .standard: "Foil"
        case .etched: "Etched"
        case .surge: "Surge Foil"
        case .halo: "Halo Foil"
        case .galaxy: "Galaxy Foil"
        case .oilSlick: "Oil Slick"
        case .confetti: "Confetti Foil"
        case .ripple: "Ripple Foil"
        case .fracture: "Fracture Foil"
        case .mana: "Mana Foil"
        case .neonInk: "Neon Ink"
        case .stepAndCompleat: "Step-and-Compleat"
        case .invisibleInk: "Invisible Ink"
        case .doubleRainbow: "Double Rainbow"
        case .rainbow: "Rainbow Foil"
        case .gilded: "Gilded Foil"
        case .textured: "Textured Foil"
        case .embossed: "Embossed"
        case .raised: "Raised Foil"
        case .silver: "Silver Foil"
        case .glossy: "Glossy"
        }
    }

    /// Whether this treatment is a special promo-type foil (i.e. not plain foil / etched / none).
    public var isSpecial: Bool {
        switch self {
        case .none, .standard, .etched: false
        default: true
        }
    }

    /// Maps Scryfall `promo_types` tokens to the special treatments they denote, in resolution
    /// priority order. Priority matters because a single printing can carry more than one token
    /// (e.g. `["oilslick", "raisedfoil"]` — the oil-slick look is the distinctive one). Tokens
    /// are the exact lowercased strings Scryfall stores (verified against the live API).
    static let orderedSpecialTokens: [(token: String, treatment: CardFoilTreatment)] = [
        ("surgefoil", .surge),
        ("halofoil", .halo),
        ("galaxyfoil", .galaxy),
        ("oilslick", .oilSlick),
        ("confettifoil", .confetti),
        ("ripplefoil", .ripple),
        ("fracturefoil", .fracture),
        ("manafoil", .mana),
        ("neonink", .neonInk),
        ("stepandcompleat", .stepAndCompleat),
        ("invisibleink", .invisibleInk),
        ("doublerainbow", .doubleRainbow),
        ("rainbowfoil", .rainbow),
        ("gilded", .gilded),
        ("textured", .textured),
        ("embossed", .embossed),
        ("raisedfoil", .raised),
        ("silverfoil", .silver),
        ("glossy", .glossy)
    ]

    /// The set of `promo_types` tokens that denote a foil treatment — used by search to surface
    /// `is:surgefoil`, `is:halofoil`, etc.
    public static let promoTypeTokens: Set<String> = Set(orderedSpecialTokens.map(\.token))

    /// The special treatment a printing's `promo_types` denote, if any. Returns `nil` when the
    /// printing carries no recognised foil-treatment token (a plain foil or non-foil printing).
    public static func from(promoTypes: [String]) -> CardFoilTreatment? {
        guard !promoTypes.isEmpty else { return nil }
        let tokens = Set(promoTypes)
        for entry in orderedSpecialTokens where tokens.contains(entry.token) {
            return entry.treatment
        }
        return nil
    }
}
