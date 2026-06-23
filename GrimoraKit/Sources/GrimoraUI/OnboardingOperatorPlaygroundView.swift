import SwiftUI

/// Interactive search step: the user taps an operator chip and watches the sample
/// set filter live. Entirely self-contained — it matches against the in-memory
/// sample cards via ``GrimoraOnboardingOperator``, never the real search engine.
struct OnboardingOperatorPlaygroundView: View {
  let cards: [GrimoraOnboardingSampleCard]
  let operators: [GrimoraOnboardingOperator]
  var palette: GrimoraPalette

  @State private var selectedOperatorID: String?

  private let chipColumns = [GridItem(.adaptive(minimum: 92), spacing: 8)]
  private let cardColumns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

  private var selectedOperator: GrimoraOnboardingOperator? {
    operators.first { $0.id == selectedOperatorID }
  }

  private var matchedCards: [GrimoraOnboardingSampleCard] {
    selectedOperator?.matchingCards(in: cards) ?? cards
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: chipColumns, spacing: 8) {
        ForEach(operators) { op in
          chip(for: op)
        }
      }

      Text(matchSummary)
        .font(.footnote.weight(.medium))
        .foregroundStyle(palette.secondaryText.color)
        .animation(.easeInOut(duration: 0.15), value: selectedOperatorID)
        .accessibilityIdentifier("onboarding-playground-summary")

      LazyVGrid(columns: cardColumns, spacing: 8) {
        ForEach(matchedCards) { card in
          OnboardingSampleCardTile(card: card, palette: palette)
        }
      }
      .animation(.easeInOut(duration: 0.18), value: matchedCards)
    }
    .accessibilityIdentifier("onboarding-operator-playground")
  }

  private func chip(for op: GrimoraOnboardingOperator) -> some View {
    let isSelected = op.id == selectedOperatorID
    return Button {
      selectedOperatorID = isSelected ? nil : op.id
    } label: {
      VStack(spacing: 3) {
        Text(op.title)
          .font(.caption.weight(.semibold))
        Text(op.token)
          .font(.caption2.monospaced())
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .padding(.horizontal, 6)
      .background(
        isSelected ? palette.accent.color.opacity(0.18) : palette.hairline.color.opacity(0.18),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(isSelected ? palette.accent.color : palette.hairline.color, lineWidth: 1)
      }
      .foregroundStyle(isSelected ? palette.accent.color : palette.primaryText.color)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("onboarding-playground-chip-\(op.id)")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var matchSummary: String {
    guard let selectedOperator else {
      return "Showing all \(cards.count) sample cards"
    }
    let count = matchedCards.count
    return "\(selectedOperator.token) matches \(count) of \(cards.count) cards"
  }
}
