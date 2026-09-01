import AppKit
import SwiftUI

/// Preferred attachment edge for the system translation popover.
/// Horizontal edges only: vertical `NSRectEdge` depends on whether the
/// positioning view is flipped, so we never ask AppKit to attach above/below.
enum TranslationPopoverEdge: Equatable {
    /// Popover to the left of the selection; system arrow on the right edge.
    case leading
    /// Popover to the right of the selection; system arrow on the left edge.
    case trailing

    var nsRectEdge: NSRectEdge {
        switch self {
        case .leading: return .minX
        case .trailing: return .maxX
        }
    }
}

/// Layout helpers for the system `NSPopover`. Pure geometry; no I/O.
enum TranslationPopoverGeometry {
    static let arrowAllowance: CGFloat = 22
    static let inset: CGFloat = 12
    static let minWidth: CGFloat = 280
    static let maxWidth: CGFloat = 760
    static let minHeight: CGFloat = 120

    static func contentWidth(
        isSentenceMode: Bool,
        textCount: Int,
        availableWidth: CGFloat
    ) -> CGFloat {
        let usable = max(availableWidth, 420)
        let cap = min(max(minWidth, usable - 96), maxWidth)
        let base: CGFloat = isSentenceMode ? 560 : 320
        return min(max(base, CGFloat(textCount) * 4.2), cap)
    }

    static func preferredEdge(
        anchorRect: CGRect,
        contentSize: CGSize,
        containerSize: CGSize
    ) -> TranslationPopoverEdge {
        let needWidth = contentSize.width + arrowAllowance
        let left = anchorRect.minX - inset
        let right = containerSize.width - anchorRect.maxX - inset
        if left >= needWidth { return .leading }
        if right >= needWidth { return .trailing }
        return left >= right ? .leading : .trailing
    }

    static func clampContentSize(_ size: CGSize, available: CGSize) -> CGSize {
        let maxW = min(max(available.width - 24, minWidth), maxWidth)
        let maxH = max(available.height * 0.8, minHeight)
        return CGSize(
            width: min(max(size.width, minWidth), maxW),
            height: min(max(size.height, minHeight), maxH)
        )
    }

    static func selectionFrame(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width, 1),
            height: max(rect.height, 1)
        )
    }
}

/// Pins a 1:1 selection-sized `NSView` and presents a real `NSPopover` from it.
/// AppKit draws the beak, vibrancy, and shadow as one chrome shape.
struct TranslationNativePopover: NSViewRepresentable {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    let availableSize: CGSize
    let onSave: (TranslationResult) -> String?
    let onDelete: (String, Bool) -> Void
    let onExplain: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> TranslationNativePopoverCoordinator {
        TranslationNativePopoverCoordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> TranslationPopoverPositioningView {
        let view = TranslationPopoverPositioningView()
        view.coordinator = context.coordinator
        context.coordinator.positioningView = view
        return view
    }

    func updateNSView(_ view: TranslationPopoverPositioningView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.positioningView = view
        context.coordinator.sync(
            request: request,
            isLoading: isLoading,
            availableSize: availableSize,
            onSave: onSave,
            onDelete: onDelete,
            onExplain: onExplain,
            onRetry: onRetry,
            onDismiss: onDismiss
        )
    }

    static func dismantleNSView(
        _ view: TranslationPopoverPositioningView,
        coordinator: TranslationNativePopoverCoordinator
    ) {
        coordinator.dismantle()
        view.coordinator = nil
    }
}

final class TranslationPopoverLiveContent: ObservableObject {
    @Published var request: TranslationBubbleRequest
    @Published var isLoading: Bool
    @Published var availableSize: CGSize
    var onSave: (TranslationResult) -> String?
    var onDelete: (String, Bool) -> Void
    var onExplain: () -> Void
    var onRetry: () -> Void
    var onDismiss: () -> Void

    init(
        request: TranslationBubbleRequest,
        isLoading: Bool,
        availableSize: CGSize,
        onSave: @escaping (TranslationResult) -> String?,
        onDelete: @escaping (String, Bool) -> Void,
        onExplain: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.isLoading = isLoading
        self.availableSize = availableSize
        self.onSave = onSave
        self.onDelete = onDelete
        self.onExplain = onExplain
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
}

private struct TranslationPopoverLiveHost: View {
    @ObservedObject var live: TranslationPopoverLiveContent

    var body: some View {
        TranslationBubble(
            request: live.request,
            isLoading: live.isLoading,
            availableSize: live.availableSize,
            onSave: { live.onSave($0) },
            onDelete: { id, savedToNote in live.onDelete(id, savedToNote) },
            onExplain: { live.onExplain() },
            onRetry: { live.onRetry() },
            onDismiss: { live.onDismiss() }
        )
    }
}

@MainActor
final class TranslationNativePopoverCoordinator: NSObject, NSPopoverDelegate {
    var onDismiss: () -> Void
    weak var positioningView: TranslationPopoverPositioningView?

    private var popover: NSPopover?
    private var hostingController: TranslationPopoverHostingController<TranslationPopoverLiveHost>?
    private var live: TranslationPopoverLiveContent?
    private var shownRequestID: UUID?
    private var lockedEdge: TranslationPopoverEdge?
    private var lastContentSize: CGSize = .zero
    private var isClosingFromOwner = false
    private var suppressShow = false
    private var hasSynced = false
    private var lastAvailableSize: CGSize = .zero

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func sync(
        request: TranslationBubbleRequest,
        isLoading: Bool,
        availableSize: CGSize,
        onSave: @escaping (TranslationResult) -> String?,
        onDelete: @escaping (String, Bool) -> Void,
        onExplain: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        lastAvailableSize = availableSize
        hasSynced = true
        self.onDismiss = onDismiss

        if let live {
            if live.request != request { live.request = request }
            if live.isLoading != isLoading { live.isLoading = isLoading }
            if live.availableSize != availableSize { live.availableSize = availableSize }
            live.onSave = onSave
            live.onDelete = onDelete
            live.onExplain = onExplain
            live.onRetry = onRetry
            live.onDismiss = onDismiss
        } else {
            let live = TranslationPopoverLiveContent(
                request: request,
                isLoading: isLoading,
                availableSize: availableSize,
                onSave: onSave,
                onDelete: onDelete,
                onExplain: onExplain,
                onRetry: onRetry,
                onDismiss: onDismiss
            )
            self.live = live
            let hosting = TranslationPopoverHostingController(
                rootView: TranslationPopoverLiveHost(live: live)
            )
            hosting.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
            hosting.onFittingSize = { [weak self] size in
                self?.applyMeasuredSize(size)
            }
            hostingController = hosting
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = hosting
            popover.delegate = self
            let width = TranslationPopoverGeometry.contentWidth(
                isSentenceMode: request.isSentenceMode,
                textCount: (request.isSentenceMode ? request.word : request.sentence).count,
                availableWidth: availableSize.width
            )
            popover.contentSize = TranslationPopoverGeometry.clampContentSize(
                CGSize(width: width, height: 220),
                available: availableSize
            )
            self.popover = popover
        }

        if shownRequestID != request.id {
            closeWithoutNotifying()
            suppressShow = false
            lockedEdge = nil
            lastContentSize = .zero
            shownRequestID = request.id
        }

        showIfPossible()
    }

    func showIfPossible() {
        guard hasSynced, !suppressShow else { return }
        guard let view = positioningView, view.window != nil else { return }
        guard view.bounds.width >= 1, view.bounds.height >= 1 else { return }
        guard let popover, !popover.isShown, let live else { return }

        let contentSize = popover.contentSize.width > 1
            ? popover.contentSize
            : CGSize(width: 320, height: 220)
        let edge = lockedEdge ?? TranslationPopoverGeometry.preferredEdge(
            anchorRect: live.request.selectionAnchorRect,
            contentSize: contentSize,
            containerSize: lastAvailableSize
        )
        lockedEdge = edge
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge.nsRectEdge)
    }

    private func applyMeasuredSize(_ size: CGSize) {
        guard let popover else { return }
        let clamped = TranslationPopoverGeometry.clampContentSize(size, available: lastAvailableSize)
        if abs(clamped.width - lastContentSize.width) < 1,
           abs(clamped.height - lastContentSize.height) < 1
        {
            return
        }
        lastContentSize = clamped
        if popover.contentSize != clamped {
            popover.contentSize = clamped
        }
    }

    func dismantle() {
        isClosingFromOwner = true
        popover?.delegate = nil
        if popover?.isShown == true {
            popover?.close()
        }
        popover = nil
        hostingController?.onFittingSize = nil
        hostingController = nil
        live = nil
        shownRequestID = nil
        lockedEdge = nil
    }

    private func closeWithoutNotifying() {
        isClosingFromOwner = true
        if popover?.isShown == true {
            popover?.close()
        }
        isClosingFromOwner = false
    }

    func popoverDidClose(_ notification: Notification) {
        guard !isClosingFromOwner else { return }
        suppressShow = true
        onDismiss()
    }
}

final class TranslationPopoverPositioningView: NSView {
    weak var coordinator: TranslationNativePopoverCoordinator?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.showIfPossible()
    }

    override func layout() {
        super.layout()
        coordinator?.showIfPossible()
    }
}

final class TranslationPopoverHostingController<Content: View>: NSHostingController<Content> {
    var onFittingSize: ((CGSize) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.autoresizingMask = [.width, .height]
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let fitting = view.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }
        onFittingSize?(fitting)
    }
}
