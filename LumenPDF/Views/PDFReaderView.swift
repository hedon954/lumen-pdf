import SwiftUI
import PDFKit
import AppKit

// MARK: - Selection info for the action menu

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }

    var expandedForComparison: CGRect {
        insetBy(dx: -1, dy: -1)
    }

    func isSameTextLine(as other: CGRect) -> Bool {
        let verticalOverlap = min(maxY, other.maxY) - max(minY, other.minY)
        return verticalOverlap > min(height, other.height) * 0.4
            || abs(midY - other.midY) <= max(height, other.height) * 0.5
    }
}

struct SelectionInfo: Equatable {
    let word: String
    let sentence: String
    /// Overall bounding box of the selection on the page (for menu anchor calculation only).
    let bounds: CGRect
    /// Pipe-separated per-line NSRect strings (e.g. "{x,y},{w,h}|{x,y},{w,h}").
    /// Using one rect per line avoids the large gap that spans between lines when a
    /// selection crosses a line break.  Backward-compatible: single-line selections
    /// produce a string with no `|`.
    let boundsStr: String
    let page: Int
    /// Center of the action menu in SwiftUI coordinates (relative to PDFKitView's frame).
    let menuAnchor: CGPoint

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.page == rhs.page && lhs.bounds == rhs.bounds
    }
}

struct UnderlineNoteDraft: Equatable {
    let word: String
    let boundsStr: String
    let page: Int
    let anchor: CGPoint
}

private struct UnderlineNoteDraftView: View {
    let draft: UnderlineNoteDraft
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var noteText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("添加划线笔记")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(ContextSentenceFormatting.displayParagraph(draft.word))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $noteText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 74)
                .focused($isFocused)
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            HStack(alignment: .center) {
                Text("可留空，仅保存划线")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.borderless)
                Button("保存") {
                    onSave(noteText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        .onAppear { isFocused = true }
    }
}

struct PDFReaderView: View {
    let document: PdfDocument
    @EnvironmentObject private var appState: AppState
    @StateObject private var session = ReadingSessionService()

    @State private var translationRequest: TranslationBubbleRequest?
    @State private var isTranslating = false
    @State private var pendingSelection: SelectionInfo?
    @State private var underlineDraft: UnderlineNoteDraft?
    // totalPages is kept as a local state for the initial load callback,
    // then written to appState so ContentView can display it in the toolbar.

    var body: some View {
        ZStack {
            PDFKitView(
                filePath: document.filePath,
                // Use AppState, not PdfDocument: the library snapshot is stale until refresh;
                // after minimize the representable may re-init and would otherwise restore the
                // page from the first open of this session.
                savedPage: appState.currentPageIndex,
                savedScrollOffset: appState.currentScrollOffset,
                onPageChange: { page, offset in
                    appState.saveReadingPosition(
                        filePath: document.filePath,
                        page: UInt32(page),
                        scrollOffset: offset
                    )
                },
                onTextSelected: { word, sentence, bounds, boundsStr, page, anchor in
                    guard !word.isEmpty else { return }
                    pendingSelection = SelectionInfo(
                        word: word, sentence: sentence,
                        bounds: bounds, boundsStr: boundsStr,
                        page: page, menuAnchor: anchor
                    )
                },
                onClearSelection: {
                    if translationRequest == nil && underlineDraft == nil { pendingSelection = nil }
                },
                onDocumentLoaded: { total in
                    handleDocumentLoaded(totalPages: total)
                }
            )

            // Selection action menu — positioned near the selection
            if let sel = pendingSelection, translationRequest == nil && underlineDraft == nil {
                selectionActionBar(sel)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    .animation(.spring(duration: 0.18), value: pendingSelection)
            }

            if let draft = underlineDraft {
                UnderlineNoteDraftView(
                    draft: draft,
                    onCancel: {
                        underlineDraft = nil
                        pendingSelection = nil
                    },
                    onSave: { noteText in
                        saveUnderlineNote(
                            word: draft.word,
                            noteText: noteText,
                            boundsStr: draft.boundsStr,
                            page: draft.page
                        )
                        underlineDraft = nil
                        pendingSelection = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .position(x: draft.anchor.x, y: draft.anchor.y + 72)
                .zIndex(2)
            }

            // Translation bubble
            if let req = translationRequest {
                GeometryReader { bubbleProxy in
                    TranslationBubble(
                        request: req,
                        isLoading: isTranslating,
                        availableSize: bubbleProxy.size,
                        onSave: { result in
                            if req.isExplanationMode || req.isSentenceMode {
                                saveSentenceToNote(result: result, request: req)
                            } else {
                                saveToDiary(result: result, request: req)
                            }
                        },
                        onDelete: { deletedId in
                        // Remove underline annotation if it was saved as a note
                        NotificationCenter.default.post(
                            name: .removeUnderlineNote,
                            object: nil,
                            userInfo: [
                                "noteId": deletedId,
                                "pageIndex": req.page,
                                "filePath": document.filePath
                            ]
                        )
                        // Also try to remove highlight (in case it was saved as vocabulary)
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
                            appState.refreshNotes()
                        },
                        onAskExplanation: { focus in
                            requestExplanation(selection: req.word, context: req.sentence,
                                               bounds: req.bounds, boundsStr: req.boundsStr,
                                               page: req.page, focus: focus)
                        },
                        onDismiss: { translationRequest = nil }
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: translationRequest != nil)
            }
            // ⌘S — invisible button that flushes reading position immediately.
            // Must be inside the ZStack (not .background) to stay in the responder chain.
            Button("") {
                NotificationCenter.default.post(
                    name: .saveReadingPositionNow,
                    object: nil,
                    userInfo: ["filePath": document.filePath]
                )
            }
            .keyboardShortcut("s", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            // Forward Cmd+Z to the responder chain (PDFView undoManager) for annotation undo.
            Button("") {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .id(document.id)
        .onReceive(NotificationCenter.default.publisher(for: .refreshNotesList)) { _ in
            appState.refreshNotes()
        }
    }

    // MARK: - Selection Action Bar

    private func selectionActionBar(_ sel: SelectionInfo) -> some View {
        HStack(spacing: 0) {
            actionBarBtn(icon: "character.bubble", label: "翻译") {
                requestTranslation(word: sel.word, sentence: sel.sentence,
                                   bounds: sel.bounds, boundsStr: sel.boundsStr,
                                   page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "text.bubble", label: "解释") {
                presentExplanationPrompt(selection: sel.word, context: sel.sentence,
                                         bounds: sel.bounds, boundsStr: sel.boundsStr,
                                         page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "highlighter", label: "高亮") {
                postFreeAnnotation(type: "highlight", boundsStr: sel.boundsStr, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "note.text", label: "划线") {
                if hasExactUnderlineNote(boundsStr: sel.boundsStr, page: sel.page) {
                    saveUnderlineNote(word: sel.word, noteText: "", boundsStr: sel.boundsStr, page: sel.page)
                    pendingSelection = nil
                } else {
                    underlineDraft = UnderlineNoteDraft(
                        word: sel.word,
                        boundsStr: sel.boundsStr,
                        page: sel.page,
                        anchor: sel.menuAnchor
                    )
                }
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "xmark", label: "") {
                pendingSelection = nil
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
        .fixedSize()
        .position(x: sel.menuAnchor.x, y: sel.menuAnchor.y)
    }

    private func actionBarBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
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

    private func postFreeAnnotation(type: String, boundsStr: String, page: Int) {
        NotificationCenter.default.post(
            name: .addFreeAnnotation,
            object: nil,
            userInfo: [
                "annotationType": type,
                "pageIndex": page,
                "boundsStr": boundsStr,
                "filePath": document.filePath
            ]
        )
    }

    private func hasExactUnderlineNote(boundsStr: String, page: Int) -> Bool {
        guard let existingNotes = try? BridgeService.shared.listNotesByPdf(pdfPath: document.filePath) else {
            return false
        }
        return existingNotes.contains { note in
            note.pageIndex == UInt32(page) && note.boundsStr == boundsStr
        }
    }

    /// 划线并自动保存为笔记：相同选区 toggle，子区域不变，部分重叠则扩展/合并。
    private func saveUnderlineNote(word: String, noteText: String, boundsStr: String, page: Int) {
        BridgeService.shared.initializeIfNeeded()

        let newRects = Self.parseAnnotationRectsStatic(boundsStr)
        guard !newRects.isEmpty else {
            appState.showToast("保存笔记失败")
            return
        }

        guard let existingNotes = try? BridgeService.shared.listNotesByPdf(pdfPath: document.filePath) else {
            appState.showToast("保存笔记失败")
            return
        }

        let samePageNotes = existingNotes.filter { $0.pageIndex == UInt32(page) }

        // Same selection keeps the toggle behavior: tap/draw the exact same underline again to remove it.
        if let match = samePageNotes.first(where: { $0.boundsStr == boundsStr }) {
            try? BridgeService.shared.deleteNote(id: match.id)
            NotificationCenter.default.post(
                name: .removeUnderlineNote,
                object: nil,
                userInfo: [
                    "noteId": match.id,
                    "pageIndex": page,
                    "filePath": document.filePath
                ]
            )
            appState.refreshNotes()
            appState.showToast("已移除笔记")
            return
        }

        // If the new selection is entirely inside an existing note, keep the existing note unchanged.
        if samePageNotes.contains(where: { note in
            Self.rects(newRects, areCoveredBy: Self.parseAnnotationRectsStatic(note.boundsStr))
        }) {
            appState.showToast("已在现有笔记范围内")
            return
        }

        let overlappingNotes = samePageNotes.filter { note in
            Self.rects(newRects, overlap: Self.parseAnnotationRectsStatic(note.boundsStr))
        }

        if !overlappingNotes.isEmpty {
            mergeUnderlineNote(
                word: word,
                noteText: noteText,
                page: page,
                newRects: newRects,
                overlappingNotes: overlappingNotes
            )
            return
        }

        createUnderlineNote(word: word, noteText: noteText, boundsStr: boundsStr, page: page, deletedNotesInfo: [])
    }

    private func mergeUnderlineNote(
        word: String,
        noteText: String,
        page: Int,
        newRects: [CGRect],
        overlappingNotes: [NoteEntry]
    ) {
        let deletedNotesInfo = overlappingNotes.map { note in
            NoteUndoInfo(
                id: note.id,
                pdfPath: note.pdfPath,
                pdfName: note.pdfName,
                pageIndex: note.pageIndex,
                content: note.content,
                note: note.note,
                boundsStr: note.boundsStr
            )
        }
        let oldRects = overlappingNotes.flatMap { Self.parseAnnotationRectsStatic($0.boundsStr) }
        let mergedBoundsStr = Self.annotationBoundsString(from: Self.mergeAnnotationRects(oldRects + newRects))
        let mergedContent = Self.mergedNoteContent(
            existing: overlappingNotes.map(\.content),
            new: word
        )
        let mergedNoteText = Self.mergedNoteText(
            existing: overlappingNotes.map(\.note),
            new: noteText
        )

        for note in overlappingNotes {
            try? BridgeService.shared.deleteNote(id: note.id)
        }

        guard createUnderlineNote(
            word: mergedContent,
            noteText: mergedNoteText,
            boundsStr: mergedBoundsStr,
            page: page,
            deletedNotesInfo: deletedNotesInfo,
            toastMessage: "已扩展笔记"
        ) != nil else {
            for info in deletedNotesInfo {
                _ = try? BridgeService.shared.saveNote(
                    pdfPath: info.pdfPath,
                    pdfName: info.pdfName,
                    pageIndex: info.pageIndex,
                    content: info.content,
                    note: info.note,
                    boundsStr: info.boundsStr
                )
            }
            return
        }
    }

    @discardableResult
    private func createUnderlineNote(
        word: String,
        noteText: String,
        boundsStr: String,
        page: Int,
        deletedNotesInfo: [NoteUndoInfo],
        toastMessage: String = "已添加笔记"
    ) -> NoteEntry? {
        guard let noteEntry = try? BridgeService.shared.saveNote(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(page),
            content: word,
            note: noteText,
            boundsStr: boundsStr
        ) else {
            appState.showToast("保存笔记失败")
            return nil
        }

        NotificationCenter.default.post(
            name: .addUnderlineNote,
            object: nil,
            userInfo: [
                "noteId": noteEntry.id,
                "pageIndex": page,
                "boundsStr": boundsStr,
                "filePath": document.filePath,
                "deletedNoteIds": deletedNotesInfo.map { $0.id },
                "deletedNotesInfo": deletedNotesInfo,
                "newNoteInfo": NoteUndoInfo(
                    id: noteEntry.id,
                    pdfPath: document.filePath,
                    pdfName: document.fileName,
                    pageIndex: UInt32(page),
                    content: word,
                    note: noteText,
                    boundsStr: boundsStr
                )
            ]
        )

        appState.refreshNotes()
        appState.showToast(toastMessage)
        return noteEntry
    }

    /// 静态方法解析 boundsStr，供多处使用
    private static func parseAnnotationRectsStatic(_ boundsStr: String) -> [CGRect] {
        boundsStr.components(separatedBy: "|").compactMap { part -> CGRect? in
            let r = NSRectFromString(part)
            return r.isEmpty ? nil : r
        }
    }

    private static func annotationBoundsString(from rects: [CGRect]) -> String {
        rects.map { NSStringFromRect($0) }.joined(separator: "|")
    }

    private static func rects(_ candidates: [CGRect], areCoveredBy existing: [CGRect]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { candidate in
            existing.contains { existingRect in
                existingRect.expandedForComparison.contains(candidate)
            }
        }
    }

    private static func rects(_ lhs: [CGRect], overlap rhs: [CGRect]) -> Bool {
        lhs.contains { left in
            rhs.contains { right in
                left.intersection(right).area > 1.0
            }
        }
    }

    private static func mergedNoteContent(existing: [String], new: String) -> String {
        let normalizedNew = ContextSentenceFormatting.displayParagraph(new)
        let existingParagraphs = existing.map(ContextSentenceFormatting.displayParagraph)
        if existingParagraphs.contains(where: { normalizedNew.contains($0) }) {
            return normalizedNew
        }
        if let containingExisting = existingParagraphs.first(where: { $0.contains(normalizedNew) }) {
            return containingExisting
        }
        return (existingParagraphs + [normalizedNew])
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }

    private static func mergedNoteText(existing: [String], new: String) -> String {
        (existing + [new])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func mergeAnnotationRects(_ rects: [CGRect]) -> [CGRect] {
        let sortedRects = rects
            .filter { !$0.isEmpty && $0 != .zero }
            .sorted { lhs, rhs in
                if abs(lhs.midY - rhs.midY) > max(lhs.height, rhs.height) * 0.6 {
                    return lhs.midY > rhs.midY
                }
                return lhs.minX < rhs.minX
            }

        return sortedRects.reduce(into: [CGRect]()) { merged, rect in
            guard let index = merged.firstIndex(where: { $0.isSameTextLine(as: rect) && $0.expandedForComparison.intersects(rect.expandedForComparison) }) else {
                merged.append(rect)
                return
            }
            merged[index] = merged[index].union(rect)
        }
    }

    // MARK: - Document loaded

    private func handleDocumentLoaded(totalPages: Int) {
        appState.totalPages = totalPages
        try? BridgeService.shared.upsertPdfDocument(
            filePath: document.filePath,
            fileName: document.fileName,
            totalPages: UInt32(totalPages)
        )
        appState.refreshLibrary()
        if appState.currentPageIndex > 0 {
            appState.showToast("已定位到 P\(appState.currentPageIndex + 1)")
        }
    }

    // MARK: - Translation

    private func requestTranslation(word: String, sentence: String,
                                     bounds: CGRect, boundsStr: String, page: Int) {
        BridgeService.shared.initializeIfNeeded()

        // Determine if this is sentence mode (multi-word selection)
        let isSentenceMode = word.split(separator: " ").count > 3 || word.count > 25

        // Resolve the "already saved" state up front (synchronously) so the bubble renders the
        // correct saved/unsaved state on its very first frame. An entry is the *same word at the
        // same position* — keyed by word + context (sentence hash) — so the same spelling in a
        // different context (different sentence) is a separate entry and can still be added.
        var existingEntryId: String?
        if !isSentenceMode {
            let hash = session.sentenceHash(sentence)
            if let existing = try? BridgeService.shared.getVocabularyByWordAndHash(word: word, sentenceHash: hash) {
                existingEntryId = existing.id
                BridgeService.shared.incrementQueryCount(id: existing.id)
            }
        }

        translationRequest = TranslationBubbleRequest(
            word: word, sentence: sentence,
            bounds: bounds, boundsStr: boundsStr,
            page: page, result: nil, translationError: nil,
            existingEntryId: existingEntryId,
            isSentenceMode: isSentenceMode,
            isExplanationMode: false
        )
        isTranslating = true

        // Track which translation request this Task belongs to, so a delayed
        // streaming callback from a previous selection can't overwrite the
        // bubble of a fresh one (user dismissed and selected something else).
        let requestId = translationRequest?.id

        Task {
            // Updates the bubble's `result` field as fields stream in.
            // Captured by both streaming-mode branches below.
            @MainActor func applyPartial(_ partial: TranslationResult) {
                guard var req = translationRequest, req.id == requestId else { return }
                req.result = partial
                req.translationError = nil
                translationRequest = req
            }

            do {
                let result: TranslationResult
                if isSentenceMode {
                    result = try await BridgeService.shared.translateSentenceStreaming(
                        sentence: word,
                        onPartial: { partial in applyPartial(partial) }
                    )
                } else {
                    result = try await BridgeService.shared.translateStreaming(
                        word: word,
                        sentence: sentence,
                        onPartial: { partial in applyPartial(partial) }
                    )
                }

                await MainActor.run {
                    guard var req = translationRequest, req.id == requestId else { return }
                    req.result = result
                    req.translationError = nil
                    translationRequest = req
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    guard var req = translationRequest, req.id == requestId else { return }
                    var detail = TranslationErrorFormatter.userMessage(from: error)
                    if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detail = "翻译失败：\(String(describing: error))"
                    }
                    req.translationError = detail
                    translationRequest = req
                    isTranslating = false
                }
            }
        }
    }


    // MARK: - Explanation

    private func presentExplanationPrompt(selection: String, context: String,
                                          bounds: CGRect, boundsStr: String, page: Int) {
        translationRequest = TranslationBubbleRequest(
            word: selection, sentence: context,
            bounds: bounds, boundsStr: boundsStr,
            page: page, result: nil, translationError: nil,
            existingEntryId: nil,
            isSentenceMode: true,
            isExplanationMode: true
        )
        isTranslating = false
    }

    private func requestExplanation(selection: String, context: String,
                                    bounds: CGRect, boundsStr: String, page: Int,
                                    focus: String?) {
        BridgeService.shared.initializeIfNeeded()

        translationRequest = TranslationBubbleRequest(
            word: selection, sentence: context,
            bounds: bounds, boundsStr: boundsStr,
            page: page, result: nil, translationError: nil,
            existingEntryId: nil,
            isSentenceMode: true,
            isExplanationMode: true
        )
        isTranslating = true

        let requestId = translationRequest?.id

        Task {
            @MainActor func applyPartial(_ partial: TranslationResult) {
                guard var req = translationRequest, req.id == requestId else { return }
                req.result = partial
                req.translationError = nil
                translationRequest = req
            }

            do {
                let result = try await BridgeService.shared.explainSelectionStreaming(
                    selection: selection,
                    context: context,
                    focus: focus ?? "",
                    onPartial: { partial in applyPartial(partial) }
                )

                await MainActor.run {
                    guard var req = translationRequest, req.id == requestId else { return }
                    req.result = result
                    req.translationError = nil
                    translationRequest = req
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    guard var req = translationRequest, req.id == requestId else { return }
                    var detail = TranslationErrorFormatter.userMessage(from: error)
                    if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detail = "解释失败：\(String(describing: error))"
                    }
                    req.translationError = detail
                    translationRequest = req
                    isTranslating = false
                }
            }
        }
    }

    // MARK: - Save to vocabulary

    @discardableResult
    private func saveToDiary(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        let hash = session.sentenceHash(request.sentence)
        guard let entry = try? BridgeService.shared.saveVocabulary(
            word: result.word, sentence: request.sentence, sentenceHash: hash,
            pdfPath: document.filePath, pdfName: document.fileName,
            pageIndex: UInt32(request.page), selectionBounds: request.boundsStr,
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
                "boundsStr": request.boundsStr, "filePath": document.filePath
            ]
        )
        appState.refreshVocabulary()
        appState.showToast("已保存「\(entry.word)」")
        return entry.id
    }

    // MARK: - Save sentence translation to notes

    @discardableResult
    private func saveSentenceToNote(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        BridgeService.shared.initializeIfNeeded()

        let noteText: String
        if request.isExplanationMode {
            noteText = result.contextExplanation
        } else {
            // Get translation text (prefer contextSentenceTranslation, fallback to contextTranslation)
            noteText = result.contextSentenceTranslation.isEmpty
                ? result.contextTranslation
                : result.contextSentenceTranslation
        }

        guard let noteEntry = try? BridgeService.shared.saveNote(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(request.page),
            content: request.word,
            note: noteText,
            boundsStr: request.boundsStr
        ) else {
            appState.showToast("保存笔记失败")
            return nil
        }

        // Add underline annotation linked to the note
        NotificationCenter.default.post(
            name: .addUnderlineNote,
            object: nil,
            userInfo: [
                "noteId": noteEntry.id,
                "pageIndex": request.page,
                "boundsStr": request.boundsStr,
                "filePath": document.filePath
            ]
        )

        appState.refreshNotes()
        appState.showToast(request.isExplanationMode ? "解释已保存到笔记" : "已保存到笔记")
        return noteEntry.id
    }
}

// MARK: - PDFKit NSViewRepresentable

struct PDFKitView: NSViewRepresentable {
    let filePath: String
    let savedPage: Int
    let savedScrollOffset: Double
    let onPageChange: (Int, Double) -> Void
    /// word, sentence, overallBounds, perLineBoundsStr, pageIndex, menuAnchor
    let onTextSelected: (String, String, CGRect, String, Int, CGPoint) -> Void
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
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.jumpToSelectionBounds(_:)),
                       name: .jumpToSelectionBounds, object: nil)
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
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Use coordinator's stored filePath (not documentURL?.path) because
        // Security-Scoped Bookmark-resolved URLs can differ from the original path.
        guard context.coordinator.currentFilePath != filePath else { return }
        guard let doc = Self.loadDocument(filePath: filePath) else { return }
        context.coordinator.parent = self
        context.coordinator.currentFilePath = filePath
        // Set BEFORE `document =` — assigning the document fires PDFViewPageChanged at page 0.
        // Without this, we would persist page 0 and reset TOC to the first chapter.
        context.coordinator.pendingRestoreTargetPage = savedPage
        context.coordinator.lastScrollOffset = savedScrollOffset
        context.coordinator.schedulePendingRestoreTimeout()
        pdfView.document = doc
        onDocumentLoaded(doc.pageCount)
        context.coordinator.lastKnownPageIndex = savedPage
        context.coordinator.applyHighlights(to: doc, filePath: filePath)
        DispatchQueue.main.async { [savedPage = self.savedPage, savedScroll = self.savedScrollOffset] in
            if savedPage > 0, savedPage < doc.pageCount,
               let page = doc.page(at: savedPage) {
                pdfView.go(to: page)
            }
            // Continuous mode: restore vertical scroll within the document after layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Coordinator.applyNormalizedScrollOffset(savedScroll, to: pdfView)
            }
        }

        // Re-attach the scroll observer to the new scroll view when the document changes.
        if let sv = pdfView.enclosingScrollView {
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.didLiveScroll(_:)),
                name: NSScrollView.didLiveScrollNotification,
                object: sv
            )
        }
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

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var selectionDebounce: Timer?
        private var scrollDebounce: Timer?
        private var annotationSaveDebounce: Timer?
        var isJumping = false
        /// The file path of the currently loaded document.
        /// Stored explicitly so we never rely on `documentURL?.path`,
        /// which differs from the original path when loaded via a Security-Scoped Bookmark.
        var currentFilePath: String = ""
        /// Last page index the user was actually on — used to restore after window deminiaturize.
        var lastKnownPageIndex: Int = 0
        /// Normalized vertical scroll (0…1), kept in sync with saves.
        var lastScrollOffset: Double = 0
        /// While non-nil, ignore spurious `pageChanged` / scroll-save until we reach this page (document load).
        var pendingRestoreTargetPage: Int?
        private var pendingRestoreTimeoutWorkItem: DispatchWorkItem?

        init(_ parent: PDFKitView) {
            self.parent = parent
            self.lastKnownPageIndex = parent.savedPage
            self.lastScrollOffset = parent.savedScrollOffset
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
            }
            pendingRestoreTimeoutWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        }

        /// Inverse of `scrollOffset(for:)` — restores vertical position in continuous scroll mode.
        static func applyNormalizedScrollOffset(_ normalized: Double, to pdfView: PDFView) {
            guard let sv = pdfView.enclosingScrollView, let dv = sv.documentView else { return }
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
            pendingRestoreTargetPage = nil
            pendingRestoreTimeoutWorkItem?.cancel()
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
                color = (ann.color as NSColor?) ?? PDFHighlightAnnotationFactory.nativeHighlightColor
                tag = ann.userName ?? ""
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
            let color: NSColor
        }

        @objc func addFreeAnnotation(_ notification: Notification) {
            guard let typeStr   = notification.userInfo?["annotationType"] as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]      as? Int,
                  let boundsStr = notification.userInfo?["boundsStr"]      as? String,
                  let filePath  = notification.userInfo?["filePath"]       as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }

            let lineRects = Self.parseAnnotationRects(boundsStr)
            guard !lineRects.isEmpty else { return }

            if typeStr == "highlight" {
                handleFreeHighlight(page: page, lineRects: lineRects)
                return
            }

            let annType: PDFAnnotationSubtype = .underline
            let color = NSColor(red: 0.8, green: 0, blue: 0, alpha: 1.0)
            let tag = "__fu"
            let undoLabel = "划线"
            let contents = "free:underline"
            let selectionUnion = lineRects.dropFirst().reduce(lineRects[0]) { $0.union($1) }

            let existing = freeMarkupAnnotations(on: page, tag: tag, contents: contents, type: annType)
                .filter { $0.bounds.intersects(selectionUnion) }

            var added: [PDFAnnotation] = []
            var removedSnapshots: [FreeAnnotationSnapshot] = []

            if existing.isEmpty {
                added.append(contentsOf: Self.makeMarkupAnnotations(
                    lineRects: lineRects,
                    selection: nil,
                    type: annType,
                    color: color,
                    tag: tag,
                    page: page,
                    contents: contents
                ))
            } else {
                let existingUnion = existing.dropFirst().reduce(existing[0].bounds) { $0.union($1.bounds) }
                let isFullyCovered = lineRects.allSatisfy { existingUnion.insetBy(dx: -1, dy: -1).contains($0) }
                removedSnapshots = existing.map { FreeAnnotationSnapshot(ann: $0) }
                existing.forEach { page.removeAnnotation($0) }
                if !isFullyCovered {
                    added.append(contentsOf: Self.makeMarkupAnnotations(
                        lineRects: lineRects,
                        selection: nil,
                        type: annType,
                        color: color,
                        tag: tag,
                        page: page,
                        contents: contents
                    ))
                }
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

        private func handleFreeHighlight(
            page: PDFPage,
            lineRects: [CGRect]
        ) {
            let tag = "__fh"
            let contents = "free:highlight"
            let color = PDFHighlightAnnotationFactory.nativeHighlightColor
            let existing = freeMarkupAnnotations(on: page, tag: tag, contents: contents, type: .highlight)
            let selectionUnion = lineRects.dropFirst().reduce(lineRects[0]) { $0.union($1) }

            // Toggle off: if the selection lands on an existing highlight, remove it. Matching uses
            // annotation `bounds` (always reliable) instead of re-derived quad points, which round-trip
            // unreliably through PDFKit and previously broke "tap again to remove".
            let hits = existing.filter { Self.highlight($0, matchesSelection: selectionUnion) }
            if !hits.isEmpty {
                let removedSnapshots = hits.map { FreeAnnotationSnapshot(ann: $0) }
                hits.forEach { page.removeAnnotation($0) }
                registerUndoAnnotationMutation(
                    page: page,
                    added: [],
                    removedSnapshots: removedSnapshots,
                    label: "高亮"
                )
                triggerAnnotationSave(immediate: true)
                return
            }

            // Nothing highlighted under the selection → create one. Build from `lineRects` directly so
            // the geometry stays consistent across save / restore.
            guard let annotation = Self.makeHighlightAnnotation(
                lineRects: lineRects,
                selection: nil,
                page: page,
                color: color,
                userName: tag,
                contents: contents
            ) else { return }

            page.addAnnotation(annotation)
            registerUndoAnnotationMutation(
                page: page,
                added: [annotation],
                removedSnapshots: [],
                label: "高亮"
            )
            triggerAnnotationSave(immediate: true)
        }

        /// Whether a highlight annotation is the one the user intends to toggle off, judged purely on
        /// bounds geometry: the selection sits inside the highlight, the highlight sits inside the
        /// selection, or the two overlap by at least half of the smaller rect.
        private static func highlight(_ ann: PDFAnnotation, matchesSelection selectionUnion: CGRect) -> Bool {
            let bounds = ann.bounds
            guard bounds.intersects(selectionUnion) else { return false }
            if bounds.insetBy(dx: -3, dy: -3).contains(selectionUnion) { return true }
            if selectionUnion.insetBy(dx: -3, dy: -3).contains(bounds) { return true }
            let intersection = bounds.intersection(selectionUnion)
            let intersectionArea = intersection.width * intersection.height
            let minArea = min(bounds.width * bounds.height, selectionUnion.width * selectionUnion.height)
            return minArea > 0 && (intersectionArea / minArea) >= 0.5
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
                        bounds: ann.bounds,
                        color: ann.color ?? NSColor.systemRed
                    ))
                    page.removeAnnotation(ann)
                }
            }

            // 添加新划线标注
            var addedAnnotations: [PDFAnnotation] = []
            for rect in lineRects {
                let ann = PDFAnnotation(bounds: rect, forType: .underline, withProperties: nil)
                ann.color = NSColor(red: 0.8, green: 0, blue: 0, alpha: 1.0)
                ann.userName = noteId
                ann.contents = "note:\(noteId)"
                page.addAnnotation(ann)
                addedAnnotations.append(ann)
            }

            triggerAnnotationSave()

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
                ann.color = snap.color
                ann.userName = snap.noteId
                ann.contents = "note:\(snap.noteId)"
                page.addAnnotation(ann)
                restoredAnnotations.append(ann)
            }

            triggerAnnotationSave()

            // 通知 Swift 层恢复/删除笔记
            // 删除新笔记
            try? BridgeService.shared.deleteNote(id: newNoteInfo.id)
            // 恢复旧笔记
            for info in deletedNotesInfo {
                _ = try? BridgeService.shared.saveNote(
                    pdfPath: info.pdfPath,
                    pdfName: info.pdfName,
                    pageIndex: info.pageIndex,
                    content: info.content,
                    note: info.note,
                    boundsStr: info.boundsStr
                )
            }
            // 刷新笔记列表
            NotificationCenter.default.post(name: .refreshNotesList, object: nil)

            // 注册重做操作
            let capturedDeletedNotesInfo = deletedNotesInfo
            undo.registerUndo(withTarget: self) { coordinator in
                // 重做：重新删除旧笔记，创建新笔记
                for info in capturedDeletedNotesInfo {
                    try? BridgeService.shared.deleteNote(id: info.id)
                }
                _ = try? BridgeService.shared.saveNote(
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
                NotificationCenter.default.post(name: .refreshNotesList, object: nil)
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
            let entries = (try? BridgeService.shared.listVocabulary()) ?? []
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
            let notes = (try? BridgeService.shared.listNotesByPdf(pdfPath: filePath)) ?? []
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
                ann.color = NSColor(red: 0.8, green: 0, blue: 0, alpha: 1.0)
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
                    color: NSColor(red: 0.8, green: 0, blue: 0, alpha: 1.0),
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
            pendingRestoreTargetPage = nil
            pendingRestoreTimeoutWorkItem?.cancel()
            isJumping = true
            pdfView.go(to: page)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        @objc func jumpToSelectionBounds(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }

            let boundsStr = notification.userInfo?["boundsStr"] as? String ?? ""
            pendingRestoreTargetPage = nil
            pendingRestoreTimeoutWorkItem?.cancel()
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
            guard let scrollView = pdfView.enclosingScrollView,
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

            if let target = pendingRestoreTargetPage {
                if pageIndex != target { return }
                pendingRestoreTimeoutWorkItem?.cancel()
                pendingRestoreTargetPage = nil
                // Layout not updated yet — measured offset is ~0; keep DB scroll until `didLiveScroll`.
                lastKnownPageIndex = pageIndex
                parent.onPageChange(pageIndex, lastScrollOffset)
                return
            }

            let offset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = offset
            parent.onPageChange(pageIndex, offset)
        }

        /// Debounced live-scroll handler — saves position ~0.5 s after scrolling stops.
        @objc func didLiveScroll(_ notification: Notification) {
            if pendingRestoreTargetPage != nil { return }
            scrollDebounce?.invalidate()
            scrollDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, let pdfView = self.pdfView,
                      let currentPage = pdfView.currentPage,
                      let doc = pdfView.document else { return }
                let pageIndex = doc.index(for: currentPage)
                let offset = self.scrollOffset(for: pdfView)
                self.lastKnownPageIndex = pageIndex
                self.lastScrollOffset = offset
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
            try? BridgeService.shared.saveReadingPosition(
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak pdfView] in
                guard let pdfView else { return }
                pdfView.go(to: page)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    Self.applyNormalizedScrollOffset(offset, to: pdfView)
                }
            }
            NotificationCenter.default.post(name: .windowDidDeminiaturize, object: nil)
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
            let pageIndex = doc.index(for: currentPage)
            try? BridgeService.shared.saveReadingPosition(
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

            selectionDebounce?.invalidate()
            selectionDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak pdfView] _ in
                guard let self, let pdfView,
                      let currentPage = pdfView.currentPage,
                      let doc = pdfView.document else { return }
                let word = selectedStr.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { return }
                let sentence = self.extractSentence(from: pdfView, containing: selection) ?? word

                // Build per-line rects for precise annotation.
                let rawLines = selection.selectionsByLine()
                let lineSelections = rawLines.isEmpty ? [selection] : rawLines
                let lineRects = lineSelections.compactMap { s -> CGRect? in
                    let r = s.bounds(for: currentPage)
                    return r.isEmpty ? nil : r
                }
                let overallBounds = selection.bounds(for: currentPage)
                let boundsStr = lineRects.isEmpty
                    ? NSStringFromRect(overallBounds)
                    : lineRects.map { NSStringFromRect($0) }.joined(separator: "|")

                let pageIndex = doc.index(for: currentPage)
                let menuAnchor = Self.menuAnchor(boundsInPage: overallBounds,
                                                 page: currentPage, pdfView: pdfView)
                DispatchQueue.main.async {
                    self.parent.onTextSelected(word, sentence, overallBounds, boundsStr, pageIndex, menuAnchor)
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
            let sentence = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
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
                let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.contains(word), t.count >= 4, t.count <= 2000 { return t }
            }
            return nil
        }

        // MARK: Scroll offset

        private func scrollOffset(for pdfView: PDFView) -> Double {
            guard let sv = pdfView.enclosingScrollView else { return 0 }
            let h = sv.documentView?.bounds.height ?? 1
            guard h > 0 else { return 0 }
            return max(0, min(1, sv.documentVisibleRect.minY / h))
        }

        // MARK: Helpers

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
            ann.color = color
            ann.userName = tag
            if let contents = contents {
                ann.contents = contents
            }
            page.addAnnotation(ann)
            return ann
        }
    }
}

// MARK: - Free markup persistence

/// Persists free-form highlights / underlines (not vocabulary- or note-linked) outside the PDF.
///
/// The app is sandboxed and cannot reliably write back into the user's (often large) PDF file, so
/// these annotations are stored in `UserDefaults` keyed by file path and re-applied on load — the
/// same non-destructive model vocabulary highlights already use via the database.
enum FreeMarkupStore {
    struct Item: Codable {
        var page: Int
        var boundsStr: String
        var type: String // "highlight" | "underline"
    }

    private static func key(for filePath: String) -> String { "freemarks::\(filePath)" }

    static func load(_ filePath: String) -> [Item] {
        guard !filePath.isEmpty,
              let data = UserDefaults.standard.data(forKey: key(for: filePath)),
              let items = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ filePath: String, items: [Item]) {
        guard !filePath.isEmpty else { return }
        let defaults = UserDefaults.standard
        if items.isEmpty {
            defaults.removeObject(forKey: key(for: filePath))
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key(for: filePath))
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let addHighlight           = Notification.Name("addHighlight")
    static let removeHighlight        = Notification.Name("removeHighlight")
    static let addFreeAnnotation      = Notification.Name("addFreeAnnotation")
    static let addUnderlineNote       = Notification.Name("addUnderlineNote")
    static let removeUnderlineNote    = Notification.Name("removeUnderlineNote")
    static let saveReadingPositionNow = Notification.Name("saveReadingPositionNow")
    static let windowDidDeminiaturize = Notification.Name("windowDidDeminiaturize")
    static let refreshNotesList       = Notification.Name("refreshNotesList")
}

// MARK: - Supporting types

struct TranslationBubbleRequest: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let sentence: String
    let bounds: CGRect
    let boundsStr: String
    let page: Int
    var result: TranslationResult?
    /// Set when `translate` throws; shown at the bottom of the bubble.
    var translationError: String?
    var existingEntryId: String?
    /// When true, the selection is a multi-word phrase/sentence, not a single word.
    let isSentenceMode: Bool
    /// When true, the bubble shows an AI reading explanation instead of a translation.
    let isExplanationMode: Bool
    /// Must compare all fields that affect the bubble UI. Comparing only `id` made SwiftUI
    /// treat success/error updates as «unchanged» and skip redrawing — users saw「翻译未完成」
    /// with an empty detail area even when `translationError` was set.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.word == rhs.word
            && lhs.sentence == rhs.sentence
            && lhs.bounds == rhs.bounds
            && lhs.boundsStr == rhs.boundsStr
            && lhs.page == rhs.page
            && lhs.result == rhs.result
            && lhs.translationError == rhs.translationError
            && lhs.existingEntryId == rhs.existingEntryId
            && lhs.isSentenceMode == rhs.isSentenceMode
            && lhs.isExplanationMode == rhs.isExplanationMode
    }
}

/// 用于撤销操作时存储笔记信息
struct NoteUndoInfo {
    let id: String
    let pdfPath: String
    let pdfName: String
    let pageIndex: UInt32
    let content: String
    let note: String
    let boundsStr: String
}
