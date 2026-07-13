import AppKit
import SwiftUI

enum ReaderRootCoordinateSpace {
    static let name = "LumenPDF.ReaderRoot"
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
    let anchor: CGPoint
    let hasExistingNote: Bool
}

@MainActor
final class SelectionActionBarModel: ObservableObject {
    @Published private(set) var presentation: SelectionActionBarPresentation?
    private var actionHandler: ((SelectionActionBarAction) -> Void)?

    func present(
        anchor: CGPoint,
        hasExistingNote: Bool,
        onAction: @escaping (SelectionActionBarAction) -> Void
    ) {
        actionHandler = onAction
        presentation = SelectionActionBarPresentation(
            id: UUID(),
            anchor: anchor,
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
                SelectionActionBarView(
                    hasExistingNote: presentation.hasExistingNote,
                    onAction: model.perform
                )
                .background {
                    WindowOutsideClickMonitor(onOutsideClick: model.dismiss)
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { actionBarSize = $0 }
                .position(clampedCenter(for: presentation.anchor, in: proxy.size))
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .animation(.spring(duration: 0.18), value: model.presentation?.id)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.dismiss()
        }
    }

    private func clampedCenter(for proposed: CGPoint, in containerSize: CGSize) -> CGPoint {
        let horizontalInset: CGFloat = 8
        let verticalInset: CGFloat = 6
        return CGPoint(
            x: clamp(
                proposed.x,
                minimum: horizontalInset,
                maximum: containerSize.width - horizontalInset,
                length: actionBarSize.width
            ),
            y: clamp(
                proposed.y,
                minimum: verticalInset,
                maximum: containerSize.height - verticalInset,
                length: actionBarSize.height
            )
        )
    }

    private func clamp(
        _ proposed: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        length: CGFloat
    ) -> CGFloat {
        guard maximum > minimum, length < maximum - minimum else {
            return (minimum + maximum) / 2
        }
        return min(max(proposed, minimum + length / 2), maximum - length / 2)
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
