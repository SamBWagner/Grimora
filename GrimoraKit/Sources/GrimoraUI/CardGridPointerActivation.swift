import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct CardGridPointerModifiers: Equatable {
    var containsCommand = false
    var containsShift = false

    #if os(macOS)
    init(_ flags: NSEvent.ModifierFlags) {
        containsCommand = flags.contains(.command)
        containsShift = flags.contains(.shift)
    }
    #elseif os(iOS) || os(visionOS)
    init(_ flags: UIKeyModifierFlags) {
        containsCommand = flags.contains(.command)
        containsShift = flags.contains(.shift)
    }
    #endif

    init(containsCommand: Bool = false, containsShift: Bool = false) {
        self.containsCommand = containsCommand
        self.containsShift = containsShift
    }
}

struct CardGridPointerDragConfiguration {
    var payload: String
    var itemCount: Int
}

extension CardGridSelectionInteraction {
    init(pointerModifiers: CardGridPointerModifiers) {
        if pointerModifiers.containsShift {
            self = .range
        } else if pointerModifiers.containsCommand {
            self = .toggle
        } else {
            self = .replace
        }
    }
}

extension View {
    func cardGridPointerActivation(
        onClick: @escaping (CardGridPointerModifiers) -> Void,
        onDoubleClick: @escaping () -> Void,
        onKeyboardActivate: (() -> Void)? = nil,
        onTouch: (() -> Void)? = nil,
        dragConfiguration: CardGridPointerDragConfiguration? = nil,
        ignoredBottomTrailingSize: CGSize? = nil
    ) -> some View {
        modifier(
            CardGridPointerActivationModifier(
                onClick: onClick,
                onDoubleClick: onDoubleClick,
                onKeyboardActivate: onKeyboardActivate,
                onTouch: onTouch,
                dragConfiguration: dragConfiguration,
                ignoredBottomTrailingSize: ignoredBottomTrailingSize
            )
        )
    }
}

private struct CardGridPointerActivationModifier: ViewModifier {
    var onClick: (CardGridPointerModifiers) -> Void
    var onDoubleClick: () -> Void
    var onKeyboardActivate: (() -> Void)?
    var onTouch: (() -> Void)?
    var dragConfiguration: CardGridPointerDragConfiguration?
    var ignoredBottomTrailingSize: CGSize?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .overlay {
                CardGridPointerActivationBridge(
                    onClick: onClick,
                    onDoubleClick: onDoubleClick,
                    onKeyboardActivate: onKeyboardActivate,
                    dragConfiguration: dragConfiguration,
                    ignoredBottomTrailingSize: ignoredBottomTrailingSize
                )
                .accessibilityHidden(true)
            }
        #elseif os(iOS) || os(visionOS)
        content
            .modifier(
                CardGridTouchActivationModifier(
                    onTouch: onTouch,
                    ignoredBottomTrailingSize: ignoredBottomTrailingSize
                )
            )
            .overlay {
                CardGridPointerActivationBridge(
                    onClick: onClick,
                    onDoubleClick: onDoubleClick,
                    onKeyboardActivate: onKeyboardActivate,
                    ignoredBottomTrailingSize: ignoredBottomTrailingSize
                )
                .modifier(CardGridPointerDragSourceModifier(dragConfiguration: dragConfiguration))
                .accessibilityHidden(true)
            }
        #else
        content
            .onTapGesture {
                onTouch?()
            }
        #endif
    }
}

private struct CardGridTouchActivationModifier: ViewModifier {
    @State private var contentSize: CGSize = .zero

    var onTouch: (() -> Void)?
    var ignoredBottomTrailingSize: CGSize?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onTouch {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                contentSize = proxy.size
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                contentSize = newSize
                            }
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard !isIgnoredBottomTrailingPoint(value.location) else {
                                return
                            }

                            onTouch()
                        }
                )
        } else {
            content
        }
    }

    private func isIgnoredBottomTrailingPoint(_ point: CGPoint) -> Bool {
        guard let ignoredBottomTrailingSize else {
            return false
        }

        let ignoredRect = CGRect(
            x: max(0, contentSize.width - ignoredBottomTrailingSize.width),
            y: max(0, contentSize.height - ignoredBottomTrailingSize.height),
            width: ignoredBottomTrailingSize.width,
            height: ignoredBottomTrailingSize.height
        )
        return ignoredRect.contains(point)
    }
}

private struct CardGridPointerDragSourceModifier: ViewModifier {
    var dragConfiguration: CardGridPointerDragConfiguration?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        if let dragConfiguration {
            content.onDrag {
                NSItemProvider(object: dragConfiguration.payload as NSString)
            } preview: {
                CardGridPointerDragPreview(count: max(1, dragConfiguration.itemCount))
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct CardGridPointerDragPreview: View {
    var count: Int

    private let cardSize = CGSize(width: 96, height: 134)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if count > 1 {
                layer
                    .rotationEffect(.degrees(7))
                    .offset(x: 14, y: 10)
                layer
                    .rotationEffect(.degrees(3))
                    .offset(x: 7, y: 5)
            }

            layer

            if count > 1 {
                Text(count.formatted())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(minWidth: 28, minHeight: 24)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.tint.opacity(0.55), lineWidth: 1)
                    }
                    .offset(x: 12, y: -10)
            }
        }
        .frame(
            width: count > 1 ? cardSize.width + 22 : cardSize.width,
            height: count > 1 ? cardSize.height + 16 : cardSize.height
        )
        .accessibilityHidden(true)
    }

    private var layer: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.background.opacity(0.96))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.tint.opacity(0.14))
                    .padding(10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.72), lineWidth: 1)
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
    }
}

#if os(macOS)
private struct CardGridPointerActivationBridge: NSViewRepresentable {
    var onClick: (CardGridPointerModifiers) -> Void
    var onDoubleClick: () -> Void
    var onKeyboardActivate: (() -> Void)?
    var dragConfiguration: CardGridPointerDragConfiguration?
    var ignoredBottomTrailingSize: CGSize?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.ignoredBottomTrailingSize = ignoredBottomTrailingSize
    }

    final class Coordinator: NSObject {
        var parent: CardGridPointerActivationBridge

        init(parent: CardGridPointerActivationBridge) {
            self.parent = parent
        }

        @MainActor
        func handleClick(with event: NSEvent) {
            parent.onClick(CardGridPointerModifiers(event.modifierFlags))
        }

        @MainActor
        func handleDoubleClick() {
            parent.onDoubleClick()
        }

        @MainActor
        func handleKeyboardActivate() -> Bool {
            guard let onKeyboardActivate = parent.onKeyboardActivate else {
                return false
            }

            onKeyboardActivate()
            return true
        }
    }

    final class ClickView: NSView, NSDraggingSource {
        weak var coordinator: Coordinator?
        var ignoredBottomTrailingSize: CGSize?
        private var mouseDownEvent: NSEvent?
        private var hasStartedDrag = false

        override var acceptsFirstResponder: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if Self.currentEventRequestsContextMenu {
                return nil
            }

            if isIgnoredBottomTrailingPoint(point) {
                return nil
            }

            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            mouseDownEvent = event
            hasStartedDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !hasStartedDrag,
                  let mouseDownEvent,
                  let dragConfiguration = coordinator?.parent.dragConfiguration,
                  dragHasMoved(from: mouseDownEvent.locationInWindow, to: event.locationInWindow)
            else {
                return
            }

            hasStartedDrag = true
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(dragConfiguration.payload, forType: .string)
            pasteboardItem.setString(
                dragConfiguration.payload,
                forType: NSPasteboard.PasteboardType(UTType.plainText.identifier)
            )
            pasteboardItem.setString(
                dragConfiguration.payload,
                forType: NSPasteboard.PasteboardType(UTType.text.identifier)
            )

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let previewImage = Self.previewImage(count: max(1, dragConfiguration.itemCount))
            let origin = convert(event.locationInWindow, from: nil)
            let previewFrame = NSRect(
                x: origin.x - previewImage.size.width / 2,
                y: origin.y - previewImage.size.height / 2,
                width: previewImage.size.width,
                height: previewImage.size.height
            )
            draggingItem.setDraggingFrame(previewFrame, contents: previewImage)

            let session = beginDraggingSession(
                with: [draggingItem],
                event: event,
                source: self
            )
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownEvent = nil
                hasStartedDrag = false
            }

            guard !hasStartedDrag else {
                return
            }

            if event.clickCount >= 2 {
                coordinator?.handleDoubleClick()
            } else {
                coordinator?.handleClick(with: event)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard Self.isPlainSpace(event),
                  coordinator?.handleKeyboardActivate() == true
            else {
                super.keyDown(with: event)
                return
            }
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        private func dragHasMoved(from start: NSPoint, to current: NSPoint) -> Bool {
            let deltaX = current.x - start.x
            let deltaY = current.y - start.y
            return sqrt((deltaX * deltaX) + (deltaY * deltaY)) >= 4
        }

        private func isIgnoredBottomTrailingPoint(_ point: NSPoint) -> Bool {
            guard let ignoredBottomTrailingSize else {
                return false
            }

            let ignoredRect = NSRect(
                x: max(0, bounds.maxX - ignoredBottomTrailingSize.width),
                y: bounds.minY,
                width: ignoredBottomTrailingSize.width,
                height: ignoredBottomTrailingSize.height
            )
            return ignoredRect.contains(point)
        }

        private static var currentEventRequestsContextMenu: Bool {
            guard let event = NSApp.currentEvent else {
                return false
            }

            if event.type == .rightMouseDown || event.type == .rightMouseDragged || event.type == .rightMouseUp {
                return true
            }

            return event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        }

        private static func isPlainSpace(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            return flags.isEmpty && (event.keyCode == 49 || event.charactersIgnoringModifiers == " ")
        }

        private static func previewImage(count: Int) -> NSImage {
            let cardSize = NSSize(width: 96, height: 134)
            let imageSize = count > 1
                ? NSSize(width: cardSize.width + 22, height: cardSize.height + 18)
                : cardSize
            let image = NSImage(size: imageSize)
            image.lockFocus()
            defer { image.unlockFocus() }

            NSColor.clear.setFill()
            NSRect(origin: .zero, size: imageSize).fill()

            let offsets: [NSPoint] = count > 1
                ? [NSPoint(x: 16, y: 1), NSPoint(x: 8, y: 7), NSPoint(x: 0, y: 14)]
                : [NSPoint(x: 0, y: 0)]

            for offset in offsets {
                drawCardLayer(
                    in: NSRect(origin: offset, size: cardSize),
                    alpha: offset == offsets.last ? 0.98 : 0.92
                )
            }

            if count > 1 {
                drawCountBadge(count, imageSize: imageSize)
            }

            return image
        }

        private static func drawCardLayer(in rect: NSRect, alpha: CGFloat) {
            let cardPath = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(alpha).setFill()
            cardPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            let insetPath = NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10), xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            insetPath.fill()

            NSColor.separatorColor.withAlphaComponent(0.72).setStroke()
            cardPath.lineWidth = 1
            cardPath.stroke()
        }

        private static func drawCountBadge(_ count: Int, imageSize: NSSize) {
            let text = count.formatted() as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ]
            let textSize = text.size(withAttributes: attributes)
            let badgeSize = NSSize(
                width: max(28, textSize.width + 16),
                height: 24
            )
            let badgeRect = NSRect(
                x: imageSize.width - badgeSize.width - 1,
                y: imageSize.height - badgeSize.height - 1,
                width: badgeSize.width,
                height: badgeSize.height
            )
            let badgePath = NSBezierPath(ovalIn: badgeRect)
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            badgePath.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
            badgePath.lineWidth = 1
            badgePath.stroke()

            let textOrigin = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            text.draw(at: textOrigin, withAttributes: attributes)
        }
    }
}
#elseif os(iOS) || os(visionOS)
private struct CardGridPointerActivationBridge: UIViewRepresentable {
    var onClick: (CardGridPointerModifiers) -> Void
    var onDoubleClick: () -> Void
    var onKeyboardActivate: (() -> Void)?
    var ignoredBottomTrailingSize: CGSize?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ClickView {
        let view = ClickView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator

        let singleClick = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleClick(_:))
        )
        singleClick.numberOfTapsRequired = 1
        singleClick.buttonMaskRequired = .primary

        let doubleClick = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        doubleClick.numberOfTapsRequired = 2
        doubleClick.buttonMaskRequired = .primary

        singleClick.require(toFail: doubleClick)
        view.addGestureRecognizer(singleClick)
        view.addGestureRecognizer(doubleClick)
        return view
    }

    func updateUIView(_ uiView: ClickView, context: Context) {
        context.coordinator.parent = self
        uiView.coordinator = context.coordinator
        uiView.ignoredBottomTrailingSize = ignoredBottomTrailingSize
    }

    final class Coordinator: NSObject {
        var parent: CardGridPointerActivationBridge

        init(parent: CardGridPointerActivationBridge) {
            self.parent = parent
        }

        @MainActor
        @objc func handleSingleClick(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            parent.onClick(CardGridPointerModifiers(recognizer.modifierFlags))
        }

        @MainActor
        @objc func handleDoubleClick(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            parent.onDoubleClick()
        }
    }

    final class ClickView: UIView {
        weak var coordinator: Coordinator?
        var ignoredBottomTrailingSize: CGSize?

        override func hitTest(_ location: CGPoint, with event: UIEvent?) -> UIView? {
            guard let event,
                  event.buttonMask.contains(.primary),
                  point(inside: location, with: event)
            else {
                return nil
            }

            return self
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard !isIgnoredBottomTrailingPoint(point) else {
                return false
            }

            return super.point(inside: point, with: event)
        }

        private func isIgnoredBottomTrailingPoint(_ point: CGPoint) -> Bool {
            guard let ignoredBottomTrailingSize else {
                return false
            }

            let ignoredRect = CGRect(
                x: max(0, bounds.maxX - ignoredBottomTrailingSize.width),
                y: max(0, bounds.maxY - ignoredBottomTrailingSize.height),
                width: ignoredBottomTrailingSize.width,
                height: ignoredBottomTrailingSize.height
            )
            return ignoredRect.contains(point)
        }
    }
}
#endif
