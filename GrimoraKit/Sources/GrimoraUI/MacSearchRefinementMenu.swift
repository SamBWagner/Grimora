#if os(macOS)
import GrimoraCore
import SwiftUI
import AppKit

struct MacSearchRefinementMenu<MenuContent: View>: View {
    var title: String
    var systemImage: String?
    var accessibilityIdentifier: String
    var helpText: String
    var accessibilityValue: String?
    @ViewBuilder var menuContent: () -> MenuContent

    init(
        title: String,
        systemImage: String? = nil,
        accessibilityIdentifier: String,
        helpText: String,
        accessibilityValue: String? = nil,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.helpText = helpText
        self.accessibilityValue = accessibilityValue
        self.menuContent = menuContent
    }

    var body: some View {
        Menu {
            menuContent()
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
            } else {
                Text(title)
                    .lineLimit(1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? title)
        .help(helpText)
    }
}

struct MacSearchRefinementPopoverButton<PopoverContent: View>: View {
    var title: String
    var systemImage: String?
    var accessibilityIdentifier: String
    var helpText: String
    var accessibilityValue: String?
    @ViewBuilder var popoverContent: (_ dismiss: @escaping () -> Void) -> PopoverContent

    @State private var isPresented = false

    init(
        title: String,
        systemImage: String? = nil,
        accessibilityIdentifier: String,
        helpText: String,
        accessibilityValue: String? = nil,
        @ViewBuilder popoverContent: @escaping (_ dismiss: @escaping () -> Void) -> PopoverContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.helpText = helpText
        self.accessibilityValue = accessibilityValue
        self.popoverContent = popoverContent
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
            } else {
                Text(title)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? title)
        .help(helpText)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent {
                isPresented = false
            }
        }
    }
}
#endif
