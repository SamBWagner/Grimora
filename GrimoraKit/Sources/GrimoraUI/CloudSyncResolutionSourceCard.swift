import GrimoraCore
import SwiftUI

struct CloudSyncResolutionSourceCard: View {
  var snapshot: DeviceSyncSnapshot
  var isSelected: Bool
  var isEligibleSource: Bool
  var conflictingLists: [CardListRecord]
  var selectedConflictingListIDs: Set<CardListRecord.ID>
  var accent: Color
  var selectSource: () -> Void
  var toggleConflictingList: (CardListRecord.ID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: selectSource) {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: sourceIcon)
            .font(.title2)
            .foregroundStyle(isSelected ? accent : .secondary)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
              Text(snapshot.deviceName)
                .font(.headline)
                .foregroundStyle(.primary)
              Spacer(minLength: 12)
              if isSelected {
                Label("Starting point", systemImage: "checkmark.circle.fill")
                  .font(.subheadline)
                  .foregroundStyle(accent)
                  .labelStyle(.titleAndIcon)
              }
            }

            Text(
              "Updated \(snapshot.capturedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())"
            )
              .font(.subheadline)
              .foregroundStyle(.secondary)

            Text(countSummary)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .contentShape(.rect)
        .frame(minHeight: 64)
      }
      .buttonStyle(.plain)
      .disabled(!isEligibleSource)
      .accessibilityLabel("\(snapshot.deviceName), \(updatedSummary), \(countSummary)")
      .accessibilityValue(isSelected ? "Selected as starting point" : "Not selected")
      .accessibilityHint(
        isEligibleSource
          ? "Selects this data as the starting point."
          : "This source contains internal conflicts and cannot be the starting point."
      )

      Divider()
        .padding(.vertical, 12)

      Label(
        isSelected ? "All lists included" : "All non-conflicting lists included",
        systemImage: "checkmark.seal"
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)

      if !isSelected, !conflictingLists.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Also keep from this source")
            .font(.subheadline)
            .bold()

          ForEach(conflictingLists) { list in
            Button {
              toggleConflictingList(list.id)
            } label: {
              HStack {
                Image(
                  systemName: selectedConflictingListIDs.contains(list.id)
                    ? "checkmark.square.fill"
                    : "square"
                )
                .foregroundStyle(
                  selectedConflictingListIDs.contains(list.id) ? accent : .secondary
                )
                Text(list.name)
                  .foregroundStyle(.primary)
                Spacer()
                Text(list.entryCount == 1 ? "1 card" : "\(list.entryCount) cards")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .contentShape(.rect)
              .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keep \(list.name)")
            .accessibilityValue(
              selectedConflictingListIDs.contains(list.id) ? "Included" : "Not included"
            )
          }
        }
        .padding(.top, 14)
      }
    }
    .padding(18)
    .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(
          isSelected ? accent : Color.secondary.opacity(0.22),
          lineWidth: isSelected ? 2 : 1
        )
    }
    .opacity(isEligibleSource ? 1 : 0.72)
  }

  private var sourceIcon: String {
    snapshot.id == CloudSyncEntityCodec.entitySnapshotID
      ? "icloud.fill"
      : "laptopcomputer.and.iphone"
  }

  private var updatedSummary: String {
    "updated \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))"
  }

  private var countSummary: String {
    let listNoun = snapshot.listCount == 1 ? "list" : "lists"
    let cardNoun = snapshot.entryCount == 1 ? "card" : "cards"
    return "\(snapshot.listCount) \(listNoun) • \(snapshot.entryCount) \(cardNoun)"
  }
}
