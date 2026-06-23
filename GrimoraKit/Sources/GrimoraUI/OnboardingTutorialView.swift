import SwiftUI

/// First-run walkthrough container.
///
/// S8a scaffold: introduces the tour and lists the curated sample set the later
/// steps teach with. The interactive steps and quizzes are filled in by S8b/S8c;
/// for now this presents the welcome and is skippable at any time. Both the Skip
/// and primary actions mark onboarding complete via ``GrimoraOnboardingModel``.
struct OnboardingTutorialView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var onboarding: GrimoraOnboardingModel

  var body: some View {
    ZStack {
      GrimoraAppBackground(palette: palette)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        skipBar

        ScrollView {
          VStack(spacing: 22) {
            header
            sampleSetSection
          }
          .padding(.horizontal, 26)
          .padding(.bottom, 24)
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
        }

        primaryAction
      }
    }
    .tint(palette.accent.color)
    .accessibilityIdentifier("onboarding-tutorial")
  }

  private var skipBar: some View {
    HStack {
      Spacer()
      Button {
        onboarding.complete()
      } label: {
        Text("Skip")
          .font(.callout.weight(.medium))
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("onboarding-skip-button")
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 4)
  }

  private var header: some View {
    VStack(spacing: 14) {
      GrimoraLogoView(size: 72)
        .shadow(color: palette.shadow.color, radius: 16, x: 0, y: 9)

      Text("Welcome to Grimora")
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.primaryText.color)
        .multilineTextAlignment(.center)

      Text(
        "A quick tour of Scryfall search. We'll use these ten cards to show how operators find exactly the cards you want."
      )
      .font(.callout)
      .foregroundStyle(palette.secondaryText.color)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 12)
  }

  private var sampleSetSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Your sample set")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.secondaryText.color)

      VStack(spacing: 0) {
        ForEach(Array(onboarding.sampleCards.enumerated()), id: \.element.id) { index, card in
          if index > 0 {
            Divider().overlay(palette.hairline.color)
          }
          sampleCardRow(card)
        }
      }
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(palette.hairline.color, lineWidth: 1)
      }
    }
  }

  private func sampleCardRow(_ card: GrimoraOnboardingSampleCard) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(card.name)
          .font(.callout.weight(.semibold))
          .foregroundStyle(palette.primaryText.color)
        Text(card.summary)
          .font(.caption)
          .foregroundStyle(palette.secondaryText.color)
      }

      Spacer(minLength: 12)

      Text(card.teachingPoint)
        .font(.caption2.weight(.medium))
        .foregroundStyle(palette.secondaryText.color)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("onboarding-sample-\(card.id)")
  }

  private var primaryAction: some View {
    Button {
      onboarding.complete()
    } label: {
      Text("Got It")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .padding(.horizontal, 26)
    .padding(.vertical, 16)
    .frame(maxWidth: 560)
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier("onboarding-done-button")
  }

  private var palette: GrimoraPalette {
    GrimoraPalette(colorScheme: colorScheme)
  }
}

#Preview {
  OnboardingTutorialView(onboarding: GrimoraOnboardingModel())
}
