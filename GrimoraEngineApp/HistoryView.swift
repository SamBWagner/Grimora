import GrimoraEngineKit
import SwiftUI

struct HistoryView: View {
  let model: EngineDashboardModel

  @State private var selection: EngineRunRecord.ID?

  var body: some View {
    Group {
      if model.history.isEmpty {
        ContentUnavailableView(
          "No runs yet",
          systemImage: "clock.badge.questionmark",
          description: Text("Completed builds will appear here.")
        )
      } else {
        Table(model.history, selection: $selection) {
          TableColumn("Started") { record in
            Text(EngineFormat.absolute(record.startedAt))
          }
          .width(min: 150, ideal: 170)

          TableColumn("Trigger") { record in
            Text(record.trigger.label)
          }
          .width(min: 70, ideal: 80)

          TableColumn("Operation") { record in
            Text(record.operation.label)
          }
          .width(min: 70, ideal: 80)

          TableColumn("Outcome") { record in
            Label(record.outcome.label, systemImage: record.outcome.symbol)
              .foregroundStyle(record.outcome.tint)
              .labelStyle(.titleAndIcon)
          }
          .width(min: 110, ideal: 120)

          TableColumn("Version") { record in
            Text(record.publishedVersion ?? "—")
              .font(.callout.monospaced())
              .foregroundStyle(.secondary)
          }
          .width(min: 140, ideal: 200)

          TableColumn("Duration") { record in
            Text(record.duration.map(EngineFormat.duration) ?? "—")
              .foregroundStyle(.secondary)
          }
          .width(min: 70, ideal: 80)
        }
      }
    }
    .navigationTitle("History")
    .navigationSubtitle("\(model.history.count) run\(model.history.count == 1 ? "" : "s")")
  }
}
