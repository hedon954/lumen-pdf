import AppKit
import SwiftUI

enum ReadingOverlayPanelID {
    static let identifier = NSUserInterfaceItemIdentifier("LumenPDF.ReadingOverlayPanel")

    static func isOverlay(_ window: NSWindow?) -> Bool {
        window?.identifier == identifier
    }
}

/// Hosts a reading popover in a borderless child panel so the user can drag it
/// outside the app window. Clicks in other apps do not dismiss it.
struct ReadingOverlayPanelHost<Content: View>: NSViewRepresentable {
    let resetID: AnyHashable
    let anchorRect: CGRect
    let availableSize: CGSize
    let placementOrder: [ReadingOverlayPlacement]
    let preferredGap: CGFloat
    let compactVerticalInset: Bool
    let content: Content

    init(
        resetID: AnyHashable,
        anchorRect: CGRect,
        availableSize: CGSize,
        placementOrder: [ReadingOverlayPlacement],
        preferredGap: CGFloat,
        compactVerticalInset: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.resetID = resetID
        self.anchorRect = anchorRect
        self.availableSize = availableSize
        self.placementOrder = placementOrder
        self.preferredGap = preferredGap
        self.compactVerticalInset = compactVerticalInset
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AttachView {
        let view = AttachView()
        bind(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: AttachView, context: Context) {
        bind(nsView, coordinator: context.coordinator)
        context.coordinator.update(
            resetID: resetID,
            anchorRect: anchorRect,
            availableSize: availableSize,
            placementOrder: placementOrder,
            preferredGap: preferredGap,
            compactVerticalInset: compactVerticalInset,
            content: content
        )
    }

    static func dismantleNSView(_ nsView: AttachView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.dismiss()
    }

    private func bind(_ view: AttachView, coordinator: Coordinator) {
        coordinator.attachView = view
        view.onWindowChange = { [weak coordinator] in
            coordinator?.presentPendingIfPossible()
        }
    }

    final class AttachView: NSView {
        var onWindowChange: (() -> Void)?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?()
        }
    }

    @MainActor
    final class Coordinator {
        weak var attachView: AttachView?
        private var panel: OverlayPanel?
        private var hostingView: NSHostingView<AnyView>?
        private var didUserMove = false
        private var isApplyingFrame = false
        private var lastResetID: AnyHashable?
        private var moveObserver: NSObjectProtocol?
        private var reportedSize: CGSize = .zero
        private var pending: PendingPresentation?

        func update<Hosted: View>(
            resetID: AnyHashable,
            anchorRect: CGRect,
            availableSize: CGSize,
            placementOrder: [ReadingOverlayPlacement],
            preferredGap: CGFloat,
            compactVerticalInset: Bool,
            content: Hosted
        ) {
            if lastResetID != resetID {
                didUserMove = false
                reportedSize = .zero
                lastResetID = resetID
            }
            pending = PendingPresentation(
                resetID: resetID,
                anchorRect: anchorRect,
                availableSize: availableSize,
                placementOrder: placementOrder,
                preferredGap: preferredGap,
                compactVerticalInset: compactVerticalInset,
                content: AnyView(content)
            )
            presentPendingIfPossible()
            if attachView?.window == nil {
                DispatchQueue.main.async { [weak self] in
                    self?.presentPendingIfPossible()
                }
            }
        }

        func presentPendingIfPossible() {
            guard let pending, let attachView, let parent = attachView.window else { return }
            presentIfNeeded(parent: parent)
            let localAnchor = panelLocalAnchor(from: pending.anchorRect)
            let hosted = AnyView(
                pending.content
                    .environment(\.readingOverlayUsesPanel, true)
                    .environment(\.readingOverlayPanelLocalAnchor, localAnchor)
                    .environment(\.readingOverlayReportedSize) { [weak self] size in
                        self?.handleReportedSize(
                            size,
                            anchorRect: pending.anchorRect,
                            availableSize: pending.availableSize,
                            placementOrder: pending.placementOrder,
                            preferredGap: pending.preferredGap,
                            compactVerticalInset: pending.compactVerticalInset
                        )
                    }
            )
            hostingView?.rootView = hosted
            hostingView?.invalidateIntrinsicContentSize()
            hostingView?.layoutSubtreeIfNeeded()
            layoutPanel(
                anchorRect: pending.anchorRect,
                availableSize: pending.availableSize,
                placementOrder: pending.placementOrder,
                preferredGap: pending.preferredGap,
                compactVerticalInset: pending.compactVerticalInset
            )
        }

        func dismiss() {
            if let observer = moveObserver {
                NotificationCenter.default.removeObserver(observer)
                moveObserver = nil
            }
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
                panel.contentView = nil
            }
            panel = nil
            hostingView = nil
            didUserMove = false
            reportedSize = .zero
            lastResetID = nil
            pending = nil
        }

        private func presentIfNeeded(parent: NSWindow) {
            if let panel {
                if panel.parent !== parent {
                    panel.parent?.removeChildWindow(panel)
                    parent.addChildWindow(panel, ordered: .above)
                }
                return
            }
            let panel = OverlayPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.identifier = ReadingOverlayPanelID.identifier
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .canJoinAllSpaces]
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = false
            let hosting = NSHostingView(rootView: AnyView(EmptyView()))
            hosting.sizingOptions = [.intrinsicContentSize]
            hosting.shadow = nil
            panel.contentView = hosting
            panel.hasShadow = false
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            self.panel = panel
            self.hostingView = hosting
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                guard let self, !self.isApplyingFrame else { return }
                self.didUserMove = true
            }
        }

        private func handleReportedSize(
            _ size: CGSize,
            anchorRect: CGRect,
            availableSize: CGSize,
            placementOrder: [ReadingOverlayPlacement],
            preferredGap: CGFloat,
            compactVerticalInset: Bool
        ) {
            guard size.width > 1, size.height > 1 else { return }
            let changed = abs(size.width - reportedSize.width) > 0.5
                || abs(size.height - reportedSize.height) > 0.5
            reportedSize = size
            guard changed else { return }
            layoutPanel(
                anchorRect: anchorRect,
                availableSize: availableSize,
                placementOrder: placementOrder,
                preferredGap: preferredGap,
                compactVerticalInset: compactVerticalInset
            )
        }

        private func layoutPanel(
            anchorRect: CGRect,
            availableSize: CGSize,
            placementOrder: [ReadingOverlayPlacement],
            preferredGap: CGFloat,
            compactVerticalInset: Bool
        ) {
            guard let panel, let attachView, let window = attachView.window else { return }
            let fitted = hostingView?.fittingSize ?? .zero
            let size: CGSize = if reportedSize.width > 1, reportedSize.height > 1 {
                reportedSize
            } else if fitted.width > 1, fitted.height > 1 {
                fitted
            } else {
                CGSize(width: 380, height: 240)
            }
            if didUserMove {
                var frame = panel.frame
                let origin = frame.origin
                frame.size = size
                frame.origin = origin
                applyFrame(frame)
                return
            }
            let origin = ReadingOverlayPlacementPolicy.place(
                ReadingOverlayPlacementInput(
                    anchorRect: anchorRect,
                    overlaySize: size,
                    containerSize: availableSize,
                    preferredGap: preferredGap,
                    horizontalSafeInset: 12,
                    verticalSafeInset: compactVerticalInset ? 12 : availableSize.height * 0.1,
                    placementOrder: placementOrder
                )
            ).origin
            let viewRect = CGRect(origin: origin, size: size)
            let windowRect = attachView.convert(viewRect, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            applyFrame(screenRect)
        }

        private struct PendingPresentation {
            let resetID: AnyHashable
            let anchorRect: CGRect
            let availableSize: CGSize
            let placementOrder: [ReadingOverlayPlacement]
            let preferredGap: CGFloat
            let compactVerticalInset: Bool
            let content: AnyView
        }

        private func applyFrame(_ frame: NSRect) {
            guard let panel else { return }
            isApplyingFrame = true
            panel.setFrame(frame, display: true)
            isApplyingFrame = false
        }

        private func panelLocalAnchor(from overlayAnchor: CGRect) -> CGRect {
            guard let panel, let attachView, let window = attachView.window else {
                return overlayAnchor
            }
            let windowRect = attachView.convert(overlayAnchor, to: nil)
            let screen = window.convertToScreen(windowRect)
            let frame = panel.frame
            return CGRect(
                x: screen.minX - frame.minX,
                y: frame.maxY - screen.maxY,
                width: max(screen.width, 1),
                height: max(screen.height, 1)
            )
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private enum ReadingOverlayUsesPanelKey: EnvironmentKey {
    static let defaultValue = false
}

private enum ReadingOverlayPanelLocalAnchorKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

private enum ReadingOverlayReportedSizeKey: EnvironmentKey {
    static let defaultValue: ((CGSize) -> Void)? = nil
}

extension EnvironmentValues {
    var readingOverlayUsesPanel: Bool {
        get { self[ReadingOverlayUsesPanelKey.self] }
        set { self[ReadingOverlayUsesPanelKey.self] = newValue }
    }

    var readingOverlayPanelLocalAnchor: CGRect? {
        get { self[ReadingOverlayPanelLocalAnchorKey.self] }
        set { self[ReadingOverlayPanelLocalAnchorKey.self] = newValue }
    }

    var readingOverlayReportedSize: ((CGSize) -> Void)? {
        get { self[ReadingOverlayReportedSizeKey.self] }
        set { self[ReadingOverlayReportedSizeKey.self] = newValue }
    }
}
