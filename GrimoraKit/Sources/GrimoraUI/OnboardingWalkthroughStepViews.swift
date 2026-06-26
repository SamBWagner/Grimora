import SwiftUI

/// Monospaced pill for a Scryfall token like `t:elf`, reused by the operators
/// cheatsheet and the interactive playground chips.
struct OnboardingOperatorTokenLabel: View {
  let token: String
  var palette: GrimoraPalette

  var body: some View {
    Text(token)
      .font(.caption.monospaced().weight(.medium))
      .foregroundStyle(palette.accent.color)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        palette.accent.color.opacity(0.12),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
      )
  }
}

/// Compact tile for one sample card: name, summary, and an optional trailing
/// accessory (a star, an add button, etc.).
struct OnboardingSampleCardTile<Accessory: View>: View {
  let card: GrimoraOnboardingSampleCard
  var palette: GrimoraPalette
  @ViewBuilder var accessory: () -> Accessory

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(card.name)
          .font(.callout.weight(.semibold))
          .foregroundStyle(palette.primaryText.color)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(card.summary)
          .font(.caption2)
          .foregroundStyle(palette.secondaryText.color)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }

      Spacer(minLength: 8)

      accessory()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(palette.hairline.color, lineWidth: 1)
    }
  }
}

extension OnboardingSampleCardTile where Accessory == EmptyView {
  init(card: GrimoraOnboardingSampleCard, palette: GrimoraPalette) {
    self.init(card: card, palette: palette) { EmptyView() }
  }
}

/// Welcome step: a read-only preview of the ten sample cards the tour uses.
struct OnboardingWelcomeStepView: View {
  let cards: [GrimoraOnboardingSampleCard]
  var palette: GrimoraPalette

  private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(cards) { card in
        OnboardingSampleCardTile(card: card, palette: palette)
      }
    }
    .accessibilityIdentifier("onboarding-welcome-sample-grid")
  }
}

/// Operators step: the cheatsheet of common operators with example tokens.
struct OnboardingOperatorsStepView: View {
  let operators: [GrimoraOnboardingOperator]
  var palette: GrimoraPalette

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(operators.enumerated()), id: \.element.id) { index, op in
        if index > 0 {
          Divider().overlay(palette.hairline.color)
        }
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          OnboardingOperatorTokenLabel(token: op.token, palette: palette)
            .frame(width: 78, alignment: .leading)

          VStack(alignment: .leading, spacing: 2) {
            Text(op.title)
              .font(.callout.weight(.semibold))
              .foregroundStyle(palette.primaryText.color)
            Text(op.detail)
              .font(.caption)
              .foregroundStyle(palette.secondaryText.color)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-operator-\(op.id)")
      }
    }
    .padding(.horizontal, 14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(palette.hairline.color, lineWidth: 1)
    }
  }
}

/// Lists step: tap a sample card to file it into a demo list (sandboxed — no real
/// data is written).
struct OnboardingListsStepView: View {
  let cards: [GrimoraOnboardingSampleCard]
  var palette: GrimoraPalette

  @State private var filedCardIDs: Set<String> = []

  private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(cards) { card in
          Button {
            toggle(card)
          } label: {
            OnboardingSampleCardTile(card: card, palette: palette) {
              Image(systemName: filedCardIDs.contains(card.id) ? "checkmark.circle.fill" : "plus.circle")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                  filedCardIDs.contains(card.id) ? palette.accent.color : palette.secondaryText.color
                )
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            filedCardIDs.contains(card.id)
              ? "Remove \(card.name) from the sample collection"
              : "Add \(card.name) to the sample collection"
          )
          .accessibilityIdentifier("onboarding-list-card-\(card.id)")
        }
      }

      Label(filedSummary, systemImage: "list.bullet.rectangle")
        .font(.footnote.weight(.medium))
        .foregroundStyle(palette.secondaryText.color)
        .animation(.easeInOut(duration: 0.15), value: filedCardIDs)
        .accessibilityIdentifier("onboarding-list-summary")
    }
  }

  private var filedSummary: String {
    let count = filedCardIDs.count
    return count == 0
      ? "Sample Collection — tap cards above to add them"
      : "Sample Collection — \(count) card\(count == 1 ? "" : "s")"
  }

  private func toggle(_ card: GrimoraOnboardingSampleCard) {
    if filedCardIDs.contains(card.id) {
      filedCardIDs.remove(card.id)
    } else {
      filedCardIDs.insert(card.id)
    }
  }
}

/// Favourites step: tap a card's star to favourite it (sandboxed demo).
struct OnboardingFavouritesStepView: View {
  let cards: [GrimoraOnboardingSampleCard]
  var palette: GrimoraPalette

  @State private var favouritedCardIDs: Set<String> = []

  private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(cards) { card in
          OnboardingSampleCardTile(card: card, palette: palette) {
            Button {
              toggle(card)
            } label: {
              Image(systemName: favouritedCardIDs.contains(card.id) ? "star.fill" : "star")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                  favouritedCardIDs.contains(card.id) ? .yellow : palette.secondaryText.color
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              favouritedCardIDs.contains(card.id)
                ? "Remove \(card.name) from Favourites"
                : "Add \(card.name) to Favourites"
            )
            .accessibilityIdentifier("onboarding-favourite-card-\(card.id)")
          }
        }
      }

      Label(favouriteSummary, systemImage: "star.fill")
        .font(.footnote.weight(.medium))
        .foregroundStyle(palette.secondaryText.color)
        .animation(.easeInOut(duration: 0.15), value: favouritedCardIDs)
        .accessibilityIdentifier("onboarding-favourite-summary")
    }
  }

  private var favouriteSummary: String {
    let count = favouritedCardIDs.count
    return count == 0
      ? "Favourites — tap a star to add"
      : "Favourites — \(count) card\(count == 1 ? "" : "s")"
  }

  private func toggle(_ card: GrimoraOnboardingSampleCard) {
    if favouritedCardIDs.contains(card.id) {
      favouritedCardIDs.remove(card.id)
    } else {
      favouritedCardIDs.insert(card.id)
    }
  }
}
