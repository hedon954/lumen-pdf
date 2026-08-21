import SwiftUI
import PDFKit
import AppKit

enum ReaderViewportTransitionMode {
    case animatedChrome
    case interactiveResize
}

protocol ReaderViewportTransitionHandling: AnyObject {
    func beginReadingViewportTransition(mode: ReaderViewportTransitionMode)
    func endReadingViewportTransition()
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

// MARK: - PDFKit NSViewRepresentable
struct PDFKitView: NSViewRepresentable {
    let filePath: String
    let savedPage: Int
    let savedScrollOffset: Double
    let onPageChange: (Int, Double) -> Void
    /// word, sentence, overallBounds, perLineBoundsStr, pageIndex, menuAnchor, selectionAnchorRect, pageMarkups
    let onTextSelected: (SelectionInfo) -> Void
    let onClearSelection: () -> Void
    let onDocumentLoaded: (Int) -> Void
    let noteAnchorRequests: [NoteAnchorRequest]
    let onNoteAnchorsChanged: ([NoteAnchorPosition]) -> Void
    let viewportTransitionController: ReaderViewportTransitionController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
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
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Use coordinator's stored filePath (not documentURL?.path) because
        // Security-Scoped Bookmark-resolved URLs can differ from the original path.
        context.coordinator.parent = self
        viewportTransitionController.handler = context.coordinator
        context.coordinator.attachViewportObserverIfNeeded()
        guard context.coordinator.currentFilePath != filePath else {
            context.coordinator.publishNoteAnchors()
            return
        }
        guard let doc = Self.loadDocument(filePath: filePath) else { return }
        context.coordinator.persistViewportState()
        context.coordinator.currentFilePath = filePath
        let storedViewport = ReadingRestorationStore.shared.viewport(for: filePath)
        context.coordinator.beginViewportRestore(
            pageIndex: storedViewport?.pageIndex ?? savedPage,
            scrollOffset: savedScrollOffset,
            viewportState: storedViewport
        )
        pdfView.document = doc
        onDocumentLoaded(doc.pageCount)
        context.coordinator.applyHighlights(to: doc, filePath: filePath)
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
        private var selectionDebounce: Timer?
        private var scrollDebounce: Timer?
        private var annotationSaveDebounce: Timer?
        private weak var observedViewport: NSClipView?
        private weak var observedScrollView: NSScrollView?
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
            guard let pdfView,
                  !currentFilePath.isEmpty,
                  let state = Self.captureViewportState(from: pdfView) else { return }
            lastViewportState = state
            ReadingRestorationStore.shared.updateViewport(state, for: currentFilePath)
        }

        private func finishViewportRestore(in pdfView: PDFView) {
            pendingRestoreTimeoutWorkItem?.cancel()
            pendingRestoreTargetPage = nil
            isRestoringViewport = false

            guard let document = pdfView.document,
                  let currentPage = pdfView.currentPage else { return }
            let pageIndex = document.index(for: currentPage)
            let scrollOffset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = scrollOffset
            persistViewportState()
            parent.onPageChange(pageIndex, scrollOffset)
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
            let pageIndex = pdfView.currentPage.flatMap { page in
                pdfView.document?.index(for: page)
            }
            return ReadingRestorationState.PDFViewport(
                pageIndex: pageIndex,
                autoScales: pdfView.autoScales,
                scaleFactor: Double(pdfView.scaleFactor),
                horizontalOffset: maxX > 0 ? Double(visibleRect.minX / maxX) : 0,
                verticalOffset: maxY > 0 ? Double(visibleRect.minY / maxY) : 0,
                anchor: captureAnchor(from: pdfView, scrollView: scrollView, documentView: documentView)
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
            let topLeftInPDFView = pdfView.convert(topLeftInDocument, from: documentView)
            guard let page = pdfView.page(for: topLeftInPDFView, nearest: true) else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            let pointInPage = pdfView.convert(topLeftInPDFView, to: page)
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

        /// Snapshot for undo/redo of note-linked underline annotations.
        private struct NoteAnnotationSnapshot {
            let noteId: String
            let bounds: CGRect
        }

        @objc func addFreeAnnotation(_ notification: Notification) {
            guard let typeStr = notification.userInfo?["annotationType"] as? String,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView
            else { return }

            let targets: [(Int, String)]
            if let pageIndexes = Self.intArray(notification.userInfo?["pageIndexes"]),
               let boundsStrs = notification.userInfo?["boundsStrs"] as? [String],
               pageIndexes.count == boundsStrs.count {
                targets = Array(zip(pageIndexes, boundsStrs))
            } else if let pageIndex = Self.intValue(notification.userInfo?["pageIndex"]),
                      let boundsStr = notification.userInfo?["boundsStr"] as? String {
                targets = [(pageIndex, boundsStr)]
            } else {
                return
            }

            pdfView.undoManager?.beginUndoGrouping()
            defer { pdfView.undoManager?.endUndoGrouping() }
            for (pageIndex, boundsStr) in targets {
                guard let page = pdfView.document?.page(at: pageIndex) else { continue }
                let lineRects = Self.parseAnnotationRects(boundsStr)
                guard !lineRects.isEmpty else { continue }
                applyFreeAnnotation(type: typeStr, page: page, lineRects: lineRects)
            }
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
            guard let undo = pdfView?.undoManager else { return }
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
            }
            if !undo.isUndoing {
                undo.setActionName(label)
            }
        }

        private func registerRedoAnnotationMutation(
            page: PDFPage,
            restoredRemoved: [PDFAnnotation],
            readdSnapshots: [FreeAnnotationSnapshot],
            label: String
        ) {
            guard let undo = pdfView?.undoManager else { return }
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
            }
            if !undo.isUndoing {
                undo.setActionName(label)
            }
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
            guard let noteId     = notification.userInfo?["noteId"]     as? String,
                  let pageIndex  = notification.userInfo?["pageIndex"]  as? Int,
                  let boundsStr  = notification.userInfo?["boundsStr"]  as? String,
                  let filePath   = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page       = pdfView.document?.page(at: pageIndex)
            else { return }

            let lineRects = Self.parseAnnotationRects(boundsStr)
            guard !lineRects.isEmpty else { return }

            // Merge payload: partial-overlap saves delete old notes and recreate one expanded note.
            let deletedNoteIds = notification.userInfo?["deletedNoteIds"] as? [String] ?? []
            let deletedNotesInfo = notification.userInfo?["deletedNotesInfo"] as? [NoteUndoInfo] ?? []
            let newNoteInfo = notification.userInfo?["newNoteInfo"] as? NoteUndoInfo

            // 移除旧划线标注（合并场景）
            var removedSnapshots: [NoteAnnotationSnapshot] = []
            for oldNoteId in deletedNoteIds {
                let oldAnns = page.annotations.filter { $0.userName == oldNoteId }
                for ann in oldAnns {
                    removedSnapshots.append(NoteAnnotationSnapshot(
                        noteId: oldNoteId,
                        bounds: ann.bounds
                    ))
                    page.removeAnnotation(ann)
                }
            }

            // 添加新划线标注
            var addedAnnotations: [PDFAnnotation] = []
            for rect in lineRects {
                let ann = PDFAnnotation(bounds: rect, forType: .underline, withProperties: nil)
                PDFMarkupAppearance.applyUnderline(to: ann)
                ann.userName = noteId
                ann.contents = "note:\(noteId)"
                page.addAnnotation(ann)
                addedAnnotations.append(ann)
            }

            triggerAnnotationSave()
            publishNoteAnchors()

            // 注册撤销操作
            if let undo = pdfView.undoManager, let newInfo = newNoteInfo {
                let capturedRemovedSnapshots = removedSnapshots
                let capturedDeletedNotesInfo = deletedNotesInfo
                undo.registerUndo(withTarget: self) { coordinator in
                    coordinator.undoUnderlineNote(
                        page: page,
                        addedAnnotations: addedAnnotations,
                        removedSnapshots: capturedRemovedSnapshots,
                        newNoteInfo: newInfo,
                        deletedNotesInfo: capturedDeletedNotesInfo,
                        filePath: filePath
                    )
                }
                undo.setActionName("划线笔记")
            }
        }

        /// 撤销划线笔记操作
        private func undoUnderlineNote(
            page: PDFPage,
            addedAnnotations: [PDFAnnotation],
            removedSnapshots: [NoteAnnotationSnapshot],
            newNoteInfo: NoteUndoInfo,
            deletedNotesInfo: [NoteUndoInfo],
            filePath: String
        ) {
            guard let undo = pdfView?.undoManager else { return }

            // 移除新添加的划线标注
            for ann in addedAnnotations {
                page.removeAnnotation(ann)
            }

            // 恢复旧的划线标注
            var restoredAnnotations: [PDFAnnotation] = []
            for snap in removedSnapshots {
                let ann = PDFAnnotation(bounds: snap.bounds, forType: .underline, withProperties: nil)
                PDFMarkupAppearance.applyUnderline(to: ann)
                ann.userName = snap.noteId
                ann.contents = "note:\(snap.noteId)"
                page.addAnnotation(ann)
                restoredAnnotations.append(ann)
            }

            triggerAnnotationSave()

            // 通知 Swift 层恢复/删除笔记
            // 删除新笔记
            try? ReaderPersistence.shared.deleteNote(id: newNoteInfo.id)
            // 恢复旧笔记
            for info in deletedNotesInfo {
                _ = try? ReaderPersistence.shared.saveNote(
                    pdfPath: info.pdfPath,
                    pdfName: info.pdfName,
                    pageIndex: info.pageIndex,
                    content: info.content,
                    note: info.note,
                    boundsStr: info.boundsStr
                )
            }
            // 刷新笔记列表
            ReaderEventBus.shared.postRefreshNotesList()

            // 注册重做操作
            let capturedDeletedNotesInfo = deletedNotesInfo
            undo.registerUndo(withTarget: self) { coordinator in
                // 重做：重新删除旧笔记，创建新笔记
                for info in capturedDeletedNotesInfo {
                    try? ReaderPersistence.shared.deleteNote(id: info.id)
                }
                _ = try? ReaderPersistence.shared.saveNote(
                    pdfPath: newNoteInfo.pdfPath,
                    pdfName: newNoteInfo.pdfName,
                    pageIndex: newNoteInfo.pageIndex,
                    content: newNoteInfo.content,
                    note: newNoteInfo.note,
                    boundsStr: newNoteInfo.boundsStr
                )
                // 重新添加/移除标注
                for ann in restoredAnnotations {
                    page.removeAnnotation(ann)
                }
                for ann in addedAnnotations {
                    page.addAnnotation(ann)
                }
                coordinator.triggerAnnotationSave()
                // 刷新笔记列表
                ReaderEventBus.shared.postRefreshNotesList()
            }
            undo.setActionName("划线笔记")
        }

        /// 删除划线笔记时移除对应的划线标注
        @objc func removeUnderlineNote(_ notification: Notification) {
            guard let noteId     = notification.userInfo?["noteId"]     as? String,
                  let pageIndex  = notification.userInfo?["pageIndex"]  as? Int,
                  let filePath   = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page       = pdfView.document?.page(at: pageIndex)
            else { return }

            // 移除所有使用该笔记 ID 的划线标注
            page.annotations
                .filter { $0.userName == noteId }
                .forEach { page.removeAnnotation($0) }
            triggerAnnotationSave()
            publishNoteAnchors()
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
                guard let page = doc.page(at: Int(note.pageIndex)) else { continue }
                restoreNoteUnderline(noteId: note.id, boundsStr: note.boundsStr, on: page)
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
            let lineRects = Self.parseAnnotationRects(boundsStr)
            for rect in lineRects where !rect.isEmpty && rect != .zero {
                let ann = PDFAnnotation(bounds: rect, forType: .underline, withProperties: nil)
                PDFMarkupAppearance.applyUnderline(to: ann)
                ann.userName = noteId
                ann.contents = "note:\(noteId)"
                page.addAnnotation(ann)
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

            guard let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let pageIndex = document.index(for: currentPage)
            let offset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = offset
            persistViewportState()
            parent.onPageChange(pageIndex, offset)
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
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }

            let boundsStr = notification.userInfo?["boundsStr"] as? String ?? ""
            cancelPendingViewportRestore()
            isJumping = true
            pdfView.go(to: page)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak pdfView, weak page] in
                guard let self, let pdfView, let page else { return }
                self.focusSelection(boundsStr: boundsStr, on: page, in: pdfView)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        private func focusSelection(boundsStr: String, on page: PDFPage, in pdfView: PDFView) {
            let rects = Self.parseAnnotationRects(boundsStr)
            guard !rects.isEmpty else { return }
            let union = rects.reduce(CGRect.null) { partial, rect in
                partial.isNull ? rect : partial.union(rect)
            }
            guard !union.isNull, !union.isEmpty else { return }

            center(rect: union, on: page, in: pdfView)
            flashFocus(rects: rects, on: page)
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
            let pageIndex = doc.index(for: currentPage)

            if let layoutTransitionMode {
                if layoutTransitionMode == .animatedChrome {
                    maintainLayoutTransitionViewport(in: pdfView)
                }
                return
            }

            if isRestoringViewport, let target = pendingRestoreTargetPage {
                if pageIndex != target { return }
                lastKnownPageIndex = pageIndex
                return
            }

            let offset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = offset
            persistViewportState()
            parent.onPageChange(pageIndex, offset)
            publishNoteAnchors()
        }

        /// The PDFKit clip view is the authoritative viewport signal. Unlike
        /// `didLiveScroll`, this also covers momentum and programmatic scrolling.
        @objc func viewportBoundsChanged(_ notification: Notification) {
            if let layoutTransitionMode {
                if layoutTransitionMode == .animatedChrome, let pdfView {
                    maintainLayoutTransitionViewport(in: pdfView)
                }
                return
            }
            publishNoteAnchors()
            guard !isRestoringViewport else { return }
            scheduleViewportPersistence()
        }

        @objc func viewportGeometryChanged(_ notification: Notification) {
            attachViewportObserverIfNeeded()
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
            scheduleViewportPersistence()
        }

        /// The reader belongs to the user as soon as they scroll: stop re-applying the saved
        /// position and start recording the new one.
        @objc func userWillStartLiveScroll(_ notification: Notification) {
            guard isRestoringViewport, let pdfView else { return }
            finishViewportRestore(in: pdfView)
        }

        private func scheduleViewportPersistence() {
            scrollDebounce?.invalidate()
            scrollDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, let pdfView = self.pdfView,
                      let currentPage = pdfView.currentPage,
                      let doc = pdfView.document else { return }
                let pageIndex = doc.index(for: currentPage)
                let offset = self.scrollOffset(for: pdfView)
                self.lastKnownPageIndex = pageIndex
                self.lastScrollOffset = offset
                self.persistViewportState()
                self.parent.onPageChange(pageIndex, offset)
            }
        }

        /// Save position synchronously just before the window is minimized.
        @objc func windowWillMiniaturize(_ notification: Notification) {
            // Verify this notification belongs to the window that contains our PDFView.
            guard let notifWindow = notification.object as? NSWindow,
                  let pdfView, pdfView.window === notifWindow,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            scrollDebounce?.invalidate()
            let pageIndex = doc.index(for: currentPage)
            let offset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = offset
            persistViewportState()
            try? ReaderPersistence.shared.saveReadingPosition(
                filePath: currentFilePath,
                page: UInt32(pageIndex),
                scrollOffset: offset
            )
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
                  let pdfView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            scrollDebounce?.invalidate()
            let pageIndex = doc.index(for: currentPage)
            let offset = scrollOffset(for: pdfView)
            lastScrollOffset = offset
            persistViewportState()
            parent.onPageChange(pageIndex, offset)
        }

        /// Called just before the app process terminates — saves position synchronously.
        @objc func appWillTerminate(_ notification: Notification) {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            scrollDebounce?.invalidate()
            annotationSaveDebounce?.invalidate()
            persistFreeMarkups()
            persistViewportState()
            let pageIndex = doc.index(for: currentPage)
            try? ReaderPersistence.shared.saveReadingPosition(
                filePath: currentFilePath,
                page: UInt32(pageIndex),
                scrollOffset: scrollOffset(for: pdfView)
            )
        }

        // MARK: Text selection

        @objc func selectionChanged(_ notification: Notification) {
            guard !isJumping else { return }
            guard let pdfView = notification.object as? PDFView else { return }

            guard let selection = pdfView.currentSelection,
                  let selectedStr = selection.string, !selectedStr.isEmpty else {
                selectionDebounce?.invalidate()
                DispatchQueue.main.async { self.parent.onClearSelection() }
                return
            }

            let selectionSnapshot = (selection.copy() as? PDFSelection) ?? selection
            selectionDebounce?.invalidate()
            selectionDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak pdfView] _ in
                guard let self, let pdfView,
                      let doc = pdfView.document else { return }
                let rawWord = selectedStr.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawWord.isEmpty else { return }

                let markups = PDFSelectionMarkupGeometry.make(
                    selection: selectionSnapshot,
                    document: doc
                )
                let preferredIndex = pdfView.currentPage.map { doc.index(for: $0) }
                guard let primary = markups.first(where: { $0.pageIndex == preferredIndex }) ?? markups.first else {
                    DispatchQueue.main.async { self.parent.onClearSelection() }
                    return
                }

                let word = PDFSelectionHeadingLeakFilter.stripEchoedHeadings(
                    from: PDFExtractedTextCollapser.collapse(
                        markups
                            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    )
                )
                guard !word.isEmpty else {
                    DispatchQueue.main.async { self.parent.onClearSelection() }
                    return
                }
                let sentence = PDFSelectionHeadingLeakFilter.stripEchoedHeadings(
                    from: PDFExtractedTextCollapser.collapse(
                        self.extractSentence(from: pdfView, containing: selectionSnapshot) ?? word
                    )
                )
                let currentPage = doc.page(at: primary.pageIndex) ?? pdfView.currentPage
                guard let currentPage else { return }
                let overallBounds = primary.bounds
                let menuAnchor = Self.menuAnchor(boundsInPage: overallBounds,
                                                 page: currentPage, pdfView: pdfView)
                let selectionAnchorRect = Self.swiftUIRect(boundsInPage: overallBounds, page: currentPage, pdfView: pdfView)
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
            guard let pdfView, !parent.noteAnchorRequests.isEmpty else {
                DispatchQueue.main.async { self.parent.onNoteAnchorsChanged([]) }
                return
            }

            let pdfFrameInWindow = pdfView.convert(pdfView.bounds, to: nil)
            let visibleRect = pdfView.bounds
            var textRectsByPageIndex: [Int: [CGRect]] = [:]
            let anchors = parent.noteAnchorRequests.compactMap { request -> NoteAnchorPosition? in
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
                    anchorRect: anchorRect
                )
            }
            DispatchQueue.main.async { self.parent.onNoteAnchorsChanged(anchors) }
        }

        // MARK: Sentence extraction

        private func extractSentence(from pdfView: PDFView, containing selection: PDFSelection) -> String? {
            guard let page = pdfView.currentPage, let pageText = page.string,
                  !pageText.isEmpty else { return nil }
            let word = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = pageText as NSString
            let selRange = selection.range(at: 0, on: page)
            guard selRange.location != NSNotFound, selRange.length > 0 else {
                return fallbackSentence(word: word, in: pageText)
            }
            let anchor = min(selRange.location + max(0, selRange.length / 2), ns.length - 1)
            if let extracted = extractFullSentence(from: ns, anchorUTF16: anchor) {
                return extracted
            }
            return fallbackSentence(word: word, in: pageText)
        }

        private func extractFullSentence(from ns: NSString, anchorUTF16: Int) -> String? {
            let len = ns.length
            guard len > 0, anchorUTF16 >= 0, anchorUTF16 < len else { return nil }
            var start = anchorUTF16
            while start > 0 {
                let c = ns.character(at: start - 1)
                if isSentenceTerminatorUTF16(c) { break }
                start -= 1
            }
            var end = anchorUTF16
            while end < len {
                let c = ns.character(at: end)
                if isSentenceTerminatorUTF16(c) { end += 1; break }
                end += 1
            }
            let r = NSRange(location: start, length: end - start)
            let sentence = PDFSelectionHeadingLeakFilter.stripEchoedHeadings(
                from: ns.substring(with: r)
            )
            if sentence.count >= 2, sentence.count <= 2000 { return sentence }
            return nil
        }

        private func isSentenceTerminatorUTF16(_ c: UInt16) -> Bool {
            switch c {
            case 0x002E, 0x0021, 0x003F: return true // . ! ?
            case 0x3002, 0xFF01, 0xFF1F: return true // 。！？
            default: return false
            }
        }

        private func fallbackSentence(word: String, in pageText: String) -> String? {
            guard !word.isEmpty else { return nil }
            let seps = CharacterSet(charactersIn: ".!?。！？")
            for part in pageText.components(separatedBy: seps) {
                let t = PDFSelectionHeadingLeakFilter.stripEchoedHeadings(
                    from: part.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if t.contains(word), t.count >= 4, t.count <= 2000 { return t }
            }
            return nil
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

        /// Parse a pipe-separated per-line bounds string back to CGRect array.
        /// Backward compatible: strings without `|` are treated as a single rect.
        static func parseAnnotationRects(_ boundsStr: String) -> [CGRect] {
            boundsStr.components(separatedBy: "|").compactMap { part -> CGRect? in
                let r = NSRectFromString(part)
                return r.isEmpty ? nil : r
            }
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
                return lineRects.compactMap { rect -> PDFAnnotation? in
                    guard !rect.isEmpty, rect != .zero else { return nil }
                    return makeAnnotation(
                        bounds: rect,
                        type: .underline,
                        color: color,
                        tag: tag,
                        page: page,
                        contents: contents
                    )
                }
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
