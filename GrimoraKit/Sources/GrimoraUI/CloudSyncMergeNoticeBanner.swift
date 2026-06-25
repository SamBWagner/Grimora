import GrimoraCore
import SwiftUI

/// A non-blocking banner shown when an incoming iCloud change replaced local data. It
/// offers a one-tap Undo (restoring the pre-merge recovery snapshot) and a dismiss, so
/// the user is never interrupted by a modal during normal editing.
struct CloudSyncMergeNoticeBanner: View {
  let notice: CloudSyncMergeNotice
  let onUndo: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "arrow.triangle.2.circlepath.icloud")
        .imageScale(.large)
        .foregroundStyle(.secondary)
      Text(notice.message)
        .font(.subheadline.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button("Undo", action: onUndo)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityIdentifier("cloud-sync-merge-undo")
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .imageScale(.small)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(.separator)
    )
    .shadow(radius: 10, y: 4)
    .frame(maxWidth: 520)
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("cloud-sync-merge-notice")
  }
}
