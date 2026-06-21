import AppKit
import GrimoraEngineKit
import SwiftUI

struct StatusView: View {
  let model: EngineDashboardModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        activityCard
        if let message = model.runErrorMessage {
          errorBanner(message)
        }
        if let build = model.localBuild {
          localBuildSection(build)
        }
        scheduleSection
        lastRunSection
      }
      .padding(24)
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Status")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await model.buildAndPublish(force: true) }
        } label: {
          Label("Force run", systemImage: "arrow.clockwise")
        }
        .disabled(model.isBusy)
        .help("Rebuild and publish even if the sources are unchanged")
      }
    }
  }

  // MARK: - Activity

  private var activityCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top) {
          statusHeadline
          Spacer()
          checkForUpdatesButton
        }
        checkResultDetail
        if case .running(let progress) = model.activity {
          runningContent(progress)
        }
        Divider()
        pipelineActions
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  /// Current state line: a spinner while running, otherwise idle + last-run summary.
  @ViewBuilder
  private var statusHeadline: some View {
    switch model.activity {
    case .running:
      Label {
        Text("Running…").font(.title3.weight(.semibold))
      } icon: {
        ProgressView().controlSize(.small)
      }
    case .idle:
      VStack(alignment: .leading, spacing: 6) {
        Label {
          Text("Idle").font(.title3.weight(.semibold))
        } icon: {
          Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
        }
        if let last = model.history.first {
          HStack(spacing: 6) {
            Image(systemName: last.outcome.symbol).foregroundStyle(last.outcome.tint)
            Text("Last run \(EngineFormat.relative(last.startedAt)) — \(last.outcome.label)")
              .foregroundStyle(.secondary)
          }
        } else {
          Text("No runs recorded yet").foregroundStyle(.secondary)
        }
      }
    }
  }

  /// Read-only source probe — sits apart from the build/publish actions because it changes nothing.
  private var checkForUpdatesButton: some View {
    Button {
      Task { await model.checkForUpdates() }
    } label: {
      Label(
        model.isChecking ? "Checking…" : "Check for Updates",
        systemImage: "arrow.triangle.2.circlepath"
      )
    }
    .controlSize(.small)
    .disabled(model.isChecking)
    .help("Ping Scryfall and MTGJSON to see if their data changed since the last build")
  }

  /// The build/publish pipeline. Prominence is on the safe local action; publishing to the live
  /// catalog is a deliberate secondary choice.
  private var pipelineActions: some View {
    HStack(spacing: 12) {
      Button {
        Task { await model.build(force: false) }
      } label: {
        Label("Download & Build", systemImage: "arrow.down.circle.fill")
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.isBusy)
      .help("Fetch the latest source data and build the catalog locally — nothing is uploaded")

      Button {
        Task { await model.publish() }
      } label: {
        Label("Publish", systemImage: "square.and.arrow.up")
      }
      .disabled(!model.canPublish)
      .help("Upload the local build to the live catalog")

      Spacer()

      Button {
        Task { await model.buildAndPublish(force: false) }
      } label: {
        Label("Build & Publish", systemImage: "arrow.up.circle")
      }
      .disabled(model.isBusy)
      .help("Build locally and upload to the live catalog in one step")
    }
    .controlSize(.large)
  }

  private enum StepState {
    case done, active, pending
  }

  private func runningContent(_ progress: EngineRunProgress) -> some View {
    let steps = RunStep.steps(for: model.activeOperation ?? .run)
    let current = RunStep.current(for: progress)
    return VStack(alignment: .leading, spacing: 10) {
      ForEach(steps) { step in
        stepRow(step, current: current, progress: progress)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func stepRow(_ step: RunStep, current: RunStep, progress: EngineRunProgress) -> some View {
    let state = stepState(step, current: current)
    HStack(alignment: .top, spacing: 10) {
      stepIcon(state)
        .frame(width: 18, height: 18)
      VStack(alignment: .leading, spacing: 4) {
        Text(step.title)
          .fontWeight(state == .active ? .semibold : .regular)
          .foregroundStyle(state == .pending ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        if state == .active {
          activeStepDetail(step, progress: progress)
        }
      }
      Spacer()
    }
  }

  @ViewBuilder
  private func stepIcon(_ state: StepState) -> some View {
    switch state {
    case .done:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .active:
      ProgressView().controlSize(.small)
    case .pending:
      Image(systemName: "circle").foregroundStyle(.tertiary)
    }
  }

  @ViewBuilder
  private func activeStepDetail(_ step: RunStep, progress: EngineRunProgress) -> some View {
    if let detail = progress.detail {
      Text(detail).font(.caption).foregroundStyle(.secondary)
    }
    if let fraction = progress.fractionCompleted {
      ProgressView(value: fraction)
        .controlSize(.small)
        .frame(maxWidth: 320)
      Text(progressLabel(step, progress: progress, fraction: fraction))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func stepState(_ step: RunStep, current: RunStep) -> StepState {
    if step.rawValue < current.rawValue { return .done }
    if step == current { return .active }
    return .pending
  }

  private func progressLabel(_ step: RunStep, progress: EngineRunProgress, fraction: Double) -> String {
    let percent = "\(Int(fraction * 100))%"
    switch step {
    case .downloadingSources, .ingestingCards, .importingPrices:
      if let total = progress.total {
        return "\(EngineFormat.bytes(progress.completed)) / \(EngineFormat.bytes(total)) · \(percent)"
      }
      return percent
    default:
      return percent
    }
  }

  @ViewBuilder
  private var checkResultDetail: some View {
    if !model.isChecking, let result = model.lastCheck {
      VStack(alignment: .leading, spacing: 8) {
        sourceStatusRow(
          title: "Scryfall card data",
          changed: result.check.scryfallChanged,
          current: EngineFormat.scryfallVersion(result.check.current),
          previous: result.check.lastBuilt.map(EngineFormat.scryfallVersion)
        )
        sourceStatusRow(
          title: "MTGJSON pricing data",
          changed: result.check.mtgjsonChanged,
          current: EngineFormat.mtgjsonVersion(result.check.current),
          previous: result.check.lastBuilt.map(EngineFormat.mtgjsonVersion)
        )
        Text("Checked \(EngineFormat.relative(result.checkedAt))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.top, 2)
    }
  }

  private func sourceStatusRow(
    title: String,
    changed: Bool,
    current: String,
    previous: String?
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: changed ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.circle.fill")
        .foregroundStyle(changed ? .orange : .green)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(title).fontWeight(.medium)
          Text(changed ? "Update available" : "Up to date")
            .foregroundStyle(changed ? .orange : .secondary)
        }
        if changed, let previous, previous != current {
          Text("\(previous) → \(current)")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        } else {
          Text(current)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.callout)
  }

  private func errorBanner(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .foregroundStyle(.red)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Schedule

  private var scheduleSection: some View {
    GroupBox("Schedule") {
      VStack(spacing: 0) {
        InfoRow(label: "Next run") {
          if let next = model.nextScheduledRun {
            VStack(alignment: .trailing, spacing: 2) {
              Text(EngineFormat.relative(next)).fontWeight(.medium)
              Text(EngineFormat.absolute(next)).font(.caption).foregroundStyle(.secondary)
            }
          } else {
            Text("—").foregroundStyle(.secondary)
          }
        }
        Divider()
        InfoRow(label: "Cadence") {
          Text(EngineFormat.scheduleSummary(model.schedule)).foregroundStyle(.secondary)
        }
      }
      .padding(4)
    }
  }

  // MARK: - Local build

  private func localBuildSection(_ build: LocalBuildInfo) -> some View {
    GroupBox("Local build") {
      VStack(spacing: 0) {
        InfoRow(label: "Version") {
          HStack(spacing: 8) {
            Text(build.version).font(.callout.monospaced()).foregroundStyle(.secondary)
            if build.isPublished {
              Label("Published", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
              Label("Not published", systemImage: "tray.fill").foregroundStyle(.orange)
            }
          }
          .labelStyle(.titleAndIcon)
          .font(.callout)
        }
        Divider()
        InfoRow(label: "Database") {
          Text(build.databaseURL.path)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Divider()
        HStack {
          Spacer()
          Button {
            NSWorkspace.shared.activateFileViewerSelecting([build.databaseURL])
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
          }
        }
        .padding(.vertical, 8)
      }
      .padding(4)
    }
  }

  // MARK: - Last run

  private var lastRunSection: some View {
    GroupBox("Last run") {
      VStack(spacing: 0) {
        if let last = model.history.first {
          InfoRow(label: "When") {
            Text(EngineFormat.absolute(last.startedAt)).foregroundStyle(.secondary)
          }
          Divider()
          InfoRow(label: "Outcome") {
            Label(last.outcome.label, systemImage: last.outcome.symbol)
              .foregroundStyle(last.outcome.tint)
          }
          if let version = last.publishedVersion {
            Divider()
            InfoRow(label: "Published version") {
              Text(version).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
          }
          if let counts = last.counts {
            Divider()
            InfoRow(label: "Cards") {
              Text(counts.cards.formatted()).foregroundStyle(.secondary)
            }
            Divider()
            InfoRow(label: "Price series") {
              Text(counts.priceSeries.formatted()).foregroundStyle(.secondary)
            }
          }
          if let error = last.error {
            Divider()
            InfoRow(label: "Error") {
              Text(error).foregroundStyle(.red).multilineTextAlignment(.trailing)
            }
          }
        } else {
          Text("No runs recorded yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
      }
      .padding(4)
    }
  }
}

/// A label/value row used inside the grouped status cards.
private struct InfoRow<Content: View>: View {
  let label: String
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
      Spacer(minLength: 16)
      content
    }
    .padding(.vertical, 8)
  }
}
