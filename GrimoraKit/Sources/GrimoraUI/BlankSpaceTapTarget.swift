import SwiftUI

#if os(macOS)
import AppKit
#endif

struct BlankSpaceTapTarget: View {
    var action: () -> Void

    var body: some View {
        Color.black.opacity(0.0001)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            #if os(macOS)
            .background {
                MacBlankSpaceClickMonitor(action: action)
                    .accessibilityHidden(true)
            }
            #endif
    }
}

#if os(macOS)
private struct MacBlankSpaceClickMonitor: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        context.coordinator.hostView = view
        context.coordinator.startMonitoringIfNeeded()
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = view
        context.coordinator.startMonitoringIfNeeded()
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: @unchecked Sendable {
        var parent: MacBlankSpaceClickMonitor
        weak var hostView: MonitorView?
        private var monitor: Any?

        init(parent: MacBlankSpaceClickMonitor) {
            self.parent = parent
        }

        func startMonitoringIfNeeded() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let windowNumber = event.windowNumber
                let location = event.locationInWindow
                let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

                MainActor.assumeIsolated {
                    self?.handleMouseDown(
                        windowNumber: windowNumber,
                        location: location,
                        hasSelectionModifier: !flags.isEmpty
                    )
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor
        private func handleMouseDown(
            windowNumber: Int,
            location: NSPoint,
            hasSelectionModifier: Bool
        ) {
            guard !hasSelectionModifier,
                  let hostView,
                  let window = hostView.window,
                  window.windowNumber == windowNumber
            else {
                return
            }

            let point = hostView.convert(location, from: nil)
            guard hostView.bounds.contains(point),
                  let contentView = window.contentView
            else {
                return
            }

            let contentPoint = contentView.convert(location, from: nil)
            guard !Self.isInteractiveHit(contentView.hitTest(contentPoint)) else {
                return
            }

            parent.action()
        }

        @MainActor
        private static func isInteractiveHit(_ view: NSView?) -> Bool {
            var current = view
            while let view = current {
                if view is NSControl {
                    return true
                }

                let className = NSStringFromClass(type(of: view))
                if className.contains("ClickView") {
                    return true
                }

                current = view.superview
            }

            return false
        }
    }

    final class MonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
#endif
