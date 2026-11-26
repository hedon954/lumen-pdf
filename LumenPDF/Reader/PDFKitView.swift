import SwiftUI
import PDFKit
import AppKit

enum ReaderViewportTransitionMode {
    case animatedChrome
    case interactiveResize
}

enum TranslationSelectionEmphasisStyle {
    /// Luminous Preview-style lookup yellow with a subtle top-to-bottom sheen.
    static let fillTop = NSColor(srgbRed: 1.0, green: 0.985, blue: 0.22, alpha: 1.0)
    static let fillBottom = NSColor(srgbRed: 1.0, green: 0.945, blue: 0.0, alpha: 1.0)
    static let shadow = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.24)
    static let gradient = NSGradient(starting: fillTop, ending: fillBottom)
}

enum TranslationSelectionEmphasisGeometry {
    /// Pill padding around the glyph bounds, matching macOS Preview's lookup badge.
    static let horizontalLift: CGFloat = 2.5
    static let verticalLift: CGFloat = 1.25
    static let cornerRadius: CGFloat = 3.5
    static let shadowBlur: CGFloat = 4.5
    static let shadowDepth: CGFloat = 1.5
    static let shadowMargin: CGFloat = 10

    static func highlightRect(for textRect: CGRect) -> CGRect {
        textRect.insetBy(dx: -horizontalLift, dy: -verticalLift)
    }

    /// Pill plus margin to hold its painted Gaussian drop shadow without clipping.
    static func viewFrame(for textRect: CGRect) -> CGRect {
        highlightRect(for: textRect).insetBy(dx: -shadowMargin, dy: -shadowMargin)
    }
}

/// Transient Preview-style lifted yellow pill over the user's selected words.
///
/// Draws an opaque yellow pill with a native CoreGraphics Gaussian shadow,
/// then renders the underlying PDF vector glyphs inside the clipped pill using
/// `.multiply` blend mode. Because the pill is opaque on top of its own shadow,
/// there is no `destinationOut` anti-aliasing halo, no `compositingFilter`
/// interference, and no bleed-through from saved highlights underneath.
/// Its owner is `PDFKitView.Coordinator`.
private final class TranslationSelectionEmphasisView: NSView {
    private struct Pill {
        let plateInPDFView: CGRect
        let page: PDFPage
        let pageToPDFView: CGAffineTransform
    }

    private weak var pdfView: PDFView?
    private var markups: [PDFPageMarkup] = []
    private var pills: [Pill] = []
    private var isLayingOutHighlights = false

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(markups: [PDFPageMarkup]) {
        self.markups = markups
        layoutHighlights()
    }

    func refresh() {
        layoutHighlights()
    }

    private func layoutHighlights() {
        guard !isLayingOutHighlights else { return }
        isLayingOutHighlights = true
        defer { isLayingOutHighlights = false }

        guard let pdfView, let document = pdfView.document else {
            pills = []
            isHidden = true
            frame = .zero
            return
        }

        let visibleBounds = pdfView.bounds
        var nextPills: [Pill] = []
        var unionFrame = CGRect.null

        for markup in markups {
            guard let page = document.page(at: markup.pageIndex) else { continue }
            let transform = Self.pageToPDFViewTransform(for: page, in: pdfView)
            for lineRect in markup.lineRects where !lineRect.isEmpty && lineRect != .zero {
                let rectInPDFView = pdfView.convert(lineRect, from: page)
                let plate = TranslationSelectionEmphasisGeometry.highlightRect(for: rectInPDFView)
                let padded = TranslationSelectionEmphasisGeometry.viewFrame(for: rectInPDFView)
                guard padded.intersects(visibleBounds) else { continue }
                nextPills.append(
                    Pill(plateInPDFView: plate, page: page, pageToPDFView: transform)
                )
                unionFrame = unionFrame.isNull ? padded : unionFrame.union(padded)
            }
        }

        pills = nextPills
        guard !nextPills.isEmpty, !unionFrame.isNull else {
            isHidden = true
            frame = .zero
            return
        }

        isHidden = false
        let snappedFrame = unionFrame.integral
        if frame != snappedFrame {
            frame = snappedFrame
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !pills.isEmpty, let context = NSGraphicsContext.current else { return }
        let cg = context.cgContext
        let originOffset = frame.origin
        let radius = TranslationSelectionEmphasisGeometry.cornerRadius

        // Pass 1: Opaque yellow bases + soft Gaussian shadows underneath.
        // Drawing all shadows before the fills prevents a multi-line pill's
        // shadow from darkening an adjacent line's yellow plate.
        for pill in pills {
            let plate = pill.plateInPDFView.offsetBy(dx: -originOffset.x, dy: -originOffset.y)
            let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
            cg.saveGState()
            cg.setShadow(
                offset: CGSize(width: 0, height: -TranslationSelectionEmphasisGeometry.shadowDepth),
                blur: TranslationSelectionEmphasisGeometry.shadowBlur,
                color: TranslationSelectionEmphasisStyle.shadow.cgColor
            )
            TranslationSelectionEmphasisStyle.fillBottom.setFill()
            path.fill()
            cg.restoreGState()
        }

        // Pass 2: Clean yellow sheen + crisp vector PDF glyphs multiplied on top.
        for pill in pills {
            let plate = pill.plateInPDFView.offsetBy(dx: -originOffset.x, dy: -originOffset.y)
            let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
            cg.saveGState()
            path.addClip()
            if let gradient = TranslationSelectionEmphasisStyle.gradient {
                gradient.draw(in: plate, angle: -90)
            } else {
                TranslationSelectionEmphasisStyle.fillBottom.setFill()
                plate.fill()
            }

            cg.setBlendMode(.multiply)
            cg.interpolationQuality = .high
            cg.setShouldAntialias(true)
            cg.setAllowsAntialiasing(true)
            cg.setShouldSmoothFonts(true)

            let pageToView = pill.pageToPDFView.concatenating(
                CGAffineTransform(translationX: -originOffset.x, y: -originOffset.y)
            )
            cg.concatenate(pageToView)
            if let pageRef = pill.page.pageRef {
                cg.drawPDFPage(pageRef)
            } else if let pdfView {
                pill.page.draw(with: pdfView.displayBox, to: cg)
            }
            cg.restoreGState()
        }
    }

    private static func pageToPDFViewTransform(
        for page: PDFPage,
        in pdfView: PDFView
    ) -> CGAffineTransform {
        let p0 = pdfView.convert(CGPoint(x: 0, y: 0), from: page)
        let px = pdfView.convert(CGPoint(x: 1, y: 0), from: page)
        let py = pdfView.convert(CGPoint(x: 0, y: 1), from: page)
        return CGAffineTransform(
            a: px.x - p0.x,
            b: px.y - p0.y,
            c: py.x - p0.x,
            d: py.y - p0.y,
            tx: p0.x,
            ty: p0.y
        )
    }
}

protocol ReaderViewportTransitionHandling: AnyObject {
    func beginReadingViewportTransition(mode: ReaderViewportTransitionMode)
    func endReadingViewportTransition()
}

enum ReaderUndoHistoryPolicy {
    /// Apple counts top-level undo groups, so one grouped cross-page edit is one history entry.
    static let minimumRequiredLevels = 20
    static let capacity = 50

    static func configure(_ undoManager: UndoManager) {
        MainActor.assumeIsolated {
            undoManager.levelsOfUndo = capacity
            undoManager.groupsByEvent = true
        }
    }

    static func clearActions(for target: AnyObject, from undoManager: UndoManager?) {
        MainActor.assumeIsolated {
            undoManager?.removeAllActions(withTarget: target)
        }
    }
}

@MainActor
final class ReaderViewportTransitionController: ObservableObject {
    weak var handler: ReaderViewportTransitionHandling?

    func begin(_ mode: ReaderViewportTransitionMode = .animatedChrome) {
        handler?.beginReadingViewportTransition(mode: mode)
    }

    func end() {
        handler?.endReadingViewportTransition()
    }
}

/// Records the drag that produced a selection. PDFKit posts the selection
/// from inside `mouseDragged` / `mouseUp`, so the points are stored before
/// `super` runs.
private final class SelectionTrackingPDFView: PDFView {
    var onGesture: ((PDFSelectionGesture?) -> Void)?
    private var anchor: (page: Int, point: CGPoint)?

    override func mouseDown(with event: NSEvent) {
        anchor = pagePoint(for: event)
        onGesture?(nil)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        publishGesture(to: event)
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        publishGesture(to: event)
        super.mouseUp(with: event)
    }

    private func publishGesture(to event: NSEvent) {
        guard let anchor, let current = pagePoint(for: event) else { return }
        onGesture?(
            PDFSelectionGesture(
                startPage: anchor.page,
                startPoint: anchor.point,
                endPage: current.page,
                endPoint: current.point
            )
        )
    }

    private func pagePoint(for event: NSEvent) -> (page: Int, point: CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true),
              let document else { return nil }
        let index = document.index(for: page)
        guard index != NSNotFound else { return nil }
        return (index, convert(viewPoint, to: page))
    }
}

// MARK: - PDFKit NSViewRepresentable
struct PDFKitView: NSViewRepresentable {
    let filePath: String
    let savedPage: Int
    let savedScrollOffset: Double
    let onPageChange: (Int, Double) -> Void
    let onVisibleTopChanged: (Int, Double) -> Void
    /// word, sentence, overallBounds, perLineBoundsStr, pageIndex, menuAnchor, selectionAnchorRect, pageMarkups
    let onTextSelected: (SelectionInfo) -> Void
    let onClearSelection: () -> Void
    let onDocumentLoaded: (Int) -> Void
    let translationSelection: TranslationSelectionEmphasis?
    /// The selection moved on screen. The translation itself is unchanged.
    let onTranslationAnchorMoved: (CGRect) -> Void
    let noteAnchorRequests: [NoteAnchorRequest]
    let onNoteAnchorsChanged: ([NoteAnchorPosition]) -> Void
    let viewportTransitionController: ReaderViewportTransitionController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = SelectionTrackingPDFView()
        pdfView.onGesture = { [weak coordinator = context.coordinator] gesture in
            coordinator?.selectionGesture = gesture
        }
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                       name: .PDFViewPageChanged, object: pdfView)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged(_:)),
                       name: .PDFViewSelectionChanged, object: pdfView)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.viewportGeometryChanged(_:)),
                       name: .PDFViewScaleChanged, object: pdfView)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.outlineNavigate(_:)),
                       name: .outlineNavigate, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.jumpToPage(_:)),
                       name: .jumpToPage, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.jumpToSelectionBounds(_:)),
                       name: .jumpToSelectionBounds, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.highlightSearchQuery(_:)),
                       name: .highlightSearchQuery, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.restoreReadingViewport(_:)),
                       name: .restoreReadingViewport, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addHighlight(_:)),
                       name: .addHighlight, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.removeHighlight(_:)),
                       name: .removeHighlight, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addFreeAnnotation(_:)),
                       name: .addFreeAnnotation, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addUnderlineNote(_:)),
                       name: .addUnderlineNote, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.removeUnderlineNote(_:)),
                       name: .removeUnderlineNote, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.savePositionNow(_:)),
                       name: .saveReadingPositionNow, object: nil)
        // App-level: save on quit
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.appWillTerminate(_:)),
                       name: NSApplication.willTerminateNotification, object: nil)
        // Window-level: save before miniaturize, restore after deminiaturize.
        // object: nil = observe ANY window; the handler verifies it's our window.
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.windowWillMiniaturize(_:)),
                       name: NSWindow.willMiniaturizeNotification, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.windowDidDeminiaturize(_:)),
                       name: NSWindow.didDeminiaturizeNotification, object: nil)

        context.coordinator.pdfView = pdfView
        viewportTransitionController.handler = context.coordinator
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.configureUndoHistory()
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Use coordinator's stored filePath (not documentURL?.path) because
        // Security-Scoped Bookmark-resolved URLs can differ from the original path.
        context.coordinator.parent = self
        viewportTransitionController.handler = context.coordinator
        context.coordinator.attachViewportObserverIfNeeded()
        context.coordinator.configureUndoHistory()
        guard context.coordinator.currentFilePath != filePath else {
            context.coordinator.syncTranslationSelection(translationSelection, in: pdfView)
            context.coordinator.publishNoteAnchors()
            return
        }
        guard let doc = Self.loadDocument(filePath: filePath) else { return }
        context.coordinator.prepareForDocumentChange()
        context.coordinator.persistViewportState()
        context.coordinator.currentFilePath = filePath
        let storedViewport = ReadingRestorationStore.shared.viewport(for: filePath)
        context.coordinator.beginViewportRestore(
            pageIndex: ReadingViewportCommit.restorePageIndex(
                viewport: storedViewport,
                savedPage: savedPage
            ),
            scrollOffset: savedScrollOffset,
            viewportState: storedViewport
        )
        pdfView.document = doc
        onDocumentLoaded(doc.pageCount)
        context.coordinator.applyHighlights(to: doc, filePath: filePath)
        context.coordinator.syncTranslationSelection(translationSelection, in: pdfView)
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.applyInitialViewportRestore(to: pdfView)
        }

        // PDFKit may finish installing or replace its internal scroll view after assigning
        // the document. Re-attach on the next run loop so viewport changes keep publishing
        // SwiftUI note-anchor coordinates even when no PDF page-change notification fires.
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.attachViewportObserverIfNeeded()
            coordinator?.publishNoteAnchors()
        }
        context.coordinator.publishNoteAnchors()
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// Load a PDFDocument, with security-scoped bookmark fallback for sandboxed apps.
    static func loadDocument(filePath: String) -> PDFDocument? {
        let url = URL(fileURLWithPath: filePath)
        if let doc = PDFDocument(url: url) { return doc }
        if let data = UserDefaults.standard.data(forKey: "bm_\(filePath)") {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                _ = resolved.startAccessingSecurityScopedResource()
                if let doc = PDFDocument(url: resolved) { return doc }
            }
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                return PDFDocument(url: resolved)
            }
        }
        return nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ReaderViewportTransitionHandling {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        var selectionGesture: PDFSelectionGesture?
        private var selectionDebounce: Timer?
        private var anchorFollowScheduled = false
        private var scrollDebounce: Timer?
        private var annotationSaveDebounce: Timer?
        private var activeTranslationSelectionID: UUID?
        private weak var translationSelectionView: TranslationSelectionEmphasisView?
        /// True while this coordinator is writing PDFKit's selection. That write
        /// posts selection and bounds notifications, which are not user actions.
        private var isApplyingTranslationSelection = false
        private var translationSelectionApplyToken = 0
        private weak var observedViewport: NSClipView?
        private weak var observedScrollView: NSScrollView?
        private weak var managedUndoManager: UndoManager?
        private var didTearDown = false
        var isJumping = false
        /// The file path of the currently loaded document.
        /// Stored explicitly so we never rely on `documentURL?.path`,
        /// which differs from the original path when loaded via a Security-Scoped Bookmark.
        var currentFilePath: String = ""
        /// Last page index the user was actually on — used to restore after window deminiaturize.
        var lastKnownPageIndex: Int = 0
        /// Normalized vertical scroll (0…1), kept in sync with saves.
        var lastScrollOffset: Double = 0
        /// Complete per-document PDFKit viewport state, including manual zoom and horizontal pan.
        private var lastViewportState: ReadingRestorationState.PDFViewport?
        private var isRestoringViewport = false
        private var isApplyingRestorePass = false
        private var isRestorePassScheduled = false
        /// Viewport captured before a reader chrome resize. While it is present,
        /// PDFKit layout changes are kept pinned to the same reading position.
        private var layoutTransitionViewport: ReadingRestorationState.PDFViewport?
        private var layoutTransitionMode: ReaderViewportTransitionMode?
        private var isApplyingLayoutTransitionViewport = false
        /// While non-nil, ignore spurious `pageChanged` / scroll-save until we reach this page (document load).
        var pendingRestoreTargetPage: Int?
        /// Last time a scroll, key, or scrollbar drag moved the viewport. Momentum shortly
        /// after that still counts as the user; a later close-time page jump does not.
        private var lastUserScrollAt: TimeInterval = 0
        private var lastPublishedOutlinePage: Int = -1
        private var lastPublishedOutlineY: Double = .nan
        private var pendingRestoreTimeoutWorkItem: DispatchWorkItem?
        /// Reading position is re-applied on this schedule after the document is assigned,
        /// because PDFKit keeps re-laying out until the restored window frame and split widths
        /// settle. The last pass must stay well inside the restore timeout below.
        private static let restoreRetryDelays: [TimeInterval] = [0.05, 0.15, 0.3, 0.5, 0.8]
        private static let restoreCompletionDelay: TimeInterval = 1.1
        private static let restoreTimeout: TimeInterval = 2.0

        init(_ parent: PDFKitView) {
            self.parent = parent
            self.lastKnownPageIndex = parent.savedPage
            self.lastScrollOffset = parent.savedScrollOffset
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            selectionDebounce?.invalidate()
            scrollDebounce?.invalidate()
            annotationSaveDebounce?.invalidate()
            pendingRestoreTimeoutWorkItem?.cancel()
        }

        @discardableResult
        func configureUndoHistory() -> UndoManager? {
            guard let undoManager = pdfView?.undoManager else { return nil }
            if managedUndoManager !== undoManager {
                ReaderUndoHistoryPolicy.clearActions(for: self, from: managedUndoManager)
                managedUndoManager = undoManager
            }
            ReaderUndoHistoryPolicy.configure(undoManager)
            return undoManager
        }

        func prepareForDocumentChange() {
            clearTranslationSelection()
            annotationSaveDebounce?.invalidate()
            annotationSaveDebounce = nil
            persistFreeMarkups()
            ReaderUndoHistoryPolicy.clearActions(for: self, from: configureUndoHistory())
        }

        func tearDown() {
            guard !didTearDown else { return }
            didTearDown = true
            publishCommittedPage()
            clearTranslationSelection()
            annotationSaveDebounce?.invalidate()
            annotationSaveDebounce = nil
            persistFreeMarkups()
            ReaderUndoHistoryPolicy.clearActions(for: self, from: managedUndoManager)
            NotificationCenter.default.removeObserver(self)
            selectionDebounce?.invalidate()
            scrollDebounce?.invalidate()
            pendingRestoreTimeoutWorkItem?.cancel()
            MainActor.assumeIsolated {
                if parent.viewportTransitionController.handler === self {
                    parent.viewportTransitionController.handler = nil
                }
            }
        }

        func attachViewportObserverIfNeeded() {
            guard let pdfView,
                  let scrollView = Self.scrollView(for: pdfView) else {
                return
            }
            attachLiveScrollObserverIfNeeded(to: scrollView)
            let viewport = scrollView.contentView
            guard observedViewport !== viewport else { return }

            if let observedViewport {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedViewport
                )
            }
            viewport.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewportBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: viewport
            )
            observedViewport = viewport
        }

        private func attachLiveScrollObserverIfNeeded(to scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else { return }
            if let observedScrollView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSScrollView.willStartLiveScrollNotification,
                    object: observedScrollView
                )
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(userWillStartLiveScroll(_:)),
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView
            )
            observedScrollView = scrollView
        }

        private static func embeddedScrollView(in view: NSView) -> NSScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? NSScrollView {
                    return scrollView
                }
                if let nested = embeddedScrollView(in: subview) {
                    return nested
                }
            }
            return nil
        }

        private static func scrollView(for pdfView: PDFView) -> NSScrollView? {
            embeddedScrollView(in: pdfView) ?? pdfView.enclosingScrollView
        }

        /// Persist free-form markups (highlights / underlines) to the app-side store.
        ///
        /// This never writes back into the user's PDF — it only updates `UserDefaults`, which is
        /// cheap and main-thread-safe, so it can run immediately after every edit without freezing
        /// the UI. Vocabulary and note annotations persist independently via the database.
        func triggerAnnotationSave(immediate: Bool = false) {
            annotationSaveDebounce?.invalidate()
            if immediate {
                persistFreeMarkups()
            } else {
                annotationSaveDebounce = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.persistFreeMarkups()
                }
            }
        }

        /// Rebuild the free-markup store from the annotations currently live on the document.
        private func persistFreeMarkups() {
            guard let doc = pdfView?.document, !currentFilePath.isEmpty else { return }
            var items: [FreeMarkupStore.Item] = []
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index) else { continue }
                for ann in page.annotations {
                    guard let tag = ann.userName, tag == "__fh" || tag == "__fu" else { continue }
                    let rects = PDFHighlightAnnotationFactory.lineRects(from: ann)
                    guard !rects.isEmpty else { continue }
                    let boundsStr = rects.map { NSStringFromRect($0) }.joined(separator: "|")
                    items.append(.init(
                        page: index,
                        boundsStr: boundsStr,
                        type: tag == "__fu" ? "underline" : "highlight"
                    ))
                }
            }
            FreeMarkupStore.save(currentFilePath, items: items)
        }

        func schedulePendingRestoreTimeout() {
            pendingRestoreTimeoutWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingRestoreTargetPage = nil
                self?.isRestoringViewport = false
            }
            pendingRestoreTimeoutWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreTimeout, execute: work)
        }

        fileprivate func beginViewportRestore(
            pageIndex: Int,
            scrollOffset: Double,
            viewportState: ReadingRestorationState.PDFViewport?
        ) {
            pendingRestoreTargetPage = pageIndex
            lastKnownPageIndex = pageIndex
            lastScrollOffset = scrollOffset
            lastViewportState = viewportState
            isRestoringViewport = true
            schedulePendingRestoreTimeout()
        }

        func applyInitialViewportRestore(to pdfView: PDFView) {
            guard isRestoringViewport,
                  let document = pdfView.document else { return }
            applyZoomState(lastViewportState, to: pdfView)
            if lastKnownPageIndex >= 0,
               lastKnownPageIndex < document.pageCount,
               let page = document.page(at: lastKnownPageIndex) {
                pdfView.go(to: page)
            }
            applyRestorePass(to: pdfView)

            for delay in Self.restoreRetryDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak pdfView] in
                    guard let self, let pdfView, self.isRestoringViewport else { return }
                    self.applyRestorePass(to: pdfView)
                }
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.restoreCompletionDelay
            ) { [weak self, weak pdfView] in
                guard let self, let pdfView, self.isRestoringViewport else { return }
                self.applyRestorePass(to: pdfView)
                self.finishViewportRestore(in: pdfView)
            }
        }

        /// Re-applies zoom and reading position while PDFKit is still settling.
        ///
        /// The window frame, the split widths, and the auto-scale factor all keep changing for
        /// a moment after launch, and every change re-lays out the document underneath us.
        private func applyRestorePass(to pdfView: PDFView) {
            guard !isApplyingRestorePass else { return }
            isApplyingRestorePass = true
            defer { isApplyingRestorePass = false }

            applyZoomState(lastViewportState, to: pdfView)
            applySavedScrollPosition(to: pdfView)
        }

        /// Explicit navigation supersedes a restore that is still settling. Without clearing the
        /// restore flag the pending passes would pull the reader back off the requested page and
        /// position saves would stay suppressed.
        private func cancelPendingViewportRestore() {
            pendingRestoreTimeoutWorkItem?.cancel()
            pendingRestoreTimeoutWorkItem = nil
            pendingRestoreTargetPage = nil
            isRestoringViewport = false
        }

        private func scheduleRestorePassAfterLayoutChange() {
            guard isRestoringViewport, !isRestorePassScheduled else { return }
            isRestorePassScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRestorePassScheduled = false
                guard self.isRestoringViewport, let pdfView = self.pdfView else { return }
                self.applyRestorePass(to: pdfView)
            }
        }

        func persistViewportState() {
            noteStableViewportFromLiveView()
            guard !currentFilePath.isEmpty, let viewport = lastViewportState else { return }
            ReadingRestorationStore.shared.updateViewport(viewport, for: currentFilePath)
            if let page = ReadingViewportCommit.pageIndex(of: viewport) {
                lastKnownPageIndex = page
            }
            lastScrollOffset = viewport.verticalOffset
        }

        /// Writes the stable viewport and the SQLite page for the document this view owns.
        private func publishCommittedPage() {
            scrollDebounce?.invalidate()
            scrollDebounce = nil
            persistViewportState()
            guard !currentFilePath.isEmpty else { return }
            parent.onPageChange(lastKnownPageIndex, lastScrollOffset)
        }

        private func noteStableViewportFromLiveView() {
            guard let pdfView,
                  let live = Self.captureViewportState(from: pdfView) else { return }
            let flags = viewportUpdateFlags()
            lastViewportState = ReadingViewportCommit.accepting(
                stable: lastViewportState,
                live: live,
                userScrollEvent: flags.userScrollEvent,
                recentUserScroll: flags.recentUserScroll
            )
            publishOutlinePositionIfNeeded()
        }

        private func publishOutlinePositionIfNeeded() {
            guard let pdfView,
                  let scrollView = Self.scrollView(for: pdfView),
                  let documentView = scrollView.documentView,
                  let focus = Self.capturePagePoint(
                      ReaderViewportGeometry.outlineFocusPoint(
                          in: scrollView.documentVisibleRect,
                          isDocumentFlipped: documentView.isFlipped
                      ),
                      from: pdfView,
                      documentView: documentView
                  ) else { return }
            if focus.pageIndex == lastPublishedOutlinePage,
               abs(focus.y - lastPublishedOutlineY) < 1 {
                return
            }
            lastPublishedOutlinePage = focus.pageIndex
            lastPublishedOutlineY = focus.y
            parent.onVisibleTopChanged(focus.pageIndex, focus.y)
        }

        private func viewportUpdateFlags() -> (userScrollEvent: Bool, recentUserScroll: Bool) {
            let now = ProcessInfo.processInfo.systemUptime
            var userScrollEvent = false
            if let type = NSApp.currentEvent?.type {
                switch type {
                case .scrollWheel, .magnify, .swipe, .keyDown, .leftMouseDragged:
                    userScrollEvent = true
                    lastUserScrollAt = now
                default:
                    break
                }
            }
            return (userScrollEvent, now - lastUserScrollAt < 1)
        }

        private func finishViewportRestore(in pdfView: PDFView) {
            pendingRestoreTimeoutWorkItem?.cancel()
            pendingRestoreTargetPage = nil
            isRestoringViewport = false

            guard pdfView.document != nil, pdfView.currentPage != nil else { return }
            publishCommittedPage()
            publishNoteAnchors()
        }

        private func applySavedScrollPosition(to pdfView: PDFView) {
            if let lastViewportState {
                Self.applyViewportOffsets(lastViewportState, to: pdfView)
            } else {
                Self.applyNormalizedScrollOffset(lastScrollOffset, to: pdfView)
            }
        }

        private func applyZoomState(
            _ state: ReadingRestorationState.PDFViewport?,
            to pdfView: PDFView
        ) {
            guard let state else {
                pdfView.autoScales = true
                return
            }
            if state.autoScales {
                pdfView.autoScales = true
                return
            }

            pdfView.autoScales = false
            let minimum = pdfView.minScaleFactor > 0 ? pdfView.minScaleFactor : 0.1
            let maximum = pdfView.maxScaleFactor > minimum ? pdfView.maxScaleFactor : 10
            pdfView.scaleFactor = min(max(CGFloat(state.scaleFactor), minimum), maximum)
        }

        private static func captureViewportState(
            from pdfView: PDFView
        ) -> ReadingRestorationState.PDFViewport? {
            guard let scrollView = scrollView(for: pdfView),
                  let documentView = scrollView.documentView else { return nil }
            let visibleRect = scrollView.documentVisibleRect
            // Closing a window collapses the reader before the app finishes quitting. Capturing
            // from that torn-down layout would replace a good reading position with the top of
            // the document, so leave the last stable capture in place instead.
            guard visibleRect.width > 1,
                  visibleRect.height > 1,
                  documentView.bounds.height > 1 else { return nil }
            let maxX = max(0, documentView.bounds.width - visibleRect.width)
            let maxY = max(0, documentView.bounds.height - visibleRect.height)
            let anchor = captureAnchor(from: pdfView, scrollView: scrollView, documentView: documentView)
            let currentPageIndex = pdfView.currentPage.flatMap { page in
                pdfView.document?.index(for: page)
            }
            return ReadingRestorationState.PDFViewport(
                pageIndex: anchor?.pageIndex ?? currentPageIndex,
                autoScales: pdfView.autoScales,
                scaleFactor: Double(pdfView.scaleFactor),
                horizontalOffset: maxX > 0 ? Double(visibleRect.minX / maxX) : 0,
                verticalOffset: maxY > 0 ? Double(visibleRect.minY / maxY) : 0,
                anchor: anchor
            )
        }

        private static func captureAnchor(
            from pdfView: PDFView,
            scrollView: NSScrollView,
            documentView: NSView
        ) -> ReadingRestorationState.PDFViewport.PageAnchor? {
            guard let document = pdfView.document else { return nil }
            let topLeftInDocument = ReaderViewportGeometry.visibleTopLeft(
                of: scrollView.documentVisibleRect,
                isDocumentFlipped: documentView.isFlipped
            )
            return capturePagePoint(topLeftInDocument, from: pdfView, documentView: documentView)
        }

        private static func capturePagePoint(
            _ pointInDocument: CGPoint,
            from pdfView: PDFView,
            documentView: NSView
        ) -> ReadingRestorationState.PDFViewport.PageAnchor? {
            guard let document = pdfView.document else { return nil }
            let pointInPDFView = pdfView.convert(pointInDocument, from: documentView)
            guard let page = pdfView.page(for: pointInPDFView, nearest: true) else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            let pointInPage = pdfView.convert(pointInPDFView, to: page)
            let anchor = ReadingRestorationState.PDFViewport.PageAnchor(
                pageIndex: pageIndex,
                x: Double(pointInPage.x),
                y: Double(pointInPage.y)
            )
            return anchor.isValid ? anchor : nil
        }

        private static func applyViewportOffsets(
            _ state: ReadingRestorationState.PDFViewport,
            to pdfView: PDFView
        ) {
            guard let scrollView = scrollView(for: pdfView),
                  let documentView = scrollView.documentView,
                  let point = targetScrollOrigin(
                      for: state,
                      in: pdfView,
                      scrollView: scrollView,
                      documentView: documentView
                  ) else { return }
            let currentPoint = scrollView.contentView.bounds.origin
            guard abs(currentPoint.x - point.x) > 0.5
                    || abs(currentPoint.y - point.y) > 0.5 else { return }
            scrollView.contentView.scroll(to: point)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private static func targetScrollOrigin(
            for state: ReadingRestorationState.PDFViewport,
            in pdfView: PDFView,
            scrollView: NSScrollView,
            documentView: NSView
        ) -> NSPoint? {
            let visibleSize = scrollView.documentVisibleRect.size
            let documentSize = documentView.bounds.size
            guard documentSize.height > 0 else { return nil }

            if let anchorPoint = anchorPointInDocument(
                state.anchor,
                in: pdfView,
                documentView: documentView
            ) {
                return ReaderViewportGeometry.scrollOrigin(
                    visibleTopLeft: anchorPoint,
                    visibleSize: visibleSize,
                    documentSize: documentSize,
                    isDocumentFlipped: documentView.isFlipped
                )
            }

            return ReaderViewportGeometry.scrollOrigin(
                normalizedHorizontal: state.horizontalOffset,
                normalizedVertical: state.verticalOffset,
                visibleSize: visibleSize,
                documentSize: documentSize
            )
        }

        private static func anchorPointInDocument(
            _ anchor: ReadingRestorationState.PDFViewport.PageAnchor?,
            in pdfView: PDFView,
            documentView: NSView
        ) -> NSPoint? {
            guard let anchor,
                  anchor.isValid,
                  let document = pdfView.document,
                  anchor.pageIndex < document.pageCount,
                  let page = document.page(at: anchor.pageIndex) else { return nil }
            let pointInPage = NSPoint(x: CGFloat(anchor.x), y: CGFloat(anchor.y))
            let pointInPDFView = pdfView.convert(pointInPage, from: page)
            let pointInDocument = documentView.convert(pointInPDFView, from: pdfView)
            guard pointInDocument.x.isFinite, pointInDocument.y.isFinite else { return nil }
            return pointInDocument
        }

        /// Inverse of `scrollOffset(for:)` — restores vertical position in continuous scroll mode.
        static func applyNormalizedScrollOffset(_ normalized: Double, to pdfView: PDFView) {
            guard let sv = scrollView(for: pdfView), let dv = sv.documentView else { return }
            let h = dv.bounds.height
            guard h > 0 else { return }
            let y = CGFloat(max(0, min(1, normalized))) * h
            let visibleH = sv.documentVisibleRect.height
            let maxY = max(0, h - visibleH)
            sv.contentView.scroll(to: NSPoint(x: 0, y: min(y, maxY)))
        }

        // MARK: Outline / page navigation

        @objc func outlineNavigate(_ notification: Notification) {
            guard let idx   = notification.userInfo?["pageIndex"] as? Int,
                  let path  = notification.userInfo?["filePath"]  as? String,
                  path == currentFilePath,
                  let pdfView,
                  let page  = pdfView.document?.page(at: idx)
            else { return }
            cancelPendingViewportRestore()
            pdfView.go(to: page)
        }

        // MARK: Vocab highlights

        @objc func addHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let boundsStr = notification.userInfo?["boundsStr"]  as? String,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            addVocabAnnotation(entryId: entryId, boundsStr: boundsStr, to: page)
        }

        @objc func removeHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            let marker = "vocab:\(entryId)"
            page.annotations
                .filter { $0.userName == entryId || $0.contents == marker }
                .forEach { page.removeAnnotation($0) }
            triggerAnnotationSave(immediate: true)
        }

        // MARK: Free annotations (highlight / underline) with toggle + merge

        /// Snapshot for undo/redo of free-form highlight/underline (not vocabulary-linked).
        /// Subtype is derived from `tag` (`__fu` = underline, `__fh` = highlight).
        private struct FreeAnnotationSnapshot {
            let lineRects: [CGRect]
            let color: NSColor
            let tag: String
            let contents: String?
            init(ann: PDFAnnotation) {
                lineRects = PDFHighlightAnnotationFactory.lineRects(from: ann)
                tag = ann.userName ?? ""
                color = tag == "__fu"
                    ? PDFMarkupAppearance.underlineColor
                    : (ann.color as NSColor?) ?? PDFHighlightAnnotationFactory.nativeHighlightColor
                contents = ann.contents
            }
            var subtype: PDFAnnotationSubtype {
                tag == "__fu" ? .underline : .highlight
            }
            var bounds: CGRect {
                lineRects.dropFirst().reduce(lineRects.first ?? .zero) { $0.union($1) }
            }
        }

        @objc func addFreeAnnotation(_ notification: Notification) {
            guard let typeStr = notification.userInfo?["annotationType"] as? String,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView
            else { return }

            guard let targets = Self.annotationTargets(from: notification.userInfo) else { return }

            let undoManager = configureUndoHistory()
            undoManager?.beginUndoGrouping()
            defer { undoManager?.endUndoGrouping() }
            for (pageIndex, boundsStr) in targets {
                guard let page = pdfView.document?.page(at: pageIndex) else { continue }
                let lineRects = Self.parseAnnotationRects(boundsStr)
                guard !lineRects.isEmpty else { continue }
                applyFreeAnnotation(type: typeStr, page: page, lineRects: lineRects)
            }
            publishNoteAnchors()
        }

        private func applyFreeAnnotation(type typeStr: String, page: PDFPage, lineRects: [CGRect]) {
            let isHighlight = typeStr == "highlight"
            applyResolvedFreeMarkup(
                page: page,
                lineRects: lineRects,
                type: isHighlight ? .highlight : .underline,
                color: isHighlight
                    ? PDFHighlightAnnotationFactory.nativeHighlightColor
                    : PDFMarkupAppearance.underlineColor,
                tag: isHighlight ? "__fh" : "__fu",
                contents: isHighlight ? "free:highlight" : "free:underline",
                undoLabel: isHighlight ? "高亮" : "划线"
            )
        }

        private func applyResolvedFreeMarkup(
            page: PDFPage,
            lineRects: [CGRect],
            type: PDFAnnotationSubtype,
            color: NSColor,
            tag: String,
            contents: String,
            undoLabel: String
        ) {
            let existing = freeMarkupAnnotations(on: page, tag: tag, contents: contents, type: type)
            let groups = existing.map { PDFHighlightAnnotationFactory.lineRects(from: $0) }
            let plan = TextLineMarkupMerge.plan(existingGroups: groups, selection: lineRects)

            var removedSnapshots: [FreeAnnotationSnapshot] = []
            for index in plan.interactingGroupIndices {
                let annotation = existing[index]
                removedSnapshots.append(FreeAnnotationSnapshot(ann: annotation))
                page.removeAnnotation(annotation)
            }

            var added: [PDFAnnotation] = []
            if !plan.addRects.isEmpty {
                added.append(contentsOf: Self.makeMarkupAnnotations(
                    lineRects: plan.addRects,
                    selection: nil,
                    type: type,
                    color: color,
                    tag: tag,
                    page: page,
                    contents: contents
                ))
            }

            if !added.isEmpty || !removedSnapshots.isEmpty {
                registerUndoAnnotationMutation(
                    page: page,
                    added: added,
                    removedSnapshots: removedSnapshots,
                    label: undoLabel
                )
                triggerAnnotationSave(immediate: true)
            }
        }

        private func freeMarkupAnnotations(
            on page: PDFPage,
            tag: String,
            contents: String,
            type: PDFAnnotationSubtype
        ) -> [PDFAnnotation] {
            page.annotations.filter { annotation in
                PDFHighlightAnnotationFactory.matchesSubtype(annotation, type)
                    && (annotation.userName == tag || annotation.contents == contents)
            }
        }

        private func registerUndoAnnotationMutation(
            page: PDFPage,
            added: [PDFAnnotation],
            removedSnapshots: [FreeAnnotationSnapshot],
            label: String
        ) {
            guard let undo = configureUndoHistory() else { return }
            let addedSnaps = added.map { FreeAnnotationSnapshot(ann: $0) }

            undo.registerUndo(withTarget: self) { [weak self] _ in
                guard let self else { return }
                for ann in added {
                    page.removeAnnotation(ann)
                }
                var restored: [PDFAnnotation] = []
                for snap in removedSnapshots {
                    restored.append(Self.makeAnnotation(from: snap, page: page))
                }
                self.registerRedoAnnotationMutation(
                    page: page,
                    restoredRemoved: restored,
                    readdSnapshots: addedSnaps,
                    label: label
                )
                self.triggerAnnotationSave(immediate: true)
                self.publishNoteAnchors()
            }
            undo.setActionName(label)
        }

        private func registerRedoAnnotationMutation(
            page: PDFPage,
            restoredRemoved: [PDFAnnotation],
            readdSnapshots: [FreeAnnotationSnapshot],
            label: String
        ) {
            guard let undo = configureUndoHistory() else { return }
            let snapshotsOfRestored = restoredRemoved.map { FreeAnnotationSnapshot(ann: $0) }

            undo.registerUndo(withTarget: self) { [weak self] _ in
                guard let self else { return }
                for ann in restoredRemoved {
                    page.removeAnnotation(ann)
                }
                var readded: [PDFAnnotation] = []
                for snap in readdSnapshots {
                    readded.append(Self.makeAnnotation(from: snap, page: page))
                }
                self.registerUndoAnnotationMutation(
                    page: page,
                    added: readded,
                    removedSnapshots: snapshotsOfRestored,
                    label: label
                )
                self.triggerAnnotationSave(immediate: true)
                self.publishNoteAnchors()
            }
            undo.setActionName(label)
        }

        private static func makeAnnotation(from snap: FreeAnnotationSnapshot, page: PDFPage) -> PDFAnnotation {
            let contents = snap.contents ?? (snap.tag == "__fu" ? "free:underline" : "free:highlight")
            if let restored = makeMarkupAnnotations(
                lineRects: snap.lineRects,
                selection: nil,
                type: snap.subtype,
                color: snap.color,
                tag: snap.tag,
                page: page,
                contents: contents
            ).first {
                return restored
            }
            let bounds = snap.bounds
            return makeAnnotation(bounds: bounds, type: snap.subtype, color: snap.color, tag: snap.tag, page: page, contents: contents)
        }

        // MARK: Underline note (划线 + 笔记)

        /// 添加划线笔记（划线 + 自动保存到笔记，支持撤销）
        @objc func addUnderlineNote(_ notification: Notification) {
            guard let noteId = notification.userInfo?["noteId"] as? String,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let document = pdfView.document
            else { return }

            guard let targets = Self.annotationTargets(from: notification.userInfo) else { return }

            // Merge payload: partial-overlap saves delete old notes and recreate one expanded note.
            let deletedNoteIds = notification.userInfo?["deletedNoteIds"] as? [String] ?? []
            let deletedNotesInfo = notification.userInfo?["deletedNotesInfo"] as? [NoteUndoInfo] ?? []
            let newNoteInfo = notification.userInfo?["newNoteInfo"] as? NoteUndoInfo

            removeNoteAnnotations(ids: Set(deletedNoteIds), from: document)
            addNoteAnnotations(noteId: noteId, targets: targets, to: document)
            publishNoteAnchors()

            if let newNoteInfo {
                registerNoteHistoryTransition(
                    current: [newNoteInfo],
                    previous: deletedNotesInfo,
                    label: "划线笔记"
                )
            }
        }

        private func registerNoteHistoryTransition(
            current: [NoteUndoInfo],
            previous: [NoteUndoInfo],
            label: String
        ) {
            guard let undo = configureUndoHistory() else { return }
            undo.registerUndo(withTarget: self) { coordinator in
                coordinator.applyNoteHistoryTransition(
                    removing: current,
                    restoring: previous,
                    label: label
                )
            }
            undo.setActionName(label)
        }

        private func applyNoteHistoryTransition(
            removing: [NoteUndoInfo],
            restoring: [NoteUndoInfo],
            label: String
        ) {
            guard let pdfView,
                  let document = pdfView.document,
                  (removing + restoring).allSatisfy({ $0.pdfPath == currentFilePath })
            else { return }

            do {
                try ReaderPersistence.shared.applyNoteHistorySnapshot(
                    removing: removing,
                    restoring: restoring
                )
            } catch {
                _ = pdfView.presentError(error)
                return
            }

            removeNoteAnnotations(ids: Set(removing.map(\.id)), from: document)
            for info in restoring {
                addNoteAnnotations(
                    noteId: info.id,
                    targets: noteTargets(for: info),
                    to: document
                )
            }
            publishNoteAnchors()
            ReaderEventBus.shared.postRefreshNotesList()

            registerNoteHistoryTransition(
                current: restoring,
                previous: removing,
                label: label
            )
        }

        private func noteTargets(for info: NoteUndoInfo) -> [(Int, String)] {
            let markups = PDFPageMarkupCodec.normalized(info.pageMarkups)
            if !markups.isEmpty {
                return markups.map { ($0.pageIndex, $0.boundsStr) }
            }
            return [(Int(info.pageIndex), info.boundsStr)]
        }

        private func addNoteAnnotations(
            noteId: String,
            targets: [(Int, String)],
            to document: PDFDocument
        ) {
            for (pageIndex, boundsStr) in targets {
                guard let page = document.page(at: pageIndex) else { continue }
                for rect in Self.parseAnnotationRects(boundsStr) {
                    page.addAnnotation(PDFMarkupAppearance.makeUnderline(
                        bounds: rect,
                        userName: noteId,
                        contents: "note:\(noteId)"
                    ))
                }
            }
        }

        private func removeNoteAnnotations(ids: Set<String>, from document: PDFDocument) {
            guard !ids.isEmpty else { return }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                page.annotations
                    .filter { ids.contains($0.userName ?? "") }
                    .forEach { page.removeAnnotation($0) }
            }
        }

        /// 删除划线笔记时移除对应的划线标注
        @objc func removeUnderlineNote(_ notification: Notification) {
            guard let noteId = notification.userInfo?["noteId"] as? String,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let document = pdfView.document
            else { return }

            removeNoteAnnotations(ids: [noteId], from: document)
            publishNoteAnchors()

            if let deletedNoteInfo = notification.userInfo?["deletedNoteInfo"] as? NoteUndoInfo {
                registerNoteHistoryTransition(
                    current: [],
                    previous: [deletedNoteInfo],
                    label: "删除笔记"
                )
            }
        }

        // MARK: Apply saved highlights on document load

        func applyHighlights(to doc: PDFDocument, filePath: String) {
            let undoWasEnabled = pdfView?.undoManager?.isUndoRegistrationEnabled ?? true
            pdfView?.undoManager?.disableUndoRegistration()
            defer {
                if undoWasEnabled {
                    pdfView?.undoManager?.enableUndoRegistration()
                }
            }

            // One-time migration: if we have no stored free markups yet but the freshly loaded PDF
            // contains some (baked in by older versions), seed the store before stripping so we
            // don't lose the user's existing free highlights/underlines.
            if FreeMarkupStore.load(filePath).isEmpty {
                persistFreeMarkups()
            }

            // Drop any app-managed annotations physically baked into the PDF by older versions, then
            // re-apply every kind from its own store so styling/color stays consistent and current.
            stripManagedAnnotations(from: doc)

            // Vocabulary highlights — source of truth: database.
            let entries = (try? ReaderPersistence.shared.listVocabulary()) ?? []
            for entry in entries where entry.pdfPath == filePath {
                guard let page = doc.page(at: Int(entry.pageIndex)) else { continue }
                addVocabAnnotation(
                    entryId: entry.id,
                    boundsStr: entry.selectionBounds,
                    to: page,
                    isRestore: true
                )
            }

            // Note-linked underlines — source of truth: database.
            let notes = (try? ReaderPersistence.shared.listNotesByPdf(pdfPath: filePath)) ?? []
            for note in notes {
                let markups = PDFPageMarkupCodec.decode(
                    note.pageMarkups,
                    fallbackPage: Int(note.pageIndex),
                    fallbackBoundsStr: note.boundsStr,
                    fallbackText: note.content
                )
                for markup in markups {
                    guard let page = doc.page(at: markup.pageIndex) else { continue }
                    restoreNoteUnderline(noteId: note.id, boundsStr: markup.boundsStr, on: page)
                }
            }

            // Free highlights / underlines — source of truth: FreeMarkupStore (UserDefaults).
            for item in FreeMarkupStore.load(filePath) {
                guard let page = doc.page(at: item.page) else { continue }
                restoreFreeMarkup(item, on: page)
            }
        }

        /// Remove vocabulary / note / free annotations that may be physically embedded in the PDF
        /// (written by older app versions). They are re-applied afterwards from app-side stores.
        private func stripManagedAnnotations(from doc: PDFDocument) {
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index) else { continue }
                let managed = page.annotations.filter { ann in
                    let tag = ann.userName ?? ""
                    let contents = ann.contents ?? ""
                    return tag == "__fh" || tag == "__fu"
                        || contents.hasPrefix("free:")
                        || contents.hasPrefix("vocab:")
                        || contents.hasPrefix("note:")
                }
                managed.forEach { page.removeAnnotation($0) }
            }
        }

        private func restoreNoteUnderline(noteId: String, boundsStr: String, on page: PDFPage) {
            for rect in Self.parseAnnotationRects(boundsStr) {
                page.addAnnotation(
                    PDFMarkupAppearance.makeUnderline(
                        bounds: rect,
                        userName: noteId,
                        contents: "note:\(noteId)"
                    )
                )
            }
        }

        private func restoreFreeMarkup(_ item: FreeMarkupStore.Item, on page: PDFPage) {
            let lineRects = Self.parseAnnotationRects(item.boundsStr)
            guard !lineRects.isEmpty else { return }
            if item.type == "underline" {
                _ = Self.makeMarkupAnnotations(
                    lineRects: lineRects, selection: nil, type: .underline,
                    color: PDFMarkupAppearance.underlineColor,
                    tag: "__fu", page: page, contents: "free:underline"
                )
            } else {
                _ = Self.makeMarkupAnnotations(
                    lineRects: lineRects, selection: nil, type: .highlight,
                    color: PDFHighlightAnnotationFactory.nativeHighlightColor,
                    tag: "__fh", page: page, contents: "free:highlight"
                )
            }
        }

        private func pageHasVocabHighlight(entryId: String, on page: PDFPage) -> Bool {
            let marker = "vocab:\(entryId)"
            return page.annotations.contains { annotation in
                PDFHighlightAnnotationFactory.matchesSubtype(annotation, .highlight)
                    && (annotation.userName == entryId || annotation.contents == marker)
            }
        }

        private func addVocabAnnotation(
            entryId: String,
            boundsStr: String,
            to page: PDFPage,
            isRestore: Bool = false
        ) {
            guard !pageHasVocabHighlight(entryId: entryId, on: page) else { return }
            let lineRects = Self.parseAnnotationRects(boundsStr)
            guard let annotation = Self.makeHighlightAnnotation(
                lineRects: lineRects,
                selection: nil,
                page: page,
                userName: entryId,
                contents: "vocab:\(entryId)"
            ) else { return }
            page.addAnnotation(annotation)
            if !isRestore {
                triggerAnnotationSave(immediate: true)
            }
        }

        // MARK: Translation selection emphasis

        func syncTranslationSelection(
            _ emphasis: TranslationSelectionEmphasis?,
            in pdfView: PDFView
        ) {
            guard let emphasis,
                  emphasis.filePath == currentFilePath,
                  let document = pdfView.document else {
                clearTranslationSelection()
                return
            }

            let emphasisView: TranslationSelectionEmphasisView
            if let current = translationSelectionView {
                emphasisView = current
            } else {
                let created = TranslationSelectionEmphasisView(pdfView: pdfView)
                translationSelectionView = created
                emphasisView = created
            }
            pdfView.addSubview(emphasisView, positioned: .above, relativeTo: nil)
            emphasisView.update(markups: emphasis.pageMarkups)

            guard activeTranslationSelectionID != emphasis.id else { return }
            activeTranslationSelectionID = emphasis.id
            let selections = emphasis.pageMarkups.compactMap { markup -> PDFSelection? in
                guard let page = document.page(at: markup.pageIndex) else { return nil }
                return PDFHighlightAnnotationFactory.selection(
                    from: markup.lineRects,
                    on: page
                )
            }
            guard let selection = Self.combinedSelection(selections, in: document) else { return }
            selection.color = .clear
            translationSelectionApplyToken += 1
            let token = translationSelectionApplyToken
            isApplyingTranslationSelection = true
            pdfView.setCurrentSelection(selection, animate: false)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.translationSelectionApplyToken == token else { return }
                self.isApplyingTranslationSelection = false
            }
        }

        private func clearTranslationSelection() {
            guard activeTranslationSelectionID != nil || translationSelectionView != nil else {
                return
            }
            activeTranslationSelectionID = nil
            translationSelectionView?.removeFromSuperview()
            translationSelectionView = nil
            pdfView?.clearSelection()
        }

        private func refreshTranslationSelectionEmphasis() {
            translationSelectionView?.refresh()
        }

        // MARK: Page jump

        @objc func jumpToPage(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath  = notification.userInfo?["filePath"]  as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            cancelPendingViewportRestore()
            isJumping = true
            pdfView.go(to: page)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        @objc func highlightSearchQuery(_ notification: Notification) {
            guard let query = notification.userInfo?["query"] as? String,
                  let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let document = pdfView.document,
                  let page = document.page(at: pageIndex)
            else { return }

            cancelPendingViewportRestore()
            isJumping = true
            pdfView.go(to: page)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak pdfView, weak page, weak document] in
                guard let self, let pdfView, let page, let document else { return }
                guard let selection = Self.searchSelection(
                    matching: query,
                    on: page,
                    in: document
                ) else { return }
                pdfView.setCurrentSelection(selection, animate: true)
                let bounds = selection.bounds(for: page)
                self.center(rect: bounds, on: page, in: pdfView)
                self.flashFocus(rects: [bounds], on: page)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        private static func searchSelection(
            matching query: String,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PDFSelection? {
            let needles = searchNeedles(from: query)
            let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            for needle in needles {
                let matches = document.findString(needle, withOptions: options)
                let pageIndex = document.index(for: page)
                if let onPage = matches.first(where: { selection in
                    selection.pages.contains(where: { document.index(for: $0) == pageIndex })
                }) {
                    return onPage
                }
            }
            return nil
        }

        private static func searchNeedles(from query: String) -> [String] {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = WorkspaceSearchMatcher.tokens(in: trimmed)
            var needles: [String] = []
            if !trimmed.isEmpty { needles.append(trimmed) }
            if tokens.count > 1 {
                needles.append(tokens.joined(separator: " "))
            }
            if let first = tokens.first, first.count >= 2, !needles.contains(first) {
                needles.append(first)
            }
            return needles
        }

        @objc func restoreReadingViewport(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let scrollOffset = notification.userInfo?["scrollOffset"] as? Double,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }
            cancelPendingViewportRestore()
            isJumping = true
            pdfView.go(to: page)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak pdfView] in
                guard let pdfView else { return }
                Self.applyNormalizedScrollOffset(scrollOffset, to: pdfView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.isJumping = false
            }
        }

        func beginReadingViewportTransition(mode: ReaderViewportTransitionMode) {
            guard let pdfView,
                  let viewport = Self.captureViewportState(from: pdfView)
            else { return }

            scrollDebounce?.invalidate()
            layoutTransitionViewport = viewport
            layoutTransitionMode = mode
            if mode == .animatedChrome {
                maintainLayoutTransitionViewport(in: pdfView)
            }
        }

        func endReadingViewportTransition() {
            guard layoutTransitionViewport != nil,
                  let pdfView
            else { return }

            pdfView.layoutSubtreeIfNeeded()
            maintainLayoutTransitionViewport(in: pdfView, restorePageIfNeeded: true)
            layoutTransitionViewport = nil
            layoutTransitionMode = nil

            guard pdfView.currentPage != nil, pdfView.document != nil else { return }
            publishCommittedPage()
            publishNoteAnchors()
        }

        private func maintainLayoutTransitionViewport(
            in pdfView: PDFView,
            restorePageIfNeeded: Bool = false
        ) {
            guard let viewport = layoutTransitionViewport,
                  !isApplyingLayoutTransitionViewport else { return }

            isApplyingLayoutTransitionViewport = true
            defer { isApplyingLayoutTransitionViewport = false }

            if restorePageIfNeeded,
               let pageIndex = viewport.pageIndex,
               let document = pdfView.document,
               pageIndex >= 0,
               pageIndex < document.pageCount,
               pdfView.currentPage.map({ document.index(for: $0) }) != pageIndex,
               let page = document.page(at: pageIndex) {
                pdfView.go(to: page)
                pdfView.layoutSubtreeIfNeeded()
            }

            Self.applyViewportOffsets(viewport, to: pdfView)
        }

        @objc func jumpToSelectionBounds(_ notification: Notification) {
            guard let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let targets = Self.annotationTargets(from: notification.userInfo),
                  let primaryTarget = targets.first,
                  let pdfView,
                  let page = pdfView.document?.page(at: primaryTarget.0)
            else { return }

            cancelPendingViewportRestore()
            isJumping = true
            pdfView.go(to: page)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.focusSelection(targets: targets, in: pdfView)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        private func focusSelection(targets: [(Int, String)], in pdfView: PDFView) {
            guard let document = pdfView.document else { return }
            let resolved = targets.compactMap { pageIndex, boundsStr -> (PDFPage, [CGRect])? in
                let rects = Self.parseAnnotationRects(boundsStr)
                guard !rects.isEmpty, let page = document.page(at: pageIndex) else { return nil }
                return (page, rects)
            }
            guard let primary = resolved.first else { return }

            let selections = resolved.compactMap { page, rects in
                PDFHighlightAnnotationFactory.selection(from: rects, on: page)
            }
            if let selection = Self.combinedSelection(selections, in: document) {
                pdfView.setCurrentSelection(selection, animate: true)
            }

            let union = primary.1.reduce(CGRect.null) { partial, rect in
                partial.isNull ? rect : partial.union(rect)
            }
            guard !union.isNull, !union.isEmpty else { return }

            center(rect: union, on: primary.0, in: pdfView)
            resolved.forEach { page, rects in
                flashFocus(rects: rects, on: page)
            }
        }

        private static func combinedSelection(
            _ selections: [PDFSelection],
            in document: PDFDocument
        ) -> PDFSelection? {
            guard let first = selections.first else { return nil }
            guard selections.count > 1 else { return first }
            let combined = PDFSelection(document: document)
            combined.add(selections)
            return combined
        }

        private func center(rect: CGRect, on page: PDFPage, in pdfView: PDFView) {
            guard let scrollView = Self.scrollView(for: pdfView),
                  let documentView = scrollView.documentView else { return }
            let rectInPDFView = pdfView.convert(rect, from: page)
            let targetInDocument = pdfView.convert(rectInPDFView, to: documentView)
            let visibleSize = scrollView.contentView.bounds.size
            let targetOrigin = NSPoint(
                x: max(0, targetInDocument.midX - visibleSize.width / 2),
                y: max(0, targetInDocument.midY - visibleSize.height / 2)
            )
            scrollView.contentView.animator().scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func flashFocus(rects: [CGRect], on page: PDFPage) {
            let annotations = rects.compactMap { rect -> PDFAnnotation? in
                guard !rect.isEmpty, rect != .zero else { return nil }
                let ann = PDFAnnotation(bounds: rect.insetBy(dx: -2, dy: -2), forType: .highlight, withProperties: nil)
                ann.color = NSColor.controlAccentColor.withAlphaComponent(0.28)
                ann.userName = "__focus"
                ann.contents = "focus:reading-context"
                page.addAnnotation(ann)
                return ann
            }
            guard !annotations.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak page] in
                guard let page else { return }
                annotations.forEach { page.removeAnnotation($0) }
            }
        }

        // MARK: Reading position save

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            refreshTranslationSelectionEmphasis()
            let pageIndex = doc.index(for: currentPage)

            if let layoutTransitionMode {
                if layoutTransitionMode == .animatedChrome {
                    maintainLayoutTransitionViewport(in: pdfView)
                }
                return
            }

            if isRestoringViewport, let target = pendingRestoreTargetPage {
                if pageIndex != target {
                    guard viewportUpdateFlags().userScrollEvent else { return }
                    finishViewportRestore(in: pdfView)
                    return
                }
                lastKnownPageIndex = pageIndex
                return
            }

            publishCommittedPage()
            publishNoteAnchors()
        }

        /// The PDFKit clip view is the authoritative viewport signal. Unlike
        /// `didLiveScroll`, this also covers momentum and programmatic scrolling.
        @objc func viewportBoundsChanged(_ notification: Notification) {
            followTranslationAnchor()
            refreshTranslationSelectionEmphasis()
            if let layoutTransitionMode {
                if layoutTransitionMode == .animatedChrome, let pdfView {
                    maintainLayoutTransitionViewport(in: pdfView)
                }
                return
            }
            publishNoteAnchors()
            guard !isRestoringViewport else { return }
            noteStableViewportFromLiveView()
            scheduleViewportPersistence()
        }

        @objc func viewportGeometryChanged(_ notification: Notification) {
            attachViewportObserverIfNeeded()
            followTranslationAnchor()
            refreshTranslationSelectionEmphasis()
            if let layoutTransitionMode {
                if layoutTransitionMode == .animatedChrome, let pdfView {
                    maintainLayoutTransitionViewport(in: pdfView)
                }
                return
            }
            publishNoteAnchors()
            guard !isRestoringViewport else {
                // A scale change re-lays out the document, which moves the saved position out
                // from under the viewport; re-anchor instead of waiting for the next pass.
                scheduleRestorePassAfterLayoutChange()
                return
            }
            noteStableViewportFromLiveView()
            scheduleViewportPersistence()
        }

        /// Scrolling and zooming move the page under the popover. They do not
        /// cancel the translation. The popover is anchored to the selection's
        /// page rects, so it follows those rects into their new screen position.
        private func followTranslationAnchor() {
            guard !isApplyingTranslationSelection else { return }
            guard activeTranslationSelectionID != nil else { return }
            guard !anchorFollowScheduled else { return }
            anchorFollowScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.anchorFollowScheduled = false
                guard self.activeTranslationSelectionID != nil,
                      let pdfView = self.pdfView,
                      let document = pdfView.document,
                      let markups = self.parent.translationSelection?.pageMarkups,
                      !markups.isEmpty else { return }
                let rect = Self.swiftUIUnion(of: markups, document: document, pdfView: pdfView)
                guard !rect.isNull, !rect.isEmpty else { return }
                self.parent.onTranslationAnchorMoved(rect)
            }
        }

        /// The reader belongs to the user as soon as they scroll: stop re-applying the saved
        /// position and start recording the new one.
        @objc func userWillStartLiveScroll(_ notification: Notification) {
            switch NSApp.currentEvent?.type {
            case .scrollWheel, .magnify, .swipe, .leftMouseDown, .leftMouseDragged:
                lastUserScrollAt = ProcessInfo.processInfo.systemUptime
            default:
                return
            }
            guard isRestoringViewport, let pdfView else { return }
            finishViewportRestore(in: pdfView)
        }

        private func scheduleViewportPersistence() {
            scrollDebounce?.invalidate()
            scrollDebounce = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.publishCommittedPage()
            }
        }

        /// Save position synchronously just before the window is minimized.
        @objc func windowWillMiniaturize(_ notification: Notification) {
            // Verify this notification belongs to the window that contains our PDFView.
            guard let notifWindow = notification.object as? NSWindow,
                  let pdfView, pdfView.window === notifWindow else { return }
            publishCommittedPage()
        }

        /// PDFKit resets scroll when a window is un-minimized; restore page + vertical offset.
        @objc func windowDidDeminiaturize(_ notification: Notification) {
            guard let notifWindow = notification.object as? NSWindow,
                  let pdfView, pdfView.window === notifWindow,
                  let page = pdfView.document?.page(at: lastKnownPageIndex) else { return }
            let offset = lastScrollOffset
            let viewportState = lastViewportState
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak pdfView] in
                guard let pdfView else { return }
                self.applyZoomState(viewportState, to: pdfView)
                pdfView.go(to: page)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let viewportState {
                        Self.applyViewportOffsets(viewportState, to: pdfView)
                    } else {
                        Self.applyNormalizedScrollOffset(offset, to: pdfView)
                    }
                }
            }
            ReaderEventBus.shared.postWindowDidDeminiaturize()
        }

        /// Cmd+S — flush current position to SQLite immediately.
        @objc func savePositionNow(_ notification: Notification) {
            guard let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  !isRestoringViewport,
                  pdfView != nil else { return }
            publishCommittedPage()
        }

        /// Called just before the app process terminates — saves position synchronously.
        @objc func appWillTerminate(_ notification: Notification) {
            scrollDebounce?.invalidate()
            annotationSaveDebounce?.invalidate()
            persistFreeMarkups()
            publishCommittedPage()
        }

        // MARK: Text selection

        @objc func selectionChanged(_ notification: Notification) {
            guard !isApplyingTranslationSelection else { return }
            guard !isJumping else { return }
            guard let pdfView = notification.object as? PDFView else { return }
            guard activeTranslationSelectionID == nil else { return }

            guard let selection = pdfView.currentSelection,
                  let selectedStr = selection.string, !selectedStr.isEmpty else {
                selectionGesture = nil
                selectionDebounce?.invalidate()
                DispatchQueue.main.async { self.parent.onClearSelection() }
                return
            }

            let selectionSnapshot = (selection.copy() as? PDFSelection) ?? selection
            selectionDebounce?.invalidate()
            selectionDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak pdfView] _ in
                guard let self, self.activeTranslationSelectionID == nil,
                      !self.isApplyingTranslationSelection,
                      let pdfView, let doc = pdfView.document else { return }
                let rawWord = selectedStr.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawWord.isEmpty else { return }

                let gesture = self.selectionGesture
                self.selectionGesture = nil
                let captured = PDFSelectionMarkupGeometry.capture(
                    selection: selectionSnapshot,
                    document: doc,
                    gesture: gesture
                )
                let markups = captured.markups
                guard let primary = markups.first else {
                    DispatchQueue.main.async { self.parent.onClearSelection() }
                    return
                }

                let fallback = PDFExtractedTextCollapser.collapse(
                    markups
                        .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                )
                let resolved = ReadingSentenceContext.resolve(lines: captured.lines)
                let word = resolved?.word ?? fallback
                let sentence = resolved?.sentence ?? fallback
                guard !word.isEmpty, !sentence.isEmpty else {
                    DispatchQueue.main.async { self.parent.onClearSelection() }
                    return
                }
                guard let currentPage = doc.page(at: primary.pageIndex) ?? pdfView.currentPage else { return }
                let overallBounds = primary.bounds
                let union = Self.swiftUIUnion(of: markups, document: doc, pdfView: pdfView)
                let selectionAnchorRect = union.isNull || union.isEmpty
                    ? Self.swiftUIRect(boundsInPage: overallBounds, page: currentPage, pdfView: pdfView)
                    : union
                let menuAnchor = Self.menuAnchor(boundsInPage: overallBounds, page: currentPage, pdfView: pdfView)
                let info = SelectionInfo(
                    word: word,
                    sentence: sentence,
                    bounds: overallBounds,
                    boundsStr: primary.boundsStr,
                    page: primary.pageIndex,
                    menuAnchor: menuAnchor,
                    selectionAnchorRect: selectionAnchorRect,
                    pageMarkups: markups
                )
                DispatchQueue.main.async {
                    self.parent.onTextSelected(info)
                }
            }
        }

        /// Convert selection bounds (page coords) to a SwiftUI-space CGPoint for the action menu.
        private static func menuAnchor(boundsInPage: CGRect,
                                       page: PDFPage, pdfView: PDFView) -> CGPoint {
            let boundsInPDFView  = pdfView.convert(boundsInPage, from: page)
            let boundsInWindow   = pdfView.convert(boundsInPDFView, to: nil)
            let pdfFrameInWindow = pdfView.convert(pdfView.bounds, to: nil)

            let swiftUICenterX = boundsInWindow.midX - pdfFrameInWindow.minX
            let selTopSwiftUI   = pdfFrameInWindow.maxY - boundsInWindow.maxY

            let menuH: CGFloat = 40
            let menuY = max(selTopSwiftUI - 8 - menuH / 2, menuH / 2 + 4)
            let menuX = min(max(swiftUICenterX, 120), pdfView.bounds.width - 120)
            return CGPoint(x: menuX, y: menuY)
        }

        /// Visible lines when any of the selection is on screen, otherwise the
        /// whole span. A cross-page selection must not become one giant anchor.
        private static func swiftUIUnion(
            of markups: [PDFPageMarkup],
            document: PDFDocument,
            pdfView: PDFView
        ) -> CGRect {
            var visibleUnion = CGRect.null
            var all = CGRect.null
            let visible = pdfView.bounds
            for markup in markups {
                guard let page = document.page(at: markup.pageIndex) else { continue }
                for rect in markup.lineRects where !rect.isNull && !rect.isEmpty {
                    let inView = pdfView.convert(rect, from: page)
                    let converted = swiftUIRect(boundsInPage: rect, page: page, pdfView: pdfView)
                    guard converted.width > 0, converted.height > 0 else { continue }
                    all = all.isNull ? converted : all.union(converted)
                    if inView.intersects(visible) {
                        visibleUnion = visibleUnion.isNull ? converted : visibleUnion.union(converted)
                    }
                }
            }
            return visibleUnion.isNull ? all : visibleUnion
        }

        private static func swiftUIRect(boundsInPage: CGRect, page: PDFPage, pdfView: PDFView) -> CGRect {
            let boundsInPDFView = pdfView.convert(boundsInPage, from: page)
            let boundsInWindow = pdfView.convert(boundsInPDFView, to: nil)
            let pdfFrameInWindow = pdfView.convert(pdfView.bounds, to: nil)
            return CGRect(
                x: boundsInWindow.minX - pdfFrameInWindow.minX,
                y: pdfFrameInWindow.maxY - boundsInWindow.maxY,
                width: boundsInWindow.width,
                height: boundsInWindow.height
            )
        }

        func publishNoteAnchors() {
            attachViewportObserverIfNeeded()
            guard let pdfView, let document = pdfView.document else {
                DispatchQueue.main.async { self.parent.onNoteAnchorsChanged([]) }
                return
            }

            let pdfFrameInWindow = pdfView.convert(pdfView.bounds, to: nil)
            let visibleRect = pdfView.bounds
            var textRectsByPageIndex: [Int: [CGRect]] = [:]
            let requests = NoteAnchorCatalog.includingUnderlines(
                saved: parent.noteAnchorRequests, visiblePages: pdfView.visiblePages, document: document
            )
            let anchors = requests.compactMap { request -> NoteAnchorPosition? in
                guard let page = pdfView.document?.page(at: request.pageIndex) else { return nil }
                let rects = Self.parseAnnotationRects(request.boundsStr)
                guard let first = rects.first, !first.isEmpty else { return nil }

                let union = rects.dropFirst().reduce(first) { $0.union($1) }
                let selectionInPDFView = pdfView.convert(union, from: page)
                guard selectionInPDFView.intersects(visibleRect.insetBy(dx: -48, dy: -48)) else { return nil }

                let lineRects = rects.map { Self.swiftUIRect(boundsInPage: $0, page: page, pdfView: pdfView) }
                let textRects = textRectsByPageIndex[request.pageIndex] ?? {
                    let pageTextSelection = page.selection(for: page.bounds(for: .cropBox))
                    let pageTextLines = pageTextSelection?.selectionsByLine() ?? []
                    let converted = pageTextLines.compactMap { selection -> CGRect? in
                        let rect = selection.bounds(for: page)
                        guard !rect.isEmpty else { return nil }
                        return Self.swiftUIRect(boundsInPage: rect, page: page, pdfView: pdfView)
                    }
                    textRectsByPageIndex[request.pageIndex] = converted
                    return converted
                }()
                let placement = NoteAnchorPlacementPolicy.place(
                    lineRects: lineRects,
                    textRects: textRects,
                    containerRect: CGRect(origin: .zero, size: pdfView.bounds.size).insetBy(dx: 4, dy: 4)
                )
                guard let point = placement?.point else { return nil }

                let unionInPDFView = pdfView.convert(union, from: page)
                let unionInWindow = pdfView.convert(unionInPDFView, to: nil)
                let anchorRect = CGRect(
                    x: unionInWindow.minX - pdfFrameInWindow.minX,
                    y: pdfFrameInWindow.maxY - unionInWindow.maxY,
                    width: unionInWindow.width,
                    height: unionInWindow.height
                )

                return NoteAnchorPosition(
                    id: request.id,
                    noteId: request.noteId,
                    pageIndex: request.pageIndex,
                    point: point,
                    anchorRect: anchorRect,
                    pageMarkup: PDFPageMarkup(
                        pageIndex: request.pageIndex, lineRects: rects,
                        text: rects.compactMap { page.selection(for: $0)?.string }.joined(separator: " ")
                    )
                )
            }
            DispatchQueue.main.async { self.parent.onNoteAnchorsChanged(anchors) }
        }

        // MARK: Scroll offset

        private func scrollOffset(for pdfView: PDFView) -> Double {
            guard let sv = Self.scrollView(for: pdfView) else { return 0 }
            let h = sv.documentView?.bounds.height ?? 1
            guard h > 0 else { return 0 }
            return max(0, min(1, sv.documentVisibleRect.minY / h))
        }

        // MARK: Helpers

        private static func intValue(_ raw: Any?) -> Int? {
            if let value = raw as? Int { return value }
            if let value = raw as? Int64 { return Int(value) }
            if let value = raw as? NSNumber { return value.intValue }
            return nil
        }

        private static func intArray(_ raw: Any?) -> [Int]? {
            if let values = raw as? [Int] { return values }
            if let values = raw as? [NSNumber] { return values.map(\.intValue) }
            if let values = raw as? NSArray {
                let mapped = values.compactMap { intValue($0) }
                return mapped.count == values.count ? mapped : nil
            }
            return nil
        }

        private static func annotationTargets(from userInfo: [AnyHashable: Any]?) -> [(Int, String)]? {
            if let pageIndexes = intArray(userInfo?["pageIndexes"]),
               let boundsStrs = userInfo?["boundsStrs"] as? [String],
               !pageIndexes.isEmpty,
               pageIndexes.count == boundsStrs.count {
                return Array(zip(pageIndexes, boundsStrs))
            }
            if let pageIndex = intValue(userInfo?["pageIndex"]),
               let boundsStr = userInfo?["boundsStr"] as? String {
                return [(pageIndex, boundsStr)]
            }
            return nil
        }

        /// Parse a pipe-separated per-line bounds string back to CGRect array.
        /// Backward compatible: strings without `|` are treated as a single rect.
        static func parseAnnotationRects(_ boundsStr: String) -> [CGRect] {
            AnnotationBoundsCodec.parse(boundsStr)
        }

        @discardableResult
        private static func makeHighlightAnnotation(
            lineRects: [CGRect],
            selection: PDFSelection?,
            page: PDFPage,
            color: NSColor = PDFHighlightAnnotationFactory.nativeHighlightColor,
            userName: String?,
            contents: String?
        ) -> PDFAnnotation? {
            if let selection {
                return PDFHighlightAnnotationFactory.makeHighlight(
                    from: selection,
                    on: page,
                    color: color,
                    userName: userName,
                    contents: contents
                )
            }
            return PDFHighlightAnnotationFactory.makeHighlight(
                lineRects: lineRects,
                color: color,
                userName: userName,
                contents: contents
            )
        }

        @discardableResult
        private static func makeMarkupAnnotations(
            lineRects: [CGRect],
            selection: PDFSelection?,
            type: PDFAnnotationSubtype,
            color: NSColor,
            tag: String,
            page: PDFPage,
            contents: String
        ) -> [PDFAnnotation] {
            switch type {
            case .highlight:
                guard let annotation = makeHighlightAnnotation(
                    lineRects: lineRects,
                    selection: selection,
                    page: page,
                    color: color,
                    userName: tag,
                    contents: contents
                ) else { return [] }
                page.addAnnotation(annotation)
                return [annotation]
            case .underline:
                guard let annotation = PDFHighlightAnnotationFactory.makeUnderline(
                    lineRects: lineRects,
                    userName: tag,
                    contents: contents
                ) else { return [] }
                page.addAnnotation(annotation)
                return [annotation]
            default:
                return []
            }
        }

        @discardableResult
        private static func makeAnnotation(bounds: CGRect, type: PDFAnnotationSubtype,
                                           color: NSColor, tag: String, page: PDFPage,
                                           contents: String? = nil) -> PDFAnnotation {
            let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            if type == .underline {
                PDFMarkupAppearance.applyUnderline(to: ann)
            } else {
                ann.color = color
            }
            ann.userName = tag
            if let contents = contents {
                ann.contents = contents
            }
            page.addAnnotation(ann)
            return ann
        }
    }
}
