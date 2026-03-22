import SwiftUI
import PDFKit

// MARK: - Selection info for the action menu

struct SelectionInfo: Equatable {
    let word: String
    let sentence: String
    let bounds: CGRect
    let page: Int
    /// Center of the action menu in SwiftUI coordinates (relative to PDFKitView's frame).
    let menuAnchor: CGPoint

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.page == rhs.page && lhs.bounds == rhs.bounds
    }
}

struct PDFReaderView: View {
    let document: PdfDocument
    @EnvironmentObject private var appState: AppState
    @StateObject private var session = ReadingSessionService()

    @State private var translationRequest: TranslationBubbleRequest?
    @State private var isTranslating = false
    @State private var pendingSelection: SelectionInfo?

    var body: some View {
        ZStack {
            PDFKitView(
                filePath: document.filePath,
                savedPage: Int(document.lastPage),
                savedScrollOffset: document.lastScrollOffset,
                onPageChange: { page, offset in
                    appState.saveReadingPosition(
                        filePath: document.filePath,
                        page: UInt32(page),
                        scrollOffset: offset
                    )
                },
                onTextSelected: { word, sentence, bounds, page, anchor in
                    guard !word.isEmpty else { return }
                    pendingSelection = SelectionInfo(
                        word: word, sentence: sentence,
                        bounds: bounds, page: page, menuAnchor: anchor
                    )
                },
                onClearSelection: {
                    if translationRequest == nil { pendingSelection = nil }
                },
                onDocumentLoaded: { totalPages in
                    handleDocumentLoaded(totalPages: totalPages)
                }
            )

            // Selection action menu — positioned near the selection
            if let sel = pendingSelection, translationRequest == nil {
                selectionActionBar(sel)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    .animation(.spring(duration: 0.18), value: pendingSelection)
            }

            // Translation bubble
            if let req = translationRequest {
                TranslationBubble(
                    request: req,
                    isLoading: isTranslating,
                    onSave: { result in saveToDiary(result: result, request: req) },
                    onDelete: { deletedId in
                        NotificationCenter.default.post(
                            name: .removeHighlight,
                            object: nil,
                            userInfo: [
                                "entryId": deletedId,
                                "pageIndex": req.page,
                                "filePath": document.filePath
                            ]
                        )
                        appState.refreshVocabulary()
                    },
                    onDismiss: { translationRequest = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: translationRequest != nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(document.fileName).font(.headline)
            }
        }
        .id(document.id)
    }

    // MARK: - Selection Action Bar

    private func selectionActionBar(_ sel: SelectionInfo) -> some View {
        HStack(spacing: 0) {
            actionBarBtn(icon: "character.bubble", label: "翻译") {
                requestTranslation(word: sel.word, sentence: sel.sentence,
                                   bounds: sel.bounds, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 22)
            actionBarBtn(icon: "highlighter", label: "高亮") {
                postFreeAnnotation(type: "highlight", bounds: sel.bounds, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 22)
            actionBarBtn(icon: "underline", label: "划线") {
                postFreeAnnotation(type: "underline", bounds: sel.bounds, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 22)
            actionBarBtn(icon: "xmark", label: "") {
                pendingSelection = nil
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
        .fixedSize()
        .position(x: sel.menuAnchor.x, y: sel.menuAnchor.y)
    }

    private func actionBarBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                if !label.isEmpty {
                    Text(label).font(.system(size: 12))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func postFreeAnnotation(type: String, bounds: CGRect, page: Int) {
        NotificationCenter.default.post(
            name: .addFreeAnnotation,
            object: nil,
            userInfo: [
                "annotationType": type,
                "pageIndex": page,
                "bounds": NSStringFromRect(bounds),
                "filePath": document.filePath
            ]
        )
    }

    // MARK: - Document loaded

    private func handleDocumentLoaded(totalPages: Int) {
        try? BridgeService.shared.upsertPdfDocument(
            filePath: document.filePath,
            fileName: document.fileName,
            totalPages: UInt32(totalPages)
        )
        appState.refreshLibrary()
        if document.lastPage > 0 {
            appState.showToast("已定位到 P\(document.lastPage + 1)")
        }
    }

    // MARK: - Translation

    private func requestTranslation(word: String, sentence: String, bounds: CGRect, page: Int) {
        let hash = session.sentenceHash(sentence)

        // Check if this exact word+sentence context is already saved.
        // We do NOT use the cached translation — always call LLM so that the same word
        // in different positions gets a fresh translation for its specific context.
        let existingEntry = try? BridgeService.shared.getVocabularyByWordAndHash(
            word: word, sentenceHash: hash
        )
        if let e = existingEntry { BridgeService.shared.incrementQueryCount(id: e.id) }

        translationRequest = TranslationBubbleRequest(
            word: word, sentence: sentence, bounds: bounds, page: page,
            result: nil, existingEntryId: existingEntry?.id
        )
        isTranslating = true

        Task {
            do {
                let result = try await BridgeService.shared.translate(word: word, sentence: sentence)
                await MainActor.run {
                    translationRequest?.result = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run { isTranslating = false }
            }
        }
    }

    // MARK: - Save to vocabulary

    @discardableResult
    private func saveToDiary(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        let hash = session.sentenceHash(request.sentence)
        let boundsStr = NSStringFromRect(request.bounds)
        guard let entry = try? BridgeService.shared.saveVocabulary(
            word: result.word, sentence: request.sentence, sentenceHash: hash,
            pdfPath: document.filePath, pdfName: document.fileName,
            pageIndex: UInt32(request.page), selectionBounds: boundsStr,
            phonetic: result.phonetic, partOfSpeech: result.partOfSpeech,
            contextTranslation: result.contextTranslation,
            contextExplanation: result.contextExplanation,
            generalDefinition: result.generalDefinition,
            contextSentenceTranslation: result.contextSentenceTranslation,
            translationSource: result.source
        ) else { return nil }

        NotificationCenter.default.post(
            name: .addHighlight, object: nil,
            userInfo: [
                "entryId": entry.id, "pageIndex": Int(entry.pageIndex),
                "bounds": boundsStr, "filePath": document.filePath
            ]
        )
        appState.refreshVocabulary()
        appState.showToast("已保存「\(entry.word)」")
        return entry.id
    }
}

// MARK: - PDFKit NSViewRepresentable

struct PDFKitView: NSViewRepresentable {
    let filePath: String
    let savedPage: Int
    let savedScrollOffset: Double
    let onPageChange: (Int, Double) -> Void
    let onTextSelected: (String, String, CGRect, Int, CGPoint) -> Void
    let onClearSelection: () -> Void
    let onDocumentLoaded: (Int) -> Void

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
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.outlineNavigate(_:)),
                       name: .outlineNavigate, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.jumpToPage(_:)),
                       name: .jumpToPage, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addHighlight(_:)),
                       name: .addHighlight, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.removeHighlight(_:)),
                       name: .removeHighlight, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addFreeAnnotation(_:)),
                       name: .addFreeAnnotation, object: nil)
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        guard pdfView.document?.documentURL?.path != filePath else { return }
        guard let doc = Self.loadDocument(filePath: filePath) else { return }
        pdfView.document = doc
        context.coordinator.parent = self
        onDocumentLoaded(doc.pageCount)
        DispatchQueue.main.async {
            if self.savedPage > 0, self.savedPage < doc.pageCount,
               let page = doc.page(at: self.savedPage) {
                pdfView.go(to: page)
            }
        }
        context.coordinator.applyHighlights(to: doc, filePath: filePath)
    }

    /// Load a PDFDocument, with security-scoped bookmark fallback for sandboxed apps.
    static func loadDocument(filePath: String) -> PDFDocument? {
        let url = URL(fileURLWithPath: filePath)
        if let doc = PDFDocument(url: url) { return doc }
        // Sandbox fallback: resolve saved bookmark
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

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var debounceTimer: Timer?
        var isJumping = false

        init(_ parent: PDFKitView) { self.parent = parent }

        @objc func outlineNavigate(_ notification: Notification) {
            guard let idx   = notification.userInfo?["pageIndex"] as? Int,
                  let path  = notification.userInfo?["filePath"]  as? String,
                  let pdfView, pdfView.document?.documentURL?.path == path,
                  let page  = pdfView.document?.page(at: idx)
            else { return }
            pdfView.go(to: page)
        }

        @objc func addHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let boundsStr = notification.userInfo?["bounds"]     as? String,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  let pdfView,  pdfView.document?.documentURL?.path == filePath,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            addVocabAnnotation(entryId: entryId, boundsStr: boundsStr, to: page)
        }

        @objc func removeHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  let pdfView,  pdfView.document?.documentURL?.path == filePath,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            page.annotations
                .filter { $0.userName == entryId }
                .forEach { page.removeAnnotation($0) }
        }

        /// Add a free (non-vocab) annotation with toggle/merge semantics.
        @objc func addFreeAnnotation(_ notification: Notification) {
            guard let typeStr   = notification.userInfo?["annotationType"] as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]      as? Int,
                  let boundsStr = notification.userInfo?["bounds"]         as? String,
                  let filePath  = notification.userInfo?["filePath"]       as? String,
                  let pdfView,  pdfView.document?.documentURL?.path == filePath,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }

            let bounds  = NSRectFromString(boundsStr)
            guard bounds != .zero else { return }

            let annType: PDFAnnotationSubtype = typeStr == "underline" ? .underline : .highlight
            let color: NSColor = typeStr == "underline"
                ? NSColor.systemBlue.withAlphaComponent(0.6)
                : NSColor.systemYellow.withAlphaComponent(0.5)

            // Free annotations are identified by a fixed userName tag so we can reliably
            // find them for toggle/merge (PDFAnnotation.type is not reliably populated).
            let tag = typeStr == "underline" ? "__fu" : "__fh"

            let existing = page.annotations.filter {
                $0.userName == tag && $0.bounds.intersects(bounds)
            }

            if existing.isEmpty {
                // No overlap – add new annotation
                let ann = PDFAnnotation(bounds: bounds, forType: annType, withProperties: nil)
                ann.color = color
                ann.userName = tag      // tag so we can find/remove it later
                page.addAnnotation(ann)
            } else {
                // Compute union of all overlapping existing annotations
                let unionExisting = existing.dropFirst().reduce(existing[0].bounds) { $0.union($1.bounds) }
                let isFullyCovered = unionExisting.contains(bounds)

                // Remove existing overlapping annotations
                existing.forEach { page.removeAnnotation($0) }

                if isFullyCovered {
                    // All covered → toggle OFF (removed above, done)
                } else {
                    // Partial coverage → merge and re-add with combined bounds
                    let merged = existing.reduce(bounds) { $0.union($1.bounds) }
                    let ann = PDFAnnotation(bounds: merged, forType: annType, withProperties: nil)
                    ann.color = color
                    ann.userName = tag
                    page.addAnnotation(ann)
                }
            }
        }

        func applyHighlights(to doc: PDFDocument, filePath: String) {
            let entries = (try? BridgeService.shared.listVocabulary()) ?? []
            for entry in entries where entry.pdfPath == filePath {
                guard let page = doc.page(at: Int(entry.pageIndex)) else { continue }
                addVocabAnnotation(entryId: entry.id, boundsStr: entry.selectionBounds, to: page)
            }
        }

        private func addVocabAnnotation(entryId: String, boundsStr: String, to page: PDFPage) {
            let bounds = NSRectFromString(boundsStr)
            guard bounds != .zero else { return }
            guard !page.annotations.contains(where: { $0.userName == entryId }) else { return }
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = NSColor.systemYellow.withAlphaComponent(0.5)
            ann.userName = entryId
            page.addAnnotation(ann)
        }

        @objc func jumpToPage(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath  = notification.userInfo?["filePath"]  as? String,
                  let pdfView,  pdfView.document?.documentURL?.path == filePath,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            isJumping = true
            pdfView.go(to: page)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let pageIndex = doc.index(for: currentPage)
            parent.onPageChange(pageIndex, scrollOffset(for: pdfView))
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard !isJumping else { return }
            guard let pdfView = notification.object as? PDFView else { return }

            guard let selection = pdfView.currentSelection,
                  let selectedStr = selection.string, !selectedStr.isEmpty else {
                debounceTimer?.invalidate()
                DispatchQueue.main.async { self.parent.onClearSelection() }
                return
            }

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak pdfView] _ in
                guard let self, let pdfView,
                      let currentPage = pdfView.currentPage,
                      let doc = pdfView.document else { return }
                let word = selectedStr.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { return }
                let sentence = self.extractSentence(from: pdfView, containing: selection) ?? word
                let boundsInPage = selection.bounds(for: currentPage)
                let pageIndex = doc.index(for: currentPage)
                let menuAnchor = Self.menuAnchor(boundsInPage: boundsInPage,
                                                 page: currentPage, pdfView: pdfView)
                DispatchQueue.main.async {
                    self.parent.onTextSelected(word, sentence, boundsInPage, pageIndex, menuAnchor)
                }
            }
        }

        /// Convert selection bounds (page coords) to a SwiftUI-space CGPoint for the action menu.
        private static func menuAnchor(boundsInPage: CGRect,
                                       page: PDFPage, pdfView: PDFView) -> CGPoint {
            // Page coords → pdfView's NSView coordinate space
            let boundsInPDFView = pdfView.convert(boundsInPage, from: page)
            // pdfView NSView coords → window coords
            let boundsInWindow  = pdfView.convert(boundsInPDFView, to: nil)
            // pdfView's own frame in window coords (establishes the origin offset)
            let pdfFrameInWindow = pdfView.convert(pdfView.bounds, to: nil)

            // Convert to SwiftUI coordinate space (Y increases downward).
            // In AppKit (non-flipped), Y increases upward.
            // pdfFrameInWindow.maxY = AppKit Y of the pdfView's TOP edge.
            let swiftUICenterX = boundsInWindow.midX - pdfFrameInWindow.minX
            // Selection's top edge in SwiftUI space = distance from pdfView top
            let selTopSwiftUI   = pdfFrameInWindow.maxY - boundsInWindow.maxY

            // Position menu CENTER 30 pt above the selection, clamped into view
            let menuH: CGFloat = 40
            let menuY = max(selTopSwiftUI - 8 - menuH / 2, menuH / 2 + 4)
            let menuX = min(max(swiftUICenterX, 120), pdfView.bounds.width - 120)
            return CGPoint(x: menuX, y: menuY)
        }

        private func extractSentence(from pdfView: PDFView, containing selection: PDFSelection) -> String? {
            guard let page = pdfView.currentPage, let pageText = page.string,
                  !pageText.isEmpty else { return nil }

            let word = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // IMPORTANT: Do NOT use `characterIndex(at:)` from geometry — it often maps
            // to the wrong run of text (e.g. list item vs preceding paragraph). Use the
            // selection's actual character range on the page string instead (UTF-16).
            let ns = pageText as NSString
            // macOS PDFKit: `range(at:on:)` — index 0 is the first contiguous range on this page
            let selRange = selection.range(at: 0, on: page)
            guard selRange.location != NSNotFound, selRange.length > 0 else {
                return fallbackSentence(word: word, in: pageText)
            }

            // Anchor at middle of selected text in the page's string (stable for multi-char words)
            let anchor = min(selRange.location + max(0, selRange.length / 2), ns.length - 1)

            // Full **sentence** for LLM: only split on `.` `!` `?` (and CJK 。！？).
            // Do **not** split on `;` or `:` — e.g. "…left to right; each node…" stays one sentence.
            if let extracted = extractFullSentence(from: ns, anchorUTF16: anchor) {
                return extracted
            }
            return fallbackSentence(word: word, in: pageText)
        }

        /// From the previous `.`/`!`/`?`/`。`/`！`/`？` to the next — one complete sentence (UTF-16).
        private func extractFullSentence(from ns: NSString, anchorUTF16: Int) -> String? {
            let len = ns.length
            guard len > 0, anchorUTF16 >= 0, anchorUTF16 < len else { return nil }

            // First character of the sentence containing `anchor`
            var start = anchorUTF16
            while start > 0 {
                let c = ns.character(at: start - 1)
                if isSentenceTerminatorUTF16(c) { break }
                start -= 1
            }

            // Last character inclusive: up to and including the next sentence terminator
            var end = anchorUTF16
            while end < len {
                let c = ns.character(at: end)
                if isSentenceTerminatorUTF16(c) {
                    end += 1 // include terminator
                    break
                }
                end += 1
            }

            let r = NSRange(location: start, length: end - start)
            let sentence = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            // Allow longer contexts for LLM (semicolon-linked clauses)
            if sentence.count >= 2, sentence.count <= 2000 { return sentence }
            return nil
        }

        /// Only true sentence-ending punctuation (not `;` `:` or newlines).
        private func isSentenceTerminatorUTF16(_ c: UInt16) -> Bool {
            switch c {
            case 0x002E, 0x0021, 0x003F: return true // . ! ?
            case 0x3002, 0xFF01, 0xFF1F: return true // 。！？
            default: return false
            }
        }

        /// Last resort: first segment between sentence terminators that contains the word.
        private func fallbackSentence(word: String, in pageText: String) -> String? {
            guard !word.isEmpty else { return nil }
            let seps = CharacterSet(charactersIn: ".!?。！？")
            for part in pageText.components(separatedBy: seps) {
                let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.contains(word), t.count >= 4, t.count <= 2000 { return t }
            }
            return nil
        }

        private func scrollOffset(for pdfView: PDFView) -> Double {
            guard let sv = pdfView.enclosingScrollView else { return 0 }
            let h = sv.documentView?.bounds.height ?? 1
            guard h > 0 else { return 0 }
            return max(0, min(1, sv.documentVisibleRect.minY / h))
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let addHighlight      = Notification.Name("addHighlight")
    static let removeHighlight   = Notification.Name("removeHighlight")
    static let addFreeAnnotation = Notification.Name("addFreeAnnotation")
}

// MARK: - Supporting types

struct TranslationBubbleRequest: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let sentence: String
    let bounds: CGRect
    let page: Int
    var result: TranslationResult?
    let existingEntryId: String?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
