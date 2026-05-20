#if os(macOS)
import GrimoraCore
import SwiftUI
import AppKit

struct SearchFocusDismissalBridge: NSViewRepresentable {
    @Binding var isFocused: Bool
    var onDismiss: () -> Void = {}

    func makeNSView(context: Context) -> SearchFocusDismissalView {
        let view = SearchFocusDismissalView()
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ view: SearchFocusDismissalView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = view
        context.coordinator.setMonitoring(isFocused)
    }

    static func dismantleNSView(_ nsView: SearchFocusDismissalView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: @unchecked Sendable {
        var parent: SearchFocusDismissalBridge
        weak var hostView: SearchFocusDismissalView?
        private var monitor: Any?

        init(parent: SearchFocusDismissalBridge) {
            self.parent = parent
        }

        func setMonitoring(_ isActive: Bool) {
            if isActive {
                startMonitoringIfNeeded()
            } else {
                stopMonitoring()
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startMonitoringIfNeeded() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let windowNumber = event.windowNumber
                let locationX = event.locationInWindow.x
                let locationY = event.locationInWindow.y

                MainActor.assumeIsolated {
                    self?.handleMouseDown(
                        windowNumber: windowNumber,
                        location: NSPoint(x: locationX, y: locationY)
                    )
                }
                return event
            }
        }

        @MainActor
        private func handleMouseDown(windowNumber: Int, location: NSPoint) {
            guard let hostView,
                  let window = hostView.window,
                  window.windowNumber == windowNumber
            else {
                return
            }

            let point = hostView.convert(location, from: nil)
            guard !hostView.bounds.contains(point) else {
                return
            }

            window.makeFirstResponder(nil)
            parent.isFocused = false
            parent.onDismiss()
        }
    }
}

final class SearchFocusDismissalView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif
