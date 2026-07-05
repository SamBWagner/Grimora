#if os(iOS)
import GrimoraCore
import SwiftUI

/// The change summary shown after a Commander re-scan. Accept applies the whole diff
/// (one undoable step); Discard throws it away. When nothing differs it shows a
/// friendly "no changes" state instead.
struct CommanderRescanSummarySheet: View {
  let deckName: String
  let diff: CommanderRescanDiff
  let onAccept: () -> Void
  let onDiscard: () -> Void

  var body: some View {
    NavigationStack {
      Group {
        if diff.isEmpty {
          emptyState
        } else {
          changeList
        }
      }
      .navigationTitle("Re-scan \(deckName)")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var changeList: some View {
    List {
      if !diff.additions.isEmpty {
        Section("Add \(diff.addedCopies)") {
          ForEach(diff.additions) { change in
            CommanderRescanChangeRow(change: change, symbol: "plus.circle.fill", tint: .green)
          }
        }
      }
      if !diff.removals.isEmpty {
        Section("Remove \(diff.removedCopies)") {
          ForEach(diff.removals) { change in
            CommanderRescanChangeRow(change: change, symbol: "minus.circle.fill", tint: .red)
          }
        }
      }
      if diff.unchangedCount > 0 {
        Section {
          Text("\(diff.unchangedCount) card\(diff.unchangedCount == 1 ? "" : "s") unchanged")
            .foregroundStyle(.secondary)
        }
      }
    }
    .safeAreaInset(edge: .bottom) { actionBar }
  }

  private var actionBar: some View {
    VStack(spacing: 10) {
      Button(action: onAccept) {
        Text("Accept Changes").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("accept-rescan-button")

      Button("Discard", role: .cancel, action: onDiscard)
        .accessibilityIdentifier("discard-rescan-button")
    }
    .padding()
    .background(.bar)
  }

  private var emptyState: some View {
    VStack(spacing: 20) {
      ContentUnavailableView {
        Label("No Changes", systemImage: "checkmark.circle")
      } description: {
        Text("Your scan matches \(deckName).")
      }
      Button("Close", action: onDiscard)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("close-rescan-button")
    }
  }
}

/// A single added/removed row: card thumbnail, name, printing, and the copy delta.
private struct CommanderRescanChangeRow: View {
  let change: CommanderRescanChange
  let symbol: String
  let tint: Color

  var body: some View {
    HStack(spacing: 12) {
      thumbnail
        .frame(width: 40, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 5))

      VStack(alignment: .leading, spacing: 2) {
        Text(change.card.name).font(.body)
        Text("\(change.card.setName) · \(change.card.setCode.uppercased()) \(change.card.collectorNumber)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Label("\(abs(change.delta))", systemImage: symbol)
        .labelStyle(.titleAndIcon)
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let path = change.card.normalImagePath ?? change.card.largeImagePath,
       FileManager.default.fileExists(atPath: path) {
      LocalCardImage(path: path, cornerRadius: 5, contentMode: .fill)
    } else {
      RoundedRectangle(cornerRadius: 5).fill(.quaternary)
    }
  }
}
#endif
