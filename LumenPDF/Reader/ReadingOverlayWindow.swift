import AppKit
import SwiftUI

struct ReadingOverlayWindowConfiguration {
    let width: CGFloat
    let initialContentHeight: CGFloat
    let minimumContentHeight: CGFloat
    let isResizable: Bool
    let minimumSize: CGSize
    let maximumSize: CGSize
    let dismissesOnBackgroundTap: Bool
    let showsFooter: Bool
    let showsAnchorPointer: Bool
    let placementOrder: [ReadingOverlayPlacement]
    let preferredGap: CGFloat
    let compactVerticalInset: Bool
    let opaqueChrome: Bool

    init(
        width: CGFloat,
        initialContentHeight: CGFloat = 160,
        minimumContentHeight: CGFloat = 80,
        isResizable: Bool = false,
        minimumSize: CGSize = CGSize(width: 340, height: 240),
        maximumSize: CGSize = CGSize(width: 920, height: 820),
        dismissesOnBackgroundTap: Bool = false,
        showsFooter: Bool = true,
        showsAnchorPointer: Bool = false,
        placementOrder: [ReadingOverlayPlacement] = ReadingOverlayPlacement.defaultOrder,
        preferredGap: CGFloat = 12,
        compactVerticalInset: Bool = false,
        opaqueChrome: Bool = false
    ) {
        self.width = width
        self.initialContentHeight = initialContentHeight
        self.minimumContentHeight = minimumContentHeight
        self.isResizable = isResizable
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.dismissesOnBackgroundTap = dismissesOnBackgroundTap
        self.showsFooter = showsFooter
        self.showsAnchorPointer = showsAnchorPointer
        self.placementOrder = placementOrder
        self.preferredGap = preferredGap
        self.compactVerticalInset = compactVerticalInset
        self.opaqueChrome = opaqueChrome
    }
}

struct ReadingOverlayWindow<Header: View, Content: View, Footer: View>: View {
    let anchorRect: CGRect
    let availableSize: CGSize
    let resetID: AnyHashable
    let configuration: ReadingOverlayWindowConfiguration
    let onDismiss: () -> Void

    @ViewBuilder private let header: () -> Header
    @ViewBuilder private let content: () -> Content
    @ViewBuilder private let footer: () -> Footer

    @State private var measuredWindowSize: CGSize = .zero
    @State private var measuredHeaderHeight: CGFloat = 0
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0
    @State private var customSize: CGSize?
    @State private var customCenter: CGPoint?
    @State private var lockedOrigin: CGPoint?
    @State private var lockedPlacement: ReadingOverlayPlacement?

    private var preferredGap: CGFloat { configuration.preferredGap }
    private let horizontalSafeInset: CGFloat = 12

    init(
        anchorRect: CGRect,
        availableSize: CGSize,
        resetID: AnyHashable,
        configuration: ReadingOverlayWindowConfiguration,
        onDismiss: @escaping () -> Void,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.anchorRect = anchorRect
        self.availableSize = availableSize
        self.resetID = resetID
        self.configuration = configuration
        self.onDismiss = onDismiss
        self.header = header
        self.content = content
        self.footer = footer
    }

    var body: some View {
        // `.position` expands the child's layout/hit-testing to the full parent. An empty
        // `onTapGesture` on that child then swallows every click in the reader, so outside
        // taps and even header buttons stop working. Place the card with `offset` instead so
        // only its visual bounds receive hits; the clear backdrop handles dismissal.
        ZStack(alignment: .topLeading) {
            if configuration.dismissesOnBackgroundTap {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
            }

            window
                .offset(x: displayedOrigin.x, y: displayedOrigin.y)
                .animation(nil, value: customCenter)
                .animation(nil, value: displayedOrigin)
        }
        // Keep the placement origin at the reader's top-left even when this overlay does not
        // install a full-size dismissal backdrop. Without an explicit frame alignment, a
        // non-dismissible window is first centered by the outer frame and then offset again,
        // which sends note drafts toward the bottom-right corner.
        .frame(
            width: availableSize.width,
            height: availableSize.height,
            alignment: .topLeading
        )
        .onChange(of: resetID) { _, _ in resetWindowState() }
        .onChange(of: availableSize) { _, _ in handleAvailableSizeChange() }
        .onChange(of: anchorRect) { oldRect, newRect in
            let moved = hypot(newRect.midX - oldRect.midX, newRect.midY - oldRect.midY)
            guard moved > 0.5 else { return }
            relockOriginForAnchorChange()
        }
    }

    private var window: some View {
        let pointing = showsPointer ? pointingSide : nil
        let along = pointing.map { side in
            ReadingOverlayPointerGeometry.alongEdge(
                anchorRect: anchorRect,
                overlayOrigin: displayedOrigin,
                overlaySize: renderedSize,
                placement: side
            )
        } ?? 0

        let card = VStack(alignment: .leading, spacing: 0) {
            header()
                .readingOverlayMeasureHeight { measuredHeaderHeight = $0 }

            Divider()

            contentViewport

            if configuration.showsFooter {
                Divider()
                footer()
                    .readingOverlayMeasureHeight { measuredFooterHeight = $0 }
            }
        }
        .frame(width: cardBodyWidth, height: cardBodyHeight)
        .overlay {
            resizeOverlay
                .padding(.top, max(0, measuredHeaderHeight - resizeHitThickness))
        }

        return chrome(card: card, pointing: pointing, along: along)
            .shadow(
                color: .black.opacity(showsPointer ? 0.22 : 0.12),
                radius: showsPointer ? 22 : 18,
                x: 0,
                y: showsPointer ? 10 : 8
            )
            .environment(\.readingOverlayMove, moveWindow)
            .readingOverlayMeasureSize(recordMeasuredWindowSize)
    }

    @ViewBuilder
    private func chrome(
        card: some View,
        pointing: ReadingOverlayPlacement?,
        along: CGFloat
    ) -> some View {
        if let pointing {
            roundedCard(card, opaque: configuration.opaqueChrome)
                .padding(swiftUIInsets(ReadingOverlayPointerGeometry.contentInsets(for: pointing)))
                .overlay(alignment: .topLeading) {
                    arrowOverlay(
                        placement: pointing,
                        along: along,
                        opaque: configuration.opaqueChrome
                    )
                }
        } else {
            card
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func roundedCard(_ card: some View, opaque: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if opaque {
            card
                .background(Color(nsColor: .textBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5) }
                .clipShape(shape)
        } else {
            card
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                .clipShape(shape)
        }
    }

    private func swiftUIInsets(_ insets: ReadingOverlayEdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: insets.top,
            leading: insets.leading,
            bottom: insets.bottom,
            trailing: insets.trailing
        )
    }

    private func arrowOverlay(
        placement: ReadingOverlayPlacement,
        along: CGFloat,
        opaque: Bool
    ) -> some View {
        let frame = ReadingOverlayPointerGeometry.arrowFrame(
            overlaySize: renderedSize,
            along: along,
            placement: placement
        )
        let fill = Color(nsColor: .textBackgroundColor)
        return ReadingOverlayArrowShape(placement: placement)
            .fill(fill)
            .overlay {
                if !opaque {
                    ReadingOverlayArrowShape(placement: placement)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                ReadingOverlayArrowShape(placement: placement)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 0.6)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var showsPointer: Bool { configuration.showsAnchorPointer }

    /// Side that owns the popover arrow. Must match the side `place` actually
    /// chose — assuming `.leading` while the card sits on the right put the
    /// triangle on the far edge, away from the word.
    private var pointingSide: ReadingOverlayPlacement {
        if let lockedPlacement {
            return lockedPlacement == .leastOverlap ? nearestPointerSide() : lockedPlacement
        }
        let placed = ReadingOverlayPlacementPolicy.place(
            placementInput(for: placementSizeForPointer)
        ).placement
        return placed == .leastOverlap ? nearestPointerSide() : placed
    }

    /// Outer size used to decide the arrow side without reading `renderedSize`
    /// (that size itself depends on the pointing side).
    private var placementSizeForPointer: CGSize {
        if let customSize { return customSize }
        if measuredWindowSize.width > 1, measuredWindowSize.height > 1 {
            return measuredWindowSize
        }
        let assumed = configuration.placementOrder.first { $0 != .leastOverlap } ?? .leading
        return ReadingOverlayPointerGeometry.outerSize(
            body: CGSize(
                width: min(configuration.width, maximumAvailableWidth),
                height: min(maximumWindowHeight, 240)
            ),
            placement: assumed
        )
    }

    private func nearestPointerSide() -> ReadingOverlayPlacement {
        let size: CGSize
        if let customSize {
            size = customSize
        } else if measuredWindowSize.width > 1, measuredWindowSize.height > 1 {
            size = measuredWindowSize
        } else {
            size = CGSize(width: configuration.width, height: 240)
        }
        let overlay = CGRect(origin: lockedOrigin ?? .zero, size: size)
        let dx = anchorRect.midX - overlay.midX
        let dy = anchorRect.midY - overlay.midY
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .leading : .trailing
        }
        return dy >= 0 ? .above : .below
    }

    private var contentViewport: some View {
        ScrollView {
            measuredContent
        }
        .frame(maxWidth: .infinity)
        .frame(height: customSize == nil ? automaticContentHeight : nil)
        .frame(maxHeight: customSize == nil ? nil : .infinity)
        .scrollIndicators(.automatic)
        .layoutPriority(customSize == nil ? 0 : 1)
    }

    private var measuredContent: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .readingOverlayMeasureHeight(recordMeasuredContentHeight)
    }

    private var automaticContentHeight: CGFloat {
        let proposed = measuredContentHeight > 1
            ? measuredContentHeight
            : configuration.initialContentHeight
        return min(max(proposed, configuration.minimumContentHeight), maximumContentHeight)
    }

    private var maximumContentHeight: CGFloat {
        let dividerHeight: CGFloat = configuration.showsFooter ? 2 : 1
        return max(
            1,
            maximumWindowHeight
            - measuredHeaderHeight
            - measuredFooterHeight
            - dividerHeight
        )
    }

    private var verticalSafeInset: CGFloat {
        if configuration.compactVerticalInset {
            return horizontalSafeInset
        }
        return availableSize.height * 0.1
    }

    private var maximumWindowHeight: CGFloat {
        max(1, availableSize.height * 0.8)
    }

    private var cardBodyWidth: CGFloat {
        bodySize(forOuter: renderedSize).width
    }

    private var cardBodyHeight: CGFloat? {
        customSize.map { bodySize(forOuter: $0).height }
    }

    private func bodySize(forOuter outer: CGSize) -> CGSize {
        guard showsPointer else { return outer }
        return ReadingOverlayPointerGeometry.bodySize(outer: outer, placement: pointingSide)
    }

    private var maximumAvailableWidth: CGFloat {
        max(1, availableSize.width - horizontalSafeInset * 2)
    }

    private var renderedSize: CGSize {
        if let customSize { return customSize }
        if measuredWindowSize.width > 0, measuredWindowSize.height > 0 {
            return CGSize(
                width: min(measuredWindowSize.width, maximumAvailableWidth),
                height: min(measuredWindowSize.height, maximumWindowHeight)
            )
        }
        let arrowX = showsPointer && pointingSide.isHorizontal ? ReadingOverlayPointerGeometry.arrowDepth : 0
        let arrowY = showsPointer && !pointingSide.isHorizontal ? ReadingOverlayPointerGeometry.arrowDepth : 0
        let body = CGSize(
            width: min(configuration.width, max(1, maximumAvailableWidth - arrowX)),
            height: min(
                max(1, maximumWindowHeight - arrowY),
                automaticContentHeight + max(measuredHeaderHeight + measuredFooterHeight + 2, 96)
            )
        )
        guard showsPointer else { return body }
        return ReadingOverlayPointerGeometry.outerSize(body: body, placement: pointingSide)
    }

    private var displayedCenter: CGPoint {
        let size = renderedSize
        let origin = displayedOrigin
        return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    private var displayedOrigin: CGPoint {
        let size = renderedSize
        if let customCenter {
            let center = clampedCenter(
                customCenter,
                windowSize: size,
                verticalSafeInset: horizontalSafeInset
            )
            return CGPoint(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2
            )
        }
        let origin = lockedOrigin ?? automaticOrigin(for: size)
        return ReadingOverlayPlacementPolicy.clamp(
            origin: origin,
            overlaySize: size,
            containerSize: availableSize,
            horizontalSafeInset: horizontalSafeInset,
            verticalSafeInset: verticalSafeInset
        )
    }

    private func automaticOrigin(for size: CGSize) -> CGPoint {
        ReadingOverlayPlacementPolicy.place(placementInput(for: size)).origin
    }

    private func placementInput(for size: CGSize) -> ReadingOverlayPlacementInput {
        ReadingOverlayPlacementInput(
            anchorRect: anchorRect,
            overlaySize: size,
            containerSize: availableSize,
            preferredGap: preferredGap,
            horizontalSafeInset: horizontalSafeInset,
            verticalSafeInset: verticalSafeInset,
            placementOrder: configuration.placementOrder
        )
    }

    private func recordMeasuredContentHeight(_ height: CGFloat) {
        measuredContentHeight = height
    }

    private func recordMeasuredWindowSize(_ size: CGSize) {
        lockOriginIfNeeded(for: size)
        measuredWindowSize = size
    }

    private func lockOriginIfNeeded(for size: CGSize) {
        guard lockedOrigin == nil,
              customCenter == nil,
              size.width > 1,
              size.height > 1 else { return }
        let result = ReadingOverlayPlacementPolicy.place(placementInput(for: size))
        lockedOrigin = result.origin
        lockedPlacement = result.placement
    }

    /// Overlay-local conversion can land one frame after the first measure.
    /// Re-place against the updated selection so the pointer is not stuck on
    /// a toolbar-shifted origin. Keep a user drag (`customCenter`) as-is.
    private func relockOriginForAnchorChange() {
        guard customCenter == nil else { return }
        lockedOrigin = nil
        lockedPlacement = nil
        lockOriginIfNeeded(for: measuredWindowSize)
    }

    private func clampedCenter(
        _ center: CGPoint,
        windowSize: CGSize,
        verticalSafeInset: CGFloat
    ) -> CGPoint {
        let origin = ReadingOverlayPlacementPolicy.clamp(
            origin: CGPoint(
                x: center.x - windowSize.width / 2,
                y: center.y - windowSize.height / 2
            ),
            overlaySize: windowSize,
            containerSize: availableSize,
            horizontalSafeInset: horizontalSafeInset,
            verticalSafeInset: verticalSafeInset
        )
        return CGPoint(
            x: origin.x + windowSize.width / 2,
            y: origin.y + windowSize.height / 2
        )
    }

    private func moveWindow(_ delta: CGSize) {
        let size = renderedSize
        let center = displayedCenter
        customCenter = clampedCenter(
            CGPoint(x: center.x + delta.width, y: center.y + delta.height),
            windowSize: size,
            verticalSafeInset: horizontalSafeInset
        )
    }

    @ViewBuilder
    private var resizeOverlay: some View {
        if configuration.isResizable {
            ZStack {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)

                resizeRegion(.top, cursor: .resizeUpDown)
                    .frame(height: resizeHitThickness)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                resizeRegion(.bottom, cursor: .resizeUpDown)
                    .frame(height: resizeHitThickness)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                resizeRegion(.leading, cursor: .resizeLeftRight)
                    .frame(width: resizeHitThickness)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                resizeRegion(.trailing, cursor: .resizeLeftRight)
                    .frame(width: resizeHitThickness)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                resizeRegion([.top, .leading], cursor: .resizeDiagonalDownRight)
                    .frame(width: resizeCornerSize, height: resizeCornerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                resizeRegion([.top, .trailing], cursor: .resizeDiagonalUpRight)
                    .frame(width: resizeCornerSize, height: resizeCornerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                resizeRegion([.bottom, .leading], cursor: .resizeDiagonalUpRight)
                    .frame(width: resizeCornerSize, height: resizeCornerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                resizeRegion([.bottom, .trailing], cursor: .resizeDiagonalDownRight)
                    .frame(width: resizeCornerSize, height: resizeCornerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private var resizeHitThickness: CGFloat { 6 }
    private var resizeCornerSize: CGFloat { 16 }

    private func resizeRegion(_ edges: ReadingOverlayResizeEdges, cursor: NSCursor) -> some View {
        ReadingOverlayResizeCapture(cursor: cursor) { delta in
            resizeWindow(by: delta, edges: edges)
        }
    }

    private func resizeWindow(by delta: CGSize, edges: ReadingOverlayResizeEdges) {
        let current = customSize ?? renderedSize
        let maxWidth = min(configuration.maximumSize.width, maximumAvailableWidth)
        let maxHeight = min(configuration.maximumSize.height, maximumWindowHeight)

        var nextWidth = current.width
        var nextHeight = current.height
        if edges.contains(.leading) { nextWidth -= delta.width }
        if edges.contains(.trailing) { nextWidth += delta.width }
        if edges.contains(.top) { nextHeight -= delta.height }
        if edges.contains(.bottom) { nextHeight += delta.height }

        nextWidth = min(max(nextWidth, configuration.minimumSize.width), maxWidth)
        nextHeight = min(max(nextHeight, configuration.minimumSize.height), maxHeight)

        let nextSize = CGSize(width: nextWidth, height: nextHeight)
        let widthDelta = nextWidth - current.width
        let heightDelta = nextHeight - current.height
        var nextCenter = displayedCenter

        if edges.contains(.leading), !edges.contains(.trailing) {
            nextCenter.x -= widthDelta / 2
        } else if edges.contains(.trailing), !edges.contains(.leading) {
            nextCenter.x += widthDelta / 2
        }
        if edges.contains(.top), !edges.contains(.bottom) {
            nextCenter.y -= heightDelta / 2
        } else if edges.contains(.bottom), !edges.contains(.top) {
            nextCenter.y += heightDelta / 2
        }

        customSize = nextSize
        customCenter = clampedCenter(
            nextCenter,
            windowSize: nextSize,
            verticalSafeInset: horizontalSafeInset
        )
    }

    private func handleAvailableSizeChange() {
        measuredWindowSize = .zero

        guard let customSize else {
            return
        }

        let maxWidth = min(configuration.maximumSize.width, maximumAvailableWidth)
        let maxHeight = min(configuration.maximumSize.height, maximumWindowHeight)
        let minWidth = min(configuration.minimumSize.width, maxWidth)
        let minHeight = min(configuration.minimumSize.height, maxHeight)
        let nextSize = CGSize(
            width: min(max(customSize.width, minWidth), maxWidth),
            height: min(max(customSize.height, minHeight), maxHeight)
        )
        let center = customCenter ?? displayedCenter
        self.customSize = nextSize
        customCenter = clampedCenter(
            center,
            windowSize: nextSize,
            verticalSafeInset: horizontalSafeInset
        )
    }

    private func resetWindowState() {
        measuredWindowSize = .zero
        measuredHeaderHeight = 0
        measuredContentHeight = 0
        measuredFooterHeight = 0
        customSize = nil
        customCenter = nil
        lockedOrigin = nil
        lockedPlacement = nil
    }
}

/// Drag handle for reading overlays. Place it in the header where the move affordance should be;
/// pressing and dragging it repositions the host `ReadingOverlayWindow`.
struct ReadingOverlayMoveHandle: View {
    @Environment(\.readingOverlayMove) private var move

    var body: some View {
        ReadingOverlayDragCapture { delta in
            move?(delta)
        }
        .frame(width: 28, height: 28)
        .overlay {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
        }
        .help("拖动以移动窗口")
        .accessibilityLabel("移动窗口")
    }
}

private enum ReadingOverlayMoveKey: EnvironmentKey {
    static let defaultValue: ((CGSize) -> Void)? = nil
}

private extension EnvironmentValues {
    var readingOverlayMove: ((CGSize) -> Void)? {
        get { self[ReadingOverlayMoveKey.self] }
        set { self[ReadingOverlayMoveKey.self] = newValue }
    }
}

private struct ReadingOverlayDragCapture: NSViewRepresentable {
    let onDelta: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDelta) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelta = onDelta
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class Coordinator: NSObject {
        var onDelta: (CGSize) -> Void
        lazy var view = CaptureView(coordinator: self)

        init(_ onDelta: @escaping (CGSize) -> Void) { self.onDelta = onDelta }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        private var lastLocation: CGPoint?
        private var isDragging = false

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func mouseDown(with event: NSEvent) {
            lastLocation = event.locationInWindow
            isDragging = true
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging, let lastLocation else { return }
            let current = event.locationInWindow
            coordinator?.onDelta(
                CGSize(width: current.x - lastLocation.x, height: -(current.y - lastLocation.y))
            )
            self.lastLocation = current
        }

        override func mouseUp(with event: NSEvent) {
            lastLocation = nil
            isDragging = false
            window?.invalidateCursorRects(for: self)
            NSCursor.openHand.set()
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

private struct ReadingOverlayResizeCapture: NSViewRepresentable {
    let cursor: NSCursor
    let onDelta: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(cursor: cursor, onDelta: onDelta) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.cursor = cursor
        context.coordinator.onDelta = onDelta
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class Coordinator: NSObject {
        var cursor: NSCursor
        var onDelta: (CGSize) -> Void
        lazy var view = CaptureView(coordinator: self)

        init(cursor: NSCursor, onDelta: @escaping (CGSize) -> Void) {
            self.cursor = cursor
            self.onDelta = onDelta
        }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        private var lastLocation: CGPoint?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func mouseDown(with event: NSEvent) { lastLocation = event.locationInWindow }
        override func mouseDragged(with event: NSEvent) {
            guard let lastLocation else { return }
            let current = event.locationInWindow
            coordinator?.onDelta(
                CGSize(width: current.x - lastLocation.x, height: -(current.y - lastLocation.y))
            )
            self.lastLocation = current
        }
        override func mouseUp(with event: NSEvent) { lastLocation = nil }
        override func resetCursorRects() {
            if let cursor = coordinator?.cursor { addCursorRect(bounds, cursor: cursor) }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

private struct ReadingOverlayResizeEdges: OptionSet {
    let rawValue: Int

    static let top = ReadingOverlayResizeEdges(rawValue: 1 << 0)
    static let bottom = ReadingOverlayResizeEdges(rawValue: 1 << 1)
    static let leading = ReadingOverlayResizeEdges(rawValue: 1 << 2)
    static let trailing = ReadingOverlayResizeEdges(rawValue: 1 << 3)
}

private extension ReadingOverlayPlacement {
    var isHorizontal: Bool {
        switch self {
        case .leading, .trailing:
            return true
        case .above, .below, .leastOverlap:
            return false
        }
    }
}

private struct ReadingOverlayArrowShape: Shape {
    var placement: ReadingOverlayPlacement

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch placement {
        case .leading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .trailing:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .above:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .below, .leastOverlap:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private extension View {
    func readingOverlayMeasureSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        onGeometryChange(for: CGSize.self, of: { $0.size }, action: onChange)
    }

    func readingOverlayMeasureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onChange)
    }

}

private extension NSCursor {
    static var resizeDiagonalDownRight: NSCursor {
        diagonalResizeCursor(systemName: "arrow.down.right.and.arrow.up.left")
    }

    static var resizeDiagonalUpRight: NSCursor {
        diagonalResizeCursor(systemName: "arrow.up.right.and.arrow.down.left")
    }

    private static func diagonalResizeCursor(systemName: String) -> NSCursor {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        return NSCursor(image: image ?? NSImage(), hotSpot: NSPoint(x: 6, y: 6))
    }
}
