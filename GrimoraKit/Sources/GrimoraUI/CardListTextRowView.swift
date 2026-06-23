import Foundation
import GrimoraCore
import SwiftUI

struct CardListTextRowView: View {
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var selectionFeedbackTrigger = 0
    @State private var isNamingNewCategory = false

    var entry: CardListEntryRecord
    var card: CardRecord?
    var categories: [CardListCategoryRecord]
    var palette: GrimoraPalette
    var onOpen: () -> Void
    var onIncrementQuantity: () -> Void
    var onRemove: () -> Void
    var onRemoveCompletely: () -> Void
    var onEditQuantity: () -> Void
    var isSelectionEnabled: Bool
    var isSelectedInSelection: Bool
    var isActiveDetail: Bool = false
    var selectionAccessibilityIdentifier: String
    var showsSelectionIndicator: Bool
    var usesSelectionModeGestures: Bool
    var onSelectionInteraction: (CardGridSelectionInteraction) -> Void
    var onMoveToCategory: (CardListCategoryRecord.ID?) -> Void
    var onCreateCategory: ((String) -> Void)?
    var onMoveToZone: (CardListZone) -> Void
    var isMoveDestinationDisabled: (CardListCategoryRecord.ID?) -> Bool
    var dragPayload: String
    var dragItemCount: Int
    var isDragEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CardListTextRowLeadingIcon(
                showsSelectionIndicator: showsSelectionIndicator,
                isSelectedInSelection: isSelectedInSelection,
                palette: palette,
                selectionAccessibilityIdentifier: selectionAccessibilityIdentifier,
                isDragEnabled: isDragEnabled
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.quantity.formatted())
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.secondaryText.color)
                        .frame(minWidth: 22, alignment: .trailing)
                        .accessibilityLabel("Quantity \(entry.quantity.formatted())")

                    Text(primaryName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.primaryText.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            if let card, !card.manaCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ManaCostView(manaCost: card.manaCost, palette: palette)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("list-entry-mana-cost-\(entry.id)")
            }

            Menu {
                rowActions
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText.color)
            .help("Card Actions")
            .accessibilityLabel("Card Actions")
            .accessibilityIdentifier("list-entry-actions-\(entry.id)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            activateRow()
        }
        .contextMenu {
            rowActions
        }
        .modifier(
            CardGridDraggableModifier(
                payload: dragPayload,
                isEnabled: isDragEnabled,
                itemCount: max(1, dragItemCount)
            )
        )
        .grimoraSelectionFeedback(trigger: selectionFeedbackTrigger)
        .cardListNewCategoryPrompt(isPresented: $isNamingNewCategory) { name in
            onCreateCategory?(name)
        }
        .listRowBackground(CardListTextRowBackground(card: card, palette: palette, isActiveDetail: isActiveDetail))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("card-list-text-row-\(entry.id)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAction {
            activateRow()
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        Button {
            onOpen()
        } label: {
            Text("Open Details")
        }
        .disabled(card == nil)
        .accessibilityIdentifier("open-list-entry-\(entry.id)")

        Button {
            onEditQuantity()
        } label: {
            Text("Set Quantity")
        }
        .accessibilityIdentifier("set-quantity-\(entry.id)")

        Button {
            onIncrementQuantity()
        } label: {
            Text("Add One")
        }
        .accessibilityIdentifier("increase-list-entry-\(entry.id)")

        Button {
            onRemove()
        } label: {
            Text("Remove One")
        }
        .accessibilityIdentifier("remove-list-entry-\(entry.id)")

        Button(role: .destructive) {
            onRemoveCompletely()
        } label: {
            Text("Remove All")
        }
        .accessibilityIdentifier("remove-all-list-entry-\(entry.id)")

        moveCategoryMenu
        moveZoneMenu
    }

    @ViewBuilder
    private var moveCategoryMenu: some View {
        if onCreateCategory != nil || !categories.isEmpty || entry.categoryID != nil {
            Menu {
                if onCreateCategory != nil {
                    Button {
                        isNamingNewCategory = true
                    } label: {
                        Label("New Category…", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("move-list-entry-\(entry.id)-new-category")

                    Divider()
                }

                Button {
                    onMoveToCategory(nil)
                } label: {
                    GrimoraMenuSelectionLabel(
                        title: "Uncategorized",
                        isSelected: entry.categoryID == nil
                    )
                }
                .disabled(isMoveDestinationDisabled(nil))
                .accessibilityIdentifier("move-list-entry-\(entry.id)-category-uncategorized")

                if !categories.isEmpty {
                    Divider()
                }

                ForEach(categories) { category in
                    Button {
                        onMoveToCategory(category.id)
                    } label: {
                        GrimoraMenuSelectionLabel(
                            title: category.name,
                            isSelected: entry.categoryID == category.id
                        )
                    }
                    .disabled(isMoveDestinationDisabled(category.id))
                    .accessibilityIdentifier("move-list-entry-\(entry.id)-category-\(category.name)")
                }
            } label: {
                Text("Move to Category")
            }
        }
    }

    @ViewBuilder
    private var moveZoneMenu: some View {
        let zones = model.selectedList?.ruleset.allowedZones ?? CardListRuleset.none.allowedZones
        if zones.count > 1 {
            Menu {
                ForEach(zones) { zone in
                    Button {
                        onMoveToZone(zone)
                    } label: {
                        GrimoraMenuSelectionLabel(
                            title: zone.title,
                            isSelected: entry.zone == zone
                        )
                    }
                    .disabled(entry.zone == zone)
                    .accessibilityIdentifier("move-list-entry-\(entry.id)-zone-\(zone.rawValue)")
                }
            } label: {
                Text("Move to Zone")
            }
        }
    }

    private var primaryName: String {
        card?.name ?? entry.cardID
    }

    private var secondaryText: String {
        guard let card else {
            return "Unavailable Print - \(entry.cardID)"
        }

        let printText = [card.setCode.uppercased(), "#\(card.collectorNumber)"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let typeText = card.typeLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if typeText.isEmpty {
            return printText
        }
        if printText.isEmpty {
            return typeText
        }
        return "\(typeText) - \(printText)"
    }

    private var manaCostAccessibilityText: String {
        ManaCostSymbolParser.accessibilityText(for: card?.manaCost ?? "")
    }

    private var accessibilityLabel: String {
        "\(entry.quantity.formatted()) \(primaryName), \(secondaryText), mana cost \(manaCostAccessibilityText)"
    }

    private var accessibilityValue: String {
        [
            isSelectedInSelection ? "Selected" : nil,
            isActiveDetail ? "Showing Details" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func activateRow() {
        if usesSelectionModeGestures {
            selectRow()
        } else {
            onOpen()
        }
    }

    private func selectRow() {
        guard isSelectionEnabled else {
            return
        }

        selectionFeedbackTrigger += 1
        onSelectionInteraction(.replace)
    }
}

enum CardListTextRowColorIdentityStyle: Equatable {
    case colorless
    case mono(String)
    case pair(String, String)
    case gold

    init(card: CardRecord?) {
        guard let card, !Self.isDevoid(card) else {
            self = .colorless
            return
        }

        let symbols = Self.orderedColorIdentitySymbols(from: card.colorIdentity)

        switch symbols.count {
        case 0:
            self = .colorless
        case 1:
            self = .mono(symbols[0])
        case 2:
            self = .pair(symbols[0], symbols[1])
        default:
            self = .gold
        }
    }

    private static func orderedColorIdentitySymbols(from values: [String]) -> [String] {
        let unique = Set(values.map { $0.uppercased() })
        return ["W", "U", "B", "R", "G"].filter { unique.contains($0) }
    }

    private static func isDevoid(_ card: CardRecord) -> Bool {
        if card.keywords.contains(where: { $0.localizedCaseInsensitiveCompare("Devoid") == .orderedSame }) {
            return true
        }

        if card.oracleText.range(of: #"\bdevoid\b"#, options: [.caseInsensitive, .regularExpression]) != nil {
            return true
        }

        return card.faces.contains { face in
            face.oracleText.range(of: #"\bdevoid\b"#, options: [.caseInsensitive, .regularExpression]) != nil
        }
    }
}

struct CardListTextEmptyCategoryRow: View {
    var palette: GrimoraPalette

    var body: some View {
        Text("No Cards")
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText.color)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
            .accessibilityIdentifier("empty-list-category")
    }
}
