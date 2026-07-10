import SwiftUI

#if os(macOS)
/// Top-level "Card" menu exposing the foil toggle. It has no key equivalent on purpose — the
/// "F" shortcut is served by the hover-aware key monitor in `SplitRootView`, which can defer to
/// focused text fields (a menu key equivalent would steal "F" from the search field). The item
/// stays disabled unless there's a target (a hovered collection card or the detail-pane card),
/// so it's inert while browsing search results.
public struct GrimoraFoilCommands: Commands {
    @FocusedValue(\.appModel) private var model: GrimoraAppModel?

    public init() {}

    public var body: some Commands {
        CommandMenu("Card") {
            Button("Toggle Foil") {
                model?.performFoilToggleCommand()
            }
            .disabled(model?.canToggleFoilForActiveTarget != true)
            .accessibilityIdentifier("toggle-foil-command")
        }
    }
}
#endif
