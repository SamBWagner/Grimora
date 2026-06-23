import SwiftUI

/// Quiz step: a short list of multiple-choice questions over the sample set, each
/// answered independently with immediate checked feedback. Reinforces the
/// operators taught earlier; entirely self-contained and skippable.
struct OnboardingQuizStepView: View {
  let questions: [GrimoraOnboardingQuizQuestion]
  var palette: GrimoraPalette

  var body: some View {
    VStack(spacing: 14) {
      ForEach(questions) { question in
        OnboardingQuizQuestionCard(question: question, palette: palette)
      }
    }
    .accessibilityIdentifier("onboarding-quiz")
  }
}

/// One quiz question with its own answer state.
private struct OnboardingQuizQuestionCard: View {
  let question: GrimoraOnboardingQuizQuestion
  var palette: GrimoraPalette

  @State private var selectedToken: String?

  private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

  private var isAnswered: Bool { selectedToken != nil }
  private var isCorrect: Bool { selectedToken == question.answerToken }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(question.prompt)
        .font(.callout.weight(.semibold))
        .foregroundStyle(palette.primaryText.color)
        .fixedSize(horizontal: false, vertical: true)

      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(question.choices) { choice in
          choiceButton(choice)
        }
      }

      if isAnswered {
        feedback
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(palette.hairline.color, lineWidth: 1)
    }
    .animation(.easeInOut(duration: 0.18), value: selectedToken)
    .accessibilityIdentifier("onboarding-quiz-question-\(question.id)")
  }

  private func choiceButton(_ choice: GrimoraOnboardingOperator) -> some View {
    Button {
      if !isAnswered {
        selectedToken = choice.token
      }
    } label: {
      VStack(spacing: 3) {
        Text(choice.title)
          .font(.caption.weight(.semibold))
        Text(choice.token)
          .font(.caption2.monospaced())
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .padding(.horizontal, 6)
      .background(background(for: choice), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(stroke(for: choice), lineWidth: 1)
      }
      .foregroundStyle(foreground(for: choice))
    }
    .buttonStyle(.plain)
    .disabled(isAnswered)
    .accessibilityLabel(accessibilityLabel(for: choice))
    .accessibilityIdentifier("onboarding-quiz-choice-\(question.id)-\(choice.id)")
  }

  /// Names the choice and, once answered, its outcome — so the result is legible
  /// without relying on colour.
  private func accessibilityLabel(for choice: GrimoraOnboardingOperator) -> String {
    let base = "\(choice.title), \(choice.token)"
    switch state(for: choice) {
    case .correct: return "\(base), correct answer"
    case .wrong: return "\(base), your answer, incorrect"
    case .idle, .dimmed: return base
    }
  }

  private var feedback: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(isCorrect ? .green : .orange)
        .accessibilityHidden(true)

      Text(isCorrect ? question.explanation : "Not quite. \(question.explanation)")
        .font(.caption)
        .foregroundStyle(palette.secondaryText.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityIdentifier("onboarding-quiz-feedback-\(question.id)")
  }

  // MARK: Choice styling — neutral until answered, then green for the correct
  // choice and orange for a wrong pick.

  private func state(for choice: GrimoraOnboardingOperator) -> ChoiceState {
    guard isAnswered else { return .idle }
    if question.isCorrect(choice) { return .correct }
    if choice.token == selectedToken { return .wrong }
    return .dimmed
  }

  private func background(for choice: GrimoraOnboardingOperator) -> Color {
    switch state(for: choice) {
    case .idle: palette.hairline.color.opacity(0.18)
    case .correct: Color.green.opacity(0.18)
    case .wrong: Color.orange.opacity(0.18)
    case .dimmed: palette.hairline.color.opacity(0.10)
    }
  }

  private func stroke(for choice: GrimoraOnboardingOperator) -> Color {
    switch state(for: choice) {
    case .idle: palette.hairline.color
    case .correct: .green
    case .wrong: .orange
    case .dimmed: palette.hairline.color.opacity(0.6)
    }
  }

  private func foreground(for choice: GrimoraOnboardingOperator) -> Color {
    switch state(for: choice) {
    case .idle: palette.primaryText.color
    case .correct: .green
    case .wrong: .orange
    case .dimmed: palette.secondaryText.color
    }
  }

  private enum ChoiceState {
    case idle, correct, wrong, dimmed
  }
}
