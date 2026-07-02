import GrimoraCore
import GrimoraUI
import SwiftUI

/// Verdict pass on a finished scan: confirm the engine's answer, or label the
/// card it should have found.
struct ReviewSheet: View {
  let model: ScryHarnessModel
  let review: PendingReview

  @Environment(\.dismiss) private var dismiss
  @State private var showsLabeling = false
  @State private var notes = ""
  @State private var cropPreview: CGImage?

  private var resolution: ScryResolution? { review.capture.result?.resolution }

  var body: some View {
    NavigationStack {
      List {
        if let cropPreview {
          Section {
            Image(decorative: cropPreview, scale: 1)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 220)
              .frame(maxWidth: .infinity)
              .listRowBackground(Color.clear)
          }
        }

        switch resolution?.confidence {
        case .some(.auto):
          autoSections
        case .some(.ambiguous):
          ambiguousSections
        case .some(.none), nil:
          unresolvedSections
        }

        Section("Notes") {
          TextField("Optional note (lighting, sleeve glare…)", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle("Scan result")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Discard") { dismiss() }
        }
      }
    }
    .task { await loadCropPreview() }
  }

  // MARK: - Engine auto-accepted

  @ViewBuilder
  private var autoSections: some View {
    if let resolution, let card = resolution.card {
      Section("Engine says") {
        engineAnswerRow(card: card, resolution: resolution)
      }
      if showsLabeling {
        labelingSections(
          candidates: resolution.candidates.filter { $0.id != card.id },
          verdictForCandidatePick: .wrong
        )
      } else {
        Section {
          Button {
            save(verdict: .correct, groundTruth: .init(card), pickedFromCandidates: false)
          } label: {
            Label("Correct", systemImage: "checkmark.circle.fill")
              .font(.title3.bold())
              .frame(maxWidth: .infinity)
          }
          .tint(.green)
          Button {
            showsLabeling = true
          } label: {
            Label("Wrong", systemImage: "xmark.circle.fill")
              .font(.title3.bold())
              .frame(maxWidth: .infinity)
          }
          .tint(.red)
        }
      }
    }
  }

  // MARK: - Engine ambiguous

  @ViewBuilder
  private var ambiguousSections: some View {
    if let resolution {
      Section("Engine was unsure — tap the printing you scanned") {
        ForEach(resolution.candidates, id: \.id) { candidate in
          Button {
            save(verdict: .correct, groundTruth: .init(candidate), pickedFromCandidates: true)
          } label: {
            cardRow(candidate)
          }
        }
      }
      Section {
        if showsLabeling {
          searchSection
        } else {
          Button("None of these — search for the right card") {
            showsLabeling = true
          }
        }
        skipRow
      }
    }
  }

  // MARK: - Nothing recognized

  @ViewBuilder
  private var unresolvedSections: some View {
    Section {
      Label(
        review.capture.result == nil ? "No card locked" : "Card found, but not resolved",
        systemImage: "questionmark.diamond"
      )
      .foregroundStyle(.secondary)
    }
    Section("Label the card it should have found") {
      searchSection
      skipRow
    }
  }

  // MARK: - Pieces

  /// After "Wrong": remaining candidates first (cheap taps), then search.
  @ViewBuilder
  private func labelingSections(
    candidates: [CardRecord],
    verdictForCandidatePick: CaptureRecord.Verdict
  ) -> some View {
    if !candidates.isEmpty {
      Section("Was it one of the other candidates?") {
        ForEach(candidates, id: \.id) { candidate in
          Button {
            save(
              verdict: verdictForCandidatePick,
              groundTruth: .init(candidate),
              pickedFromCandidates: false
            )
          } label: {
            cardRow(candidate)
          }
        }
      }
    }
    Section("Search for the right card") {
      searchSection
      skipRow
    }
  }

  private var searchSection: some View {
    CardPickerView(model: model) { card in
      save(verdict: .wrong, groundTruth: .init(card), pickedFromCandidates: false)
    }
  }

  private var skipRow: some View {
    Button("Save unlabeled (label later on the Mac)") {
      save(verdict: .skipped, groundTruth: nil, pickedFromCandidates: false)
    }
    .foregroundStyle(.secondary)
  }

  private func engineAnswerRow(card: CardRecord, resolution: ScryResolution) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(card.name)
        .font(.title2.bold())
      // Set + collector number decide the verdict: "correct" means the exact
      // printing, not just the right name.
      Text("\(card.setCode.uppercased()) · #\(card.collectorNumber) · \(card.setName)")
        .font(.headline)
        .foregroundStyle(.tint)
      HStack(spacing: 8) {
        badge(resolution.method.rawValue)
        badge(resolution.confidence.rawValue)
        if review.capture.source == .videoFrame {
          badge("video frame")
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func cardRow(_ card: CardRecord) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(card.name)
        .font(.body.weight(.medium))
      Text("\(card.setCode.uppercased()) · #\(card.collectorNumber) · \(card.setName)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func badge(_ text: String) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(.quaternary, in: Capsule())
  }

  private func save(
    verdict: CaptureRecord.Verdict,
    groundTruth: CaptureRecord.CardIdentity?,
    pickedFromCandidates: Bool
  ) {
    let capture = review.capture
    let notes = notes
    Task {
      await model.save(
        capture,
        verdict: verdict,
        groundTruth: groundTruth,
        pickedFromCandidates: pickedFromCandidates,
        notes: notes
      )
    }
    dismiss()
  }

  private func loadCropPreview() async {
    guard let result = review.capture.result, let rectified = result.rectified else { return }
    let orientation = result.orientation
    cropPreview = await Task.detached(priority: .utility) {
      ScryTextExtractor.makeUpright(rectified, orientation: orientation)
    }.value
  }
}

/// Plain-text catalog search returning specific printings; tapping a row hands
/// the picked card back.
struct CardPickerView: View {
  let model: ScryHarnessModel
  let onPick: (CardRecord) -> Void

  @State private var searchText = ""
  @State private var results: [CardRecord] = []

  var body: some View {
    TextField("Card name…", text: $searchText)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .onChange(of: searchText) { _, text in
        results = model.searchCards(text)
      }
    ForEach(results.prefix(25), id: \.id) { card in
      Button {
        onPick(card)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(card.name)
            .font(.body.weight(.medium))
          Text("\(card.setCode.uppercased()) · #\(card.collectorNumber) · \(card.setName)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
