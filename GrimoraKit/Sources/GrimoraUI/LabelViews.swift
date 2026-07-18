import GrimoraCore
import SwiftUI

/// A single colored label dot. The white ring + soft shadow keep it legible on any artwork, so pips
/// can sit directly on the card without a heavier chrome plate.
struct LabelSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    var color: LabelColor
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color.fillColor(for: colorScheme))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: max(0.5, size * 0.08)))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// A horizontal strip of label dots for a card tile — the bottom-left "pips". Shows up to
/// `maxVisible` dots and, when there are more, a compact `+N` so the row stays short; the full set
/// is available on hover (macOS tooltip) and in the detail pane.
struct LabelPipRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var labels: [CardLabelRecord]
    var maxVisible: Int = 3
    var pipSize: CGFloat = 9

    private var visible: [CardLabelRecord] { Array(labels.prefix(maxVisible)) }
    private var overflow: Int { max(0, labels.count - maxVisible) }

    var body: some View {
        if !labels.isEmpty {
            HStack(spacing: 3) {
                ForEach(visible) { label in
                    LabelSwatch(color: label.color, size: pipSize)
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.system(size: pipSize * 0.95, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, pipSize * 0.35)
                        .frame(minWidth: pipSize, minHeight: pipSize)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Labels: \(labels.map(\.name).joined(separator: ", "))")
            .help(labels.map(\.name).joined(separator: ", "))
        }
    }
}

/// The shared contents of a card's "Labels" menu — a toggle per applicable label (checkmark when
/// applied) plus "New Label…". Dropped into every card action surface (right-click / long-press
/// context menu, the tile "…" more-menu, and the list-row menus) so labeling is a first-class,
/// consistent action everywhere, not just the detail pane. Toggling writes straight through the
/// model; "New Label…" defers to the host's `onNewLabel` (which owns the editor sheet).
struct CardLabelMenuItems: View {
    @Environment(GrimoraAppModel.self) private var model
    var entry: CardCollectionEntryRecord
    /// The entries a toggle should touch (multi-select aware). Defaults to just this entry.
    var targetEntryIDs: [CardCollectionEntryRecord.ID]? = nil
    var onNewLabel: () -> Void

    var body: some View {
        let applicable = model.applicableLabels(forListID: entry.listID)
        ForEach(applicable) { label in
            Button {
                model.toggleLabel(label.id, forEntryIDs: targetEntryIDs ?? [entry.id])
            } label: {
                if entry.labelIDs.contains(label.id) {
                    Label(label.name, systemImage: "checkmark")
                } else {
                    Text(label.name)
                }
            }
            .accessibilityIdentifier("toggle-label-\(entry.id)-\(label.id)")
        }
        if !applicable.isEmpty {
            Divider()
        }
        Button(action: onNewLabel) {
            Label("New Label…", systemImage: "plus")
        }
        .accessibilityIdentifier("new-label-\(entry.id)")
    }
}

/// A swatch + name chip for a label, used in the detail pane, the manager, and pickers. When
/// `onRemove` is set it shows a remove affordance.
struct LabelChip: View {
    @Environment(\.colorScheme) private var colorScheme
    var label: CardLabelRecord
    var showsScopeHint: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 5) {
            LabelSwatch(color: label.color, size: 10)
            Text(label.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(palette.primaryText.color)
            if showsScopeHint, !label.isGlobal {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                    .foregroundStyle(palette.secondaryText.color)
                    .help("Only in this collection")
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(label.name)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.cardSurface.color, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.hairline.color, lineWidth: 1))
    }

    private var palette: GrimoraPalette { .cached(for: colorScheme) }
}
