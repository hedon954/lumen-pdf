import AppKit
import SwiftUI

struct WindowOutsideClickMonitor: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutsideClick: onOutsideClick)
    }

    func makeNSView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: PassthroughView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ nsView: PassthroughView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        weak var view: NSView?
        var onOutsideClick: () -> Void
        private var monitor: Any?
        private var isCancelled = false

        init(onOutsideClick: @escaping () -> Void) {
            self.onOutsideClick = onOutsideClick
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            isCancelled = false
            // The click that opened this overlay is still in-flight. Wait until
            // the next turn so that same mouseDown cannot dismiss it.
            DispatchQueue.main.async { [weak self] in
                self?.installMonitor()
            }
        }

        func stopMonitoring() {
            isCancelled = true
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func installMonitor() {
            guard !isCancelled, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .magnify]
            ) { [weak self] event in
                guard let self, self.view?.window?.attachedSheet == nil else { return event }
                let clickedInside = if ReadingOverlayPanelID.isOverlay(event.window) {
                    true
                } else if let view = self.view, event.window === view.window {
                    view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                } else {
                    false
                }
                if !clickedInside {
                    self.onOutsideClick()
                }
                return event
            }
        }
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
