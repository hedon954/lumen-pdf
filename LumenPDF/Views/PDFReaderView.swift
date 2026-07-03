import SwiftUI
import PDFKit
import AppKit

struct PDFReaderView: View {
    let document: PdfDocument
    let onExplainSelection: (PDFSelectionContext) -> Void
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
                        if let noteId = draft.appendingNoteId {
                            appendUnderlineNoteText(noteId: noteId, existingNoteText: draft.existingNoteText, noteText: noteText)
                        } else {
                            saveUnderlineNote(
                                word: draft.word,
                                noteText: noteText,
                                boundsStr: draft.boundsStr,
                                page: draft.page
                            )
                        }
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
                            if req.isSentenceMode {
                                saveSentenceToNote(result: result, request: req)
                            } else {
                                saveToDiary(result: result, request: req)
                            }
                        },
                        onDelete: { deletedId, savedToNote in
                            deleteTranslationSave(id: deletedId, savedToNote: savedToNote, request: req)
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
                ReaderEventBus.shared.postSaveReadingPositionNow(filePath: document.filePath)
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
                onExplainSelection(
                    PDFSelectionContext(
                        pdfPath: document.filePath,
                        pdfName: document.fileName,
                        pageIndex: sel.page,
                        selectedText: sel.word,
                        surroundingText: sel.sentence,
                        bounds: sel.bounds,
                        boundsStr: sel.boundsStr
                    )
                )
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "highlighter", label: "高亮") {
                postFreeAnnotation(type: "highlight", boundsStr: sel.boundsStr, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "underline", label: "划线") {
                postFreeAnnotation(type: "underline", boundsStr: sel.boundsStr, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            if let existingNote = exactUnderlineNote(boundsStr: sel.boundsStr, page: sel.page) {
                actionBarBtn(icon: "plus.bubble", label: "添加笔记") {
                    underlineDraft = UnderlineNoteDraft(
                        word: sel.word,
                        boundsStr: sel.boundsStr,
                        page: sel.page,
                        anchor: sel.menuAnchor,
                        appendingNoteId: existingNote.id,
                        existingNoteText: existingNote.note
                    )
                }
                Divider().frame(height: 26)
                actionBarBtn(icon: "note.text", label: "取消笔记") {
                    saveUnderlineNote(word: sel.word, noteText: "", boundsStr: sel.boundsStr, page: sel.page)
                    pendingSelection = nil
                }
            } else {
                actionBarBtn(icon: "note.text", label: "笔记") {
                    underlineDraft = UnderlineNoteDraft(
                        word: sel.word,
                        boundsStr: sel.boundsStr,
                        page: sel.page,
                        anchor: sel.menuAnchor,
                        appendingNoteId: nil,
                        existingNoteText: ""
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
        ReaderEventBus.shared.postFreeAnnotation(
            type: type,
            boundsStr: boundsStr,
            page: page,
            filePath: document.filePath
        )
    }

    private func exactUnderlineNote(boundsStr: String, page: Int) -> NoteEntry? {
        guard let existingNotes = try? ReaderPersistence.shared.listNotesByPdf(pdfPath: document.filePath) else {
            return nil
        }
        return existingNotes.first { note in
            note.pageIndex == UInt32(page) && note.boundsStr == boundsStr
        }
    }

    private func appendUnderlineNoteText(noteId: String, existingNoteText: String, noteText: String) {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appState.showToast("请输入笔记内容")
            return
        }
        _ = try? ReaderPersistence.shared.updateNote(
            id: noteId,
            note: NoteTextList.appending(trimmed, to: existingNoteText)
        )
        appState.refreshNotes()
        appState.showToast("已追加笔记")
    }

    /// 创建笔记并添加关联下划线：相同选区 toggle，子区域不变，部分重叠则扩展/合并。
    private func saveUnderlineNote(word: String, noteText: String, boundsStr: String, page: Int) {
        ReaderPersistence.shared.initializeIfNeeded()

        let newRects = Self.parseAnnotationRectsStatic(boundsStr)
        guard !newRects.isEmpty else {
            appState.showToast("保存笔记失败")
            return
        }

        guard let existingNotes = try? ReaderPersistence.shared.listNotesByPdf(pdfPath: document.filePath) else {
            appState.showToast("保存笔记失败")
            return
        }

        let samePageNotes = existingNotes.filter { $0.pageIndex == UInt32(page) }

        // Same selection keeps the toggle behavior: tap/draw the exact same underline again to remove it.
        if let match = samePageNotes.first(where: { $0.boundsStr == boundsStr }) {
            try? ReaderPersistence.shared.deleteNote(id: match.id)
            ReaderEventBus.shared.postRemoveUnderlineNote(
                noteId: match.id,
                page: page,
                filePath: document.filePath
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
            try? ReaderPersistence.shared.deleteNote(id: note.id)
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
                _ = try? ReaderPersistence.shared.saveNote(
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
        guard let noteEntry = try? ReaderPersistence.shared.saveNote(
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

        ReaderEventBus.shared.postAddUnderlineNote(
            noteId: noteEntry.id,
            page: page,
            boundsStr: boundsStr,
            filePath: document.filePath,
            undoInfo: NoteUndoInfo(
                id: noteEntry.id,
                pdfPath: document.filePath,
                pdfName: document.fileName,
                pageIndex: UInt32(page),
                content: word,
                note: noteText,
                boundsStr: boundsStr
            ),
            deletedNotesInfo: deletedNotesInfo
        )

        appState.refreshNotes()
        appState.showToast(toastMessage)
        return noteEntry
    }

    /// 静态方法解析 boundsStr，供多处使用
    private static func parseAnnotationRectsStatic(_ boundsStr: String) -> [CGRect] {
        AnnotationBoundsCodec.parse(boundsStr)
    }

    private static func annotationBoundsString(from rects: [CGRect]) -> String {
        AnnotationBoundsCodec.string(from: rects)
    }

    private static func rects(_ candidates: [CGRect], areCoveredBy existing: [CGRect]) -> Bool {
        UnderlineNoteMergePolicy.rects(candidates, areCoveredBy: existing)
    }

    private static func rects(_ lhs: [CGRect], overlap rhs: [CGRect]) -> Bool {
        UnderlineNoteMergePolicy.rects(lhs, overlap: rhs)
    }

    private static func mergedNoteContent(existing: [String], new: String) -> String {
        UnderlineNoteMergePolicy.mergedNoteContent(existing: existing, new: new)
    }

    private static func mergedNoteText(existing: [String], new: String) -> String {
        UnderlineNoteMergePolicy.mergedNoteText(existing: existing, new: new)
    }

    private static func mergeAnnotationRects(_ rects: [CGRect]) -> [CGRect] {
        UnderlineNoteMergePolicy.mergeAnnotationRects(rects)
    }

    // MARK: - Document loaded

    private func handleDocumentLoaded(totalPages: Int) {
        appState.totalPages = totalPages
        try? ReaderPersistence.shared.upsertPdfDocument(
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
        ReaderPersistence.shared.initializeIfNeeded()

        // Determine if this is sentence mode (multi-word selection)
        let isSentenceMode = word.split(separator: " ").count > 3 || word.count > 25

        // Resolve the "already saved" state up front (synchronously) so the bubble renders the
        // correct saved/unsaved state on its very first frame. An entry is the *same word at the
        // same position* — keyed by word + context (sentence hash) — so the same spelling in a
        // different context (different sentence) is a separate entry and can still be added.
        var existingEntryId: String?
        if !isSentenceMode {
            let hash = session.sentenceHash(sentence)
            if let existing = try? ReaderPersistence.shared.getVocabularyByWordAndHash(word: word, sentenceHash: hash) {
                existingEntryId = existing.id
                ReaderPersistence.shared.incrementQueryCount(id: existing.id)
            }
        }

        translationRequest = TranslationBubbleRequest(
            word: word, sentence: sentence,
            bounds: bounds, boundsStr: boundsStr,
            page: page, result: nil, translationError: nil,
            existingEntryId: existingEntryId,
            isSentenceMode: isSentenceMode
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
                    result = try await ReaderPersistence.shared.translateSentenceStreaming(
                        sentence: word,
                        onPartial: { partial in applyPartial(partial) }
                    )
                } else {
                    result = try await ReaderPersistence.shared.translateStreaming(
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

    // MARK: - Save to vocabulary

    @discardableResult
    private func saveToDiary(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        let hash = session.sentenceHash(request.sentence)
        guard let entry = try? ReaderPersistence.shared.saveVocabulary(
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

        ReaderEventBus.shared.postAddHighlight(
            entryId: entry.id,
            page: Int(entry.pageIndex),
            boundsStr: request.boundsStr,
            filePath: document.filePath
        )
        appState.refreshVocabulary()
        appState.showToast("已保存「\(entry.word)」")
        return entry.id
    }

    // MARK: - Save sentence translation to notes

    @discardableResult
    private func saveSentenceToNote(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        ReaderPersistence.shared.initializeIfNeeded()

        let noteText = result.contextSentenceTranslation.isEmpty
            ? result.contextTranslation
            : result.contextSentenceTranslation

        guard let noteEntry = try? ReaderPersistence.shared.saveNote(
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
        ReaderEventBus.shared.postAddUnderlineNote(
            noteId: noteEntry.id,
            page: request.page,
            boundsStr: request.boundsStr,
            filePath: document.filePath
        )

        appState.refreshNotes()
        appState.showToast("已保存到笔记")
        return noteEntry.id
    }

    private func deleteTranslationSave(id: String, savedToNote: Bool, request: TranslationBubbleRequest) {
        if savedToNote {
            try? ReaderPersistence.shared.deleteNote(id: id)
            ReaderEventBus.shared.postRemoveUnderlineNote(
                noteId: id,
                page: request.page,
                filePath: document.filePath
            )
            appState.refreshNotes()
            appState.showToast("已从笔记删除")
        } else {
            try? ReaderPersistence.shared.deleteVocabulary(id: id)
            ReaderEventBus.shared.postRemoveHighlight(
                entryId: id,
                page: request.page,
                filePath: document.filePath
            )
            appState.refreshVocabulary()
            appState.showToast("已从单词本删除")
        }
    }
}
