#if os(iOS)
import GrimoraCore
import SwiftUI

/// The passive single-mode offer: the identified card as a chip where the
/// shutter button used to live.
///
/// Three gestures:
/// - **tap** — review sheet (confident) or printing picker (ambiguous);
/// - **swipe left** — accept: straight into Scanned, no sheet (confident only);
/// - **swipe right** — "that's wrong": dismiss and scan again.
struct ScryConfirmChip: View {
  let offer: ScrySingleFlow.Offer
  var thresholds: ScryPriceThresholds = .default
  let onTap: () -> Void
  var onSwipeAccept: () -> Void = {}
  var onSwipeRetry: () -> Void = {}

  @State private var dragOffset: CGFloat = 0
  private let swipeThreshold: CGFloat = 64

  private var isConfident: Bool {
    if case .confident = offer.kind { return true }
    return false
  }

  /// The value band of the offered card — drives the chip's accent color, price
  /// badge, and (for `.gold`) its border. Ambiguous offers have no single price.
  private var priceTier: ScryPriceTier {
    if case .confident(let card) = offer.kind {
      return thresholds.tier(forUSD: card.priceUSD)
    }
    return .none
  }

  var body: some View {
    chipContent
      .offset(x: dragOffset)
      .overlay(alignment: .trailing) {
        // Revealed as the chip slides left: swipe-accept.
        swipeHint(systemImage: "tray.and.arrow.down.fill", tint: .green)
          .opacity(isConfident ? hintOpacity(for: -dragOffset) : 0)
          .offset(x: 44)
      }
      .overlay(alignment: .leading) {
        // Revealed as the chip slides right: rescan.
        swipeHint(systemImage: "arrow.counterclockwise", tint: .orange)
          .opacity(hintOpacity(for: dragOffset))
          .offset(x: -44)
      }
      .contentShape(Rectangle())
      .onTapGesture(perform: onTap)
      .gesture(dragGesture)
      .accessibilityIdentifier("scry-confirm-chip")
      .accessibilityLabel(accessibilityText)
      .accessibilityAction(named: "Rescan") { onSwipeRetry() }
      .modifier(AcceptAccessibilityAction(isConfident: isConfident, onAccept: onSwipeAccept))
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        let translation = value.translation.width
        // The accept direction only exists for confident chips; elsewhere the
        // chip resists (rubber-band) instead of pretending it will act.
        if translation < 0, !isConfident {
          dragOffset = translation * 0.2
        } else {
          dragOffset = translation
        }
      }
      .onEnded { value in
        let translation = value.translation.width
        if translation <= -swipeThreshold, isConfident {
          onSwipeAccept()
        } else if translation >= swipeThreshold {
          onSwipeRetry()
        }
        withAnimation(.spring(duration: 0.3)) {
          dragOffset = 0
        }
      }
  }

  private func hintOpacity(for progress: CGFloat) -> Double {
    max(0, min(1, progress / swipeThreshold))
  }

  private func swipeHint(systemImage: String, tint: Color) -> some View {
    Image(systemName: systemImage)
      .font(.title3.weight(.semibold))
      .foregroundStyle(tint)
      .padding(10)
      .background(.ultraThinMaterial, in: Circle())
  }

  private var chipContent: some View {
    HStack(spacing: 12) {
      thumbnail
        .frame(width: 46, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 5))

      VStack(alignment: .leading, spacing: 3) {
        switch offer.kind {
        case .confident(let card):
          Label(card.name, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .labelStyle(ChipLabelStyle(iconColor: priceTier.accentColor ?? .secondary))
          Text("\(card.setCode.uppercased()) \(card.collectorNumber) · \(card.setName)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("Tap to review · ← add · rescan →")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        case .ambiguous(let candidates):
          Label("Which printing?", systemImage: "questionmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .labelStyle(ChipLabelStyle(iconColor: .orange))
          if let first = candidates.first {
            Text(first.name)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text("Tap to pick from \(candidates.count) · rescan →")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      .lineLimit(1)

      priceBadge

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(priceTier.accentColor ?? .clear, lineWidth: priceTier.hasBorder ? 2.5 : 1)
    )
    .shadow(
      color: priceTier.hasBorder ? (priceTier.accentColor ?? .clear).opacity(0.55) : .clear,
      radius: priceTier.hasBorder ? 9 : 0
    )
  }

  /// The card's USD price, tinted by tier. Shown for every identified card so the
  /// value is visible at a glance; hidden only when the price is unknown.
  @ViewBuilder
  private var priceBadge: some View {
    if case .confident(let card) = offer.kind, let price = card.priceUSD {
      Text(price, format: .currency(code: "USD"))
        .font(.subheadline.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(priceTier.accentColor ?? .secondary)
        .lineLimit(1)
    }
  }

  private var accessibilityText: String {
    switch offer.kind {
    case .confident(let card):
      "Identified \(card.name), \(card.setName) number \(card.collectorNumber). Tap to review, or use actions to add or rescan."
    case .ambiguous(let candidates):
      "\(candidates.count) possible printings. Tap to pick one, or rescan."
    }
  }

  @ViewBuilder
  private var thumbnail: some View {
    switch offer.kind {
    case .confident(let card):
      cardThumbnail(card)
    case .ambiguous(let candidates):
      if let first = candidates.first {
        cardThumbnail(first).opacity(0.75)
      } else {
        placeholder
      }
    }
  }

  @ViewBuilder
  private func cardThumbnail(_ card: CardRecord) -> some View {
    if let path = card.smallImagePath ?? card.normalImagePath,
       FileManager.default.fileExists(atPath: path) {
      LocalCardImage(path: path, cornerRadius: 5, contentMode: .fill)
    } else if let urlString = card.smallImageURL ?? card.normalImageURL,
              let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        placeholder
      }
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 5).fill(.quaternary)
  }
}

/// Adds the "Add to Scanned" accessibility action only when the chip is
/// confident — an ambiguous chip has no single card to accept.
private struct AcceptAccessibilityAction: ViewModifier {
  let isConfident: Bool
  let onAccept: () -> Void

  func body(content: Content) -> some View {
    if isConfident {
      content.accessibilityAction(named: "Add to Scanned") { onAccept() }
    } else {
      content
    }
  }
}

private struct ChipLabelStyle: LabelStyle {
  var iconColor: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 5) {
      configuration.icon.foregroundStyle(iconColor)
      configuration.title
    }
  }
}
#endif
