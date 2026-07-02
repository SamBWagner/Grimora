import GrimoraCore
import SwiftUI

/// Everything captured this session (and before): thumbnails, verdict badges,
/// swipe-to-delete, and tap-through for relabeling.
struct CaptureListView: View {
  let model: ScryHarnessModel

  @Environment(\.dismiss) private var dismiss
  @State private var selected: CaptureRecord?

  var body: some View {
    NavigationStack {
      List {
        ForEach(model.captures) { record in
          Button {
            selected = record
          } label: {
            row(record)
          }
          .buttonStyle(.plain)
        }
        .onDelete { offsets in
          for offset in offsets {
            model.delete(model.captures[offset])
          }
        }
      }
      .overlay {
        if model.captures.isEmpty {
          ContentUnavailableView(
            "No captures yet",
            systemImage: "camera.viewfinder",
            description: Text("Scans you confirm land here — and in Documents/Captures for Finder.")
          )
        }
      }
      .navigationTitle("Captures (\(model.captures.count))")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selected) { record in
        CaptureDetailView(model: model, record: record)
      }
    }
  }

  private func row(_ record: CaptureRecord) -> some View {
    HStack(spacing: 12) {
      thumbnail(record)
      VStack(alignment: .leading, spacing: 2) {
        Text(record.groundTruth?.name ?? "Unlabeled")
          .font(.body.weight(.medium))
        if let truth = record.groundTruth {
          Text("\(truth.setCode.uppercased()) · #\(truth.collectorNumber)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      verdictBadge(record)
    }
  }

  private func thumbnail(_ record: CaptureRecord) -> some View {
    Group {
      if let image = model.store.thumbnail(for: record.id, maxPixel: 120) {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 44, height: 60)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func verdictBadge(_ record: CaptureRecord) -> some View {
    let (label, color): (String, Color) = switch record.verdict {
    case .correct: record.pickedFromCandidates ? ("picked", .orange) : ("correct", .green)
    case .wrong: ("wrong", .red)
    case .skipped: ("unlabeled", .gray)
    }
    return Text(label)
      .font(.caption2.weight(.bold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(color.opacity(0.18), in: Capsule())
      .foregroundStyle(color)
  }
}

/// One capture: the saved crop, the engine's answer, and relabel/delete actions.
struct CaptureDetailView: View {
  let model: ScryHarnessModel
  @State var record: CaptureRecord

  @Environment(\.dismiss) private var dismiss
  @State private var showsSearch = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          if let image = model.store.thumbnail(for: record.id, maxPixel: 800) {
            Image(decorative: image, scale: 1)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 320)
              .frame(maxWidth: .infinity)
              .listRowBackground(Color.clear)
          }
        }

        Section("Label") {
          LabeledContent("Ground truth") {
            Text(record.groundTruth.map { "\($0.name) (\($0.setCode.uppercased()) #\($0.collectorNumber))" }
              ?? "—")
          }
          LabeledContent("Verdict") { Text(record.verdict.rawValue) }
          if let engine = record.engine {
            LabeledContent("Engine said") {
              Text(engine.card.map { "\($0.name) (\($0.setCode.uppercased()) #\($0.collectorNumber))" }
                ?? engine.confidence)
            }
            LabeledContent("Method") { Text(engine.method) }
          }
          LabeledContent("Capture") {
            Text("\(record.capture.source) · foil \(record.foil ? "yes" : "no") · \(record.background)")
          }
        }

        Section("Fix label") {
          if let engineCard = record.engine?.card, record.verdict != .correct {
            Button("Engine was right after all") {
              record.verdict = .correct
              record.groundTruth = engineCard
              record.needsLabel = false
              record.pickedFromCandidates = false
              model.update(record: record)
              dismiss()
            }
          }
          if showsSearch {
            CardPickerView(model: model) { card in
              record.groundTruth = .init(card)
              record.verdict = .wrong
              record.needsLabel = false
              record.pickedFromCandidates = false
              model.update(record: record)
              dismiss()
            }
          } else {
            Button("Pick a different card…") { showsSearch = true }
          }
        }

        Section {
          Button("Delete capture", role: .destructive) {
            model.delete(record)
            dismiss()
          }
        }
      }
      .navigationTitle(record.id)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
