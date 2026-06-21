import SwiftUI

struct EngineRootView: View {
  let model: EngineDashboardModel

  @State private var selection: SidebarItem? = .status

  /// Sidebar sections. Status and History ship now; later phases (configuration, data health,
  /// AI tagging) can be added here without disturbing existing screens.
  enum SidebarItem: String, CaseIterable, Identifiable {
    case status = "Status"
    case history = "History"

    var id: String { rawValue }

    var symbol: String {
      switch self {
      case .status: "gauge.with.dots.needle.67percent"
      case .history: "clock.arrow.circlepath"
      }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(SidebarItem.allCases, selection: $selection) { item in
        Label(item.rawValue, systemImage: item.symbol).tag(item)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
      .navigationTitle("Grimora Engine")
    } detail: {
      switch selection ?? .status {
      case .status:
        StatusView(model: model)
      case .history:
        HistoryView(model: model)
      }
    }
    .task {
      await model.startPolling()
    }
  }
}
