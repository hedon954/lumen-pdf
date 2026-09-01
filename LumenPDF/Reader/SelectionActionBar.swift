import AppKit
import SwiftUI

enum ReaderRootCoordinateSpace {
    static let name = "LumenPDF.ReaderRoot"

    /// Convert a reader-root selection into the overlay GeometryReader's local
    /// space. The named root origin is not always the overlay's `(0, 0)`: the
    /// unified toolbar typically shifts the overlay down, so using root `Y`
    /// directly places the pointer a toolbar-height away from the highlight.
    static func localRect(
        _ rootRect: CGRect,
        overlayFrameInRoot: CGRect
    ) -> CGRect {
        rootRect.offsetBy(
            dx: -overlayFrameInRoot.minX,
            dy: -overlayFrameInRoot.minY
        )
    }
}

enum SelectionActionBarAction {
    case translate
    case explain
    case highlight
    case underline
    case addNote
    case removeNote
    case close
}

struct SelectionActionBarPresentation: Identifiable, Equatable {
    let id: UUID
    let anchorRect: CGRect
    let hasExistingNote: Bool
}

enum SelectionActionBarPlacement {
    static func localAnchorRect(
        _ anchorRect: CGRect,
        overlayFrameInRoot: CGRect
    ) -> CGRect {
        ReaderRootCoordinateSpace.localRect(
            anchorRect,
            overlayFrameInRoot: overlayFrameInRoot
        )
    }
}

@MainActor
final class SelectionActionBarModel: ObservableObject {
    @Published private(set) var presentation: SelectionActionBarPresentation?
    private var actionHandler: ((SelectionActionBarAction) -> Void)?

    func present(
        anchorRect: CGRect,
        hasExistingNote: Bool,
        onAction: @escaping (SelectionActionBarAction) -> Void
    ) {
        actionHandler = onAction
        presentation = SelectionActionBarPresentation(
            id: UUID(),
            anchorRect: anchorRect,
            hasExistingNote: hasExistingNote
        )
    }

    func perform(_ action: SelectionActionBarAction) {
        guard presentation != nil else { return }
        let handler = actionHandler
        dismiss()
        handler?(action)
    }

    func dismiss() {
        presentation = nil
        actionHandler = nil
    }
}

struct SelectionActionBarOverlay: View {
    @ObservedObject var model: SelectionActionBarModel
    @State private var actionBarSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            if let presentation = model.presentation {
                let localAnchorRect = SelectionActionBarPlacement.localAnchorRect(
                    presentation.anchorRect,
                    overlayFrameInRoot: proxy.frame(in: .named(ReaderRootCoordinateSpace.name))
                )
                SelectionActionBarView(
                    hasExistingNote: presentation.hasExistingNote,
                    onAction: model.perform
                )
                .background {
                    WindowOutsideClickMonitor(onOutsideClick: model.dismiss)
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { actionBarSize = $0 }
                .position(placementCenter(for: localAnchorRect, in: proxy.size))
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .animation(.spring(duration: 0.18), value: model.presentation?.id)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.dismiss()
        }
    }

    private func placementCenter(for anchorRect: CGRect, in containerSize: CGSize) -> CGPoint {
        guard actionBarSize.width > 0, actionBarSize.height > 0 else {
            return CGPoint(x: anchorRect.midX, y: anchorRect.maxY + 10)
        }
        let result = ReadingOverlayPlacementPolicy.place(
            ReadingOverlayPlacementInput(
                anchorRect: anchorRect,
                overlaySize: actionBarSize,
                containerSize: containerSize,
                preferredGap: 10,
                horizontalSafeInset: 8,
                verticalSafeInset: 6
            )
        )
        return CGPoint(
            x: result.origin.x + actionBarSize.width / 2,
            y: result.origin.y + actionBarSize.height / 2
        )
    }
}

private struct SelectionActionBarView: View {
    let hasExistingNote: Bool
    let onAction: (SelectionActionBarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            actionButton(icon: "character.bubble", label: "翻译", action: .translate)
            divider
            actionButton(icon: "text.bubble", label: "解释", action: .explain)
            divider
            actionButton(icon: "highlighter", label: "高亮", action: .highlight)
            divider
            actionButton(icon: "underline", label: "划线", action: .underline)
            divider
            if hasExistingNote {
                actionButton(icon: "plus.bubble", label: "添加笔记", action: .addNote)
                divider
                actionButton(icon: "note.text", label: "取消笔记", action: .removeNote)
            } else {
                actionButton(icon: "note.text", label: "笔记", action: .addNote)
            }
            divider
            actionButton(icon: "xmark", label: "", action: .close)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .fixedSize()
    }

    private var divider: some View {
        Divider().frame(height: 26)
    }

    private func actionButton(
        icon: String,
        label: String,
        action: SelectionActionBarAction
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                if !label.isEmpty {
                    Text(label).font(.system(size: 13))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct WindowOutsideClickMonitor: NSViewRepresentable {
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

        init(onOutsideClick: @escaping () -> Void) {
            self.onOutsideClick = onOutsideClick
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self else { return event }
                let clickedInside = if let view = self.view,
                                       event.window === view.window {
                    view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                } else {
                    false
                }
                if !clickedInside {
                    DispatchQueue.main.async { [weak self] in self?.onOutsideClick() }
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
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
