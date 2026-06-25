import GrimoraCore
import SwiftUI

/// A retail destination a card can be bought from. The list is intentionally
/// small and data-driven: adding another shop is a matter of appending to
/// ``PurchaseProvider/all``.
struct PurchaseProvider: Identifiable, Sendable {
    let id: String
    let displayName: String
    let iconSystemImage: String

    /// Builds the destination URL for a card, or `nil` if one can't be formed.
    let purchaseURL: @Sendable (CardRecord) -> URL?

    /// Every provider offered in the Buy menu, in display order.
    static let all: [PurchaseProvider] = [.mtgMate]
}

extension PurchaseProvider {
    /// MTG Mate — Brisbane MTG singles store. Deep-links to the card's listing
    /// page (`/cards/{name}`), where the buyer chooses printing/condition and
    /// adds to cart. We can't pre-fill the cart without their internal product
    /// IDs, so the card page is the correct landing spot.
    static let mtgMate = PurchaseProvider(
        id: "mtgmate",
        displayName: "MTG Mate",
        iconSystemImage: "bag"
    ) { card in
        mtgMateURL(for: card)
    }

    static func mtgMateURL(for card: CardRecord) -> URL? {
        let name = searchName(for: card)
        guard !name.isEmpty, let encoded = encodedPathSegment(name) else {
            return nil
        }
        return URL(string: "https://www.mtgmate.com.au/cards/\(encoded)")
    }

    /// The single-face name to search by. Multi-face cards (DFC / split /
    /// adventure) carry a "Front // Back" name but are listed under the front
    /// name on retail sites, so prefer the front face.
    static func searchName(for card: CardRecord) -> String {
        if let front = card.faces.first?.name,
           !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return front
        }

        let name = card.name
        if let separator = name.range(of: " // ") {
            return String(name[..<separator.lowerBound])
        }
        return name
    }

    /// Percent-encodes a value for use as a URL path segment. Mirrors the idiom
    /// in `CardShareContent.encodedPathSegment`: keep path-legal characters,
    /// encode spaces and the segment-breaking `/?#`.
    private static func encodedPathSegment(_ value: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

/// The provider buttons themselves, owning the `openURL` action. Each opens the
/// chosen retailer's page for `card` in the system browser, keeping the user's
/// login and cart session intact for checkout. Shared by ``CardBuyMenu`` and by
/// call sites that want to supply their own menu label (e.g. the card detail
/// toolbar's icon button).
struct CardBuyMenuItems: View {
    let card: CardRecord
    @Environment(\.openURL) private var openURL

    var body: some View {
        ForEach(PurchaseProvider.all) { provider in
            Button {
                if let url = provider.purchaseURL(card) {
                    openURL(url)
                }
            } label: {
                Label(provider.displayName, systemImage: provider.iconSystemImage)
            }
            .accessibilityIdentifier("card-buy-provider-\(provider.id)-\(card.id)")
        }
    }
}

/// Long-press / context-menu "Buy" submenu with the default cart label.
struct CardBuyMenu: View {
    let card: CardRecord

    var body: some View {
        Menu {
            CardBuyMenuItems(card: card)
        } label: {
            Label("Buy", systemImage: "cart")
        }
        .accessibilityIdentifier("card-buy-menu-\(card.id)")
    }
}
