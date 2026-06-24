import SwiftUI

/// First-run walkthrough container.
///
/// Presents the skippable, interactive tour: a sequence of
/// ``GrimoraOnboardingWalkthroughStep`` pages teaching operators, searching,
/// lists, and favourites with the curated sample set. Skip (always available) and
/// finishing both mark onboarding complete via ``GrimoraOnboardingModel``.
struct OnboardingTutorialView: View {
  @Environment(\.colorScheme) private var colorScheme
  var onboarding: GrimoraOnboardingModel

  @State private var step: GrimoraOnboardingWalkthroughStep = .welcome

  private var steps: [GrimoraOnboardingWalkthroughStep] {
    GrimoraOnboardingWalkthroughStep.allCases
  }

  var body: some View {
    ZStack {
      GrimoraAppBackground(palette: palette)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        OnboardingTopBar(steps: steps, current: step, palette: palette, skip: skip)

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(step: step, palette: palette)
            OnboardingStepContent(step: step, cards: onboarding.sampleCards, palette: palette)
          }
          .padding(.horizontal, 26)
          .padding(.top, 4)
          .padding(.bottom, 24)
          .frame(maxWidth: 600)
          .frame(maxWidth: .infinity)
        }

        OnboardingNavigationBar(step: step, goBack: goBack, goNext: goNext)
      }
    }
    .tint(palette.accent.color)
    .animation(.easeInOut(duration: 0.2), value: step)
  }

  private func goBack() {
    if let previous = step.previous {
      step = previous
    }
  }

  private func goNext() {
    if let next = step.next {
      step = next
    } else {
      onboarding.complete()
    }
  }

  private func skip() {
    onboarding.complete()
  }

  private var palette: GrimoraPalette {
    GrimoraPalette(colorScheme: colorScheme)
  }
}

#Preview {
  OnboardingTutorialView(onboarding: GrimoraOnboardingModel())
}
