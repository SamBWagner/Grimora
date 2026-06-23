import SwiftUI

/// First-run walkthrough container.
///
/// Presents the skippable, interactive tour: a sequence of
/// ``GrimoraOnboardingWalkthroughStep`` pages teaching operators, searching,
/// lists, and favourites with the curated sample set. Skip (always available) and
/// finishing both mark onboarding complete via ``GrimoraOnboardingModel``.
struct OnboardingTutorialView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var onboarding: GrimoraOnboardingModel

  @State private var step: GrimoraOnboardingWalkthroughStep = .welcome

  private var steps: [GrimoraOnboardingWalkthroughStep] {
    GrimoraOnboardingWalkthroughStep.allCases
  }

  var body: some View {
    ZStack {
      GrimoraAppBackground(palette: palette)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            stepHeader
            stepContent
          }
          .padding(.horizontal, 26)
          .padding(.top, 4)
          .padding(.bottom, 24)
          .frame(maxWidth: 600)
          .frame(maxWidth: .infinity)
        }

        navigationBar
      }
    }
    .tint(palette.accent.color)
    .animation(.easeInOut(duration: 0.2), value: step)
    .accessibilityIdentifier("onboarding-tutorial")
  }

  private var topBar: some View {
    HStack {
      progressDots
      Spacer()
      Button("Skip", action: skip)
        .font(.callout.weight(.medium))
        .buttonStyle(.borderless)
        .accessibilityIdentifier("onboarding-skip-button")
    }
    .padding(.horizontal, 22)
    .padding(.top, 16)
    .padding(.bottom, 8)
  }

  private var progressDots: some View {
    HStack(spacing: 6) {
      ForEach(steps) { item in
        Circle()
          .fill(item == step ? palette.accent.color : palette.secondaryText.color.opacity(0.3))
          .frame(width: 7, height: 7)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Step \(step.index + 1) of \(steps.count)")
    .accessibilityIdentifier("onboarding-progress")
  }

  private var stepHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      if step == .welcome {
        GrimoraLogoView(size: 64)
          .shadow(color: palette.shadow.color, radius: 14, x: 0, y: 8)
          .padding(.bottom, 4)
      }

      Text(step.title)
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.primaryText.color)

      Text(step.summary)
        .font(.callout)
        .foregroundStyle(palette.secondaryText.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .welcome:
      OnboardingWelcomeStepView(cards: onboarding.sampleCards, palette: palette)
    case .operators:
      OnboardingOperatorsStepView(
        operators: GrimoraOnboardingOperatorCatalog.cheatsheet,
        palette: palette
      )
    case .search:
      OnboardingOperatorPlaygroundView(
        cards: onboarding.sampleCards,
        operators: GrimoraOnboardingOperatorCatalog.playground,
        palette: palette
      )
    case .quiz:
      OnboardingQuizStepView(
        questions: GrimoraOnboardingQuizCatalog.questions,
        palette: palette
      )
    case .lists:
      OnboardingListsStepView(
        cards: Array(onboarding.sampleCards.prefix(4)),
        palette: palette
      )
    case .favourites:
      OnboardingFavouritesStepView(
        cards: Array(onboarding.sampleCards.prefix(4)),
        palette: palette
      )
    case .finish:
      EmptyView()
    }
  }

  private var navigationBar: some View {
    HStack(spacing: 12) {
      if !step.isFirst {
        Button("Back", action: goBack)
          .buttonStyle(.bordered)
          .controlSize(.large)
          .accessibilityIdentifier("onboarding-back-button")
      }

      Button(step.isLast ? "Start Exploring" : "Next", action: goNext)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("onboarding-next-button")
    }
    .padding(.horizontal, 26)
    .padding(.vertical, 16)
    .frame(maxWidth: 600)
    .frame(maxWidth: .infinity)
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
