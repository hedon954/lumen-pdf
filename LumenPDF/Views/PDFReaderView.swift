import SwiftUI
import PDFKit
import AppKit

struct PDFReaderView: View {
    let document: PdfDocument
    @ObservedObject var selectionActionBarModel: SelectionActionBarModel
    @ObservedObject var translationOverlayModel: TranslationOverlayModel
    let viewportTransitionController: ReaderViewportTransitionController
    let onExplainSelection: (PDFSelectionContext) -> Void
    let onOpenNotes: () -> Void
    @EnvironmentObject private var appState: AppState
    @StateObject private var session = ReadingSessionService()

    @State private var underlineDraft: UnderlineNoteDraft?
    @State private var noteAnchorPositions: [NoteAnchorPosition] = []
    @State private var activeNoteReview: ActiveNoteReview?
    // totalPages is kept as a local state for the initial load callback,
    // then written to appState so ContentView can display it in the toolbar.

    var body: some View {
        GeometryReader { proxy in
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
                onTextSelected: { word, sentence, bounds, boundsStr, page, anchor, selectionAnchorRect in
                    guard !word.isEmpty else { return }
                    let selection = SelectionInfo(
                        word: word, sentence: sentence,
                        bounds: bounds, boundsStr: boundsStr,
                        page: page, menuAnchor: anchor,
                        selectionAnchorRect: selectionAnchorRect
                    )
                    let readerFrame = proxy.frame(in: .named(ReaderRootCoordinateSpace.name))
                    let rootSelectionRect = selectionAnchorRect.offsetBy(
                        dx: readerFrame.minX,
                        dy: readerFrame.minY
                    )
                    selectionActionBarModel.present(
                        anchorRect: rootSelectionRect,
                        hasExistingNote: exactUnderlineNote(boundsStr: boundsStr, page: page) != nil,
                        onAction: { action in
                            handleSelectionAction(
                                action,
                                selection: selection,
                                translationAnchorRect: rootSelectionRect
                            )
                        }
                    )
                },
                onClearSelection: {
                    selectionActionBarModel.dismiss()
                },
                onDocumentLoaded: { total in
                    handleDocumentLoaded(totalPages: total)
                },
                noteAnchorRequests: noteAnchorRequests,
                onNoteAnchorsChanged: { anchors in
                    if noteAnchorPositions != anchors {
                        noteAnchorPositions = anchors
                    }
                },
                viewportTransitionController: viewportTransitionController
            )

            if let draft = underlineDraft {
                UnderlineNoteDraftView(
                    draft: draft,
                    availableSize: proxy.size,
                    onCancel: {
                        underlineDraft = nil
                    },
                    onSave: { noteText in
                        let trimmedNoteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedNoteText.isEmpty else {
                            appState.showToast("请输入笔记内容")
                            return
                        }
                        if let noteId = draft.appendingNoteId {
                            appendUnderlineNoteText(
                                noteId: noteId,
                                existingNoteText: draft.existingNoteText,
                                noteText: trimmedNoteText
                            )
                        } else {
                            saveUnderlineNote(
                                word: draft.word,
                                noteText: trimmedNoteText,
                                boundsStr: draft.boundsStr,
                                page: draft.page
                            )
                        }
                        underlineDraft = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(2)
            }

            NoteAnchorOverlayView(anchors: noteAnchorPositions) { anchor in
                openNoteReview(anchor)
            }
            .zIndex(1)

            if let review = activeNoteReview {
                NoteReviewPopoverView(
                    review: review,
                    availableSize: proxy.size,
                    onOpenNotes: {
                        onOpenNotes()
                        activeNoteReview = nil
                    },
                    onDeleteItem: { noteId, itemIndex in
                        deleteNoteReviewItem(noteId: noteId, itemIndex: itemIndex)
                    },
                    onDeleteAll: {
                        deleteAllNotes(in: review)
                    },
                    onClose: {
                        activeNoteReview = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(3)
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
        }
        .id(document.id)
        .onReceive(NotificationCenter.default.publisher(for: .refreshNotesList)) { _ in
            appState.refreshNotes()
        }
    }

    private var noteAnchorRequests: [NoteAnchorRequest] {
        let notes = appState.notes.filter { $0.pdfPath == document.filePath && !$0.boundsStr.isEmpty }
        let grouped = Dictionary(grouping: notes) { note in
            "\(note.pageIndex)|\(note.boundsStr)"
        }
        return grouped.values.compactMap { group in
            guard let first = group.sorted(by: { $0.createdAt < $1.createdAt }).first else { return nil }
            return NoteAnchorRequest(
                id: "note-anchor|\(first.pageIndex)|\(first.boundsStr)",
                noteId: first.id,
                pageIndex: Int(first.pageIndex),
                boundsStr: first.boundsStr
            )
        }
    }

    private func openNoteReview(_ anchor: NoteAnchorPosition) {
        let anchorBounds = appState.notes.first(where: { $0.id == anchor.noteId })?.boundsStr
        let notes = appState.notes.filter { note in
            note.pdfPath == document.filePath &&
                Int(note.pageIndex) == anchor.pageIndex &&
                (note.id == anchor.noteId || note.boundsStr == anchorBounds)
        }
        guard !notes.isEmpty else { return }
        closeTranslationOverlay()
        underlineDraft = nil
        selectionActionBarModel.dismiss()
        activeNoteReview = ActiveNoteReview(id: anchor.id, anchor: anchor, notes: notes.sorted { $0.createdAt < $1.createdAt })
    }

    private func closeOtherReadingOverlays() {
        closeTranslationOverlay()
        activeNoteReview = nil
    }

    private func closeTranslationOverlay() {
        translationOverlayModel.dismiss()
    }

    private func deleteNoteReviewItem(noteId: String, itemIndex: Int) {
        guard let review = activeNoteReview,
              let note = review.notes.first(where: { $0.id == noteId }),
              let remainingText = NoteTextList.removingItem(at: itemIndex, from: note.note)
        else {
            appState.showToast("删除笔记失败")
            return
        }

        do {
            if remainingText.isEmpty {
                try ReaderPersistence.shared.deleteNote(id: note.id)
                ReaderEventBus.shared.postRemoveUnderlineNote(
                    noteId: note.id,
                    page: Int(note.pageIndex),
                    filePath: note.pdfPath
                )
            } else {
                try ReaderPersistence.shared.updateNote(id: note.id, note: remainingText)
            }
            refreshActiveNoteReview(matching: review)
            appState.showToast("已删除这条笔记")
        } catch {
            appState.showToast("删除笔记失败")
        }
    }

    private func deleteAllNotes(in review: ActiveNoteReview) {
        var deletedCount = 0
        for note in review.notes {
            do {
                try ReaderPersistence.shared.deleteNote(id: note.id)
                ReaderEventBus.shared.postRemoveUnderlineNote(
                    noteId: note.id,
                    page: Int(note.pageIndex),
                    filePath: note.pdfPath
                )
                deletedCount += 1
            } catch {
                continue
            }
        }

        refreshActiveNoteReview(matching: review)
        if deletedCount == review.notes.count {
            appState.showToast("已删除这里的全部笔记")
        } else if deletedCount > 0 {
            appState.showToast("部分笔记删除失败")
        } else {
            appState.showToast("删除笔记失败")
        }
    }

    private func refreshActiveNoteReview(matching review: ActiveNoteReview) {
        appState.refreshNotes()
        guard let reference = review.notes.first else {
            activeNoteReview = nil
            return
        }

        let remainingNotes = appState.notes.filter { note in
            note.pdfPath == reference.pdfPath &&
                note.pageIndex == reference.pageIndex &&
                note.boundsStr == reference.boundsStr
        }
        guard !remainingNotes.isEmpty else {
            activeNoteReview = nil
            return
        }

        activeNoteReview = ActiveNoteReview(
            id: review.id,
            anchor: review.anchor,
            notes: remainingNotes.sorted { $0.createdAt < $1.createdAt }
        )
    }

    // MARK: - Selection Action Bar

    private func handleSelectionAction(
        _ action: SelectionActionBarAction,
        selection: SelectionInfo,
        translationAnchorRect: CGRect
    ) {
        switch action {
        case .translate:
            requestTranslation(
                word: selection.word,
                sentence: selection.sentence,
                bounds: selection.bounds,
                boundsStr: selection.boundsStr,
                page: selection.page,
                selectionAnchorRect: translationAnchorRect
            )
        case .explain:
            onExplainSelection(
                PDFSelectionContext(
                    pdfPath: document.filePath,
                    pdfName: document.fileName,
                    pageIndex: selection.page,
                    selectedText: selection.word,
                    surroundingText: selection.sentence,
                    bounds: selection.bounds,
                    boundsStr: selection.boundsStr
                )
            )
        case .highlight:
            postFreeAnnotation(type: "highlight", boundsStr: selection.boundsStr, page: selection.page)
        case .underline:
            postFreeAnnotation(type: "underline", boundsStr: selection.boundsStr, page: selection.page)
        case .addNote:
            closeOtherReadingOverlays()
            let existingNote = exactUnderlineNote(boundsStr: selection.boundsStr, page: selection.page)
            underlineDraft = UnderlineNoteDraft(
                word: selection.word,
                boundsStr: selection.boundsStr,
                page: selection.page,
                anchor: selection.menuAnchor,
                anchorRect: selection.selectionAnchorRect,
                appendingNoteId: existingNote?.id,
                existingNoteText: existingNote?.note ?? ""
            )
        case .removeNote:
            if let existingNote = exactUnderlineNote(boundsStr: selection.boundsStr, page: selection.page) {
                removeUnderlineNote(existingNote)
            }
        case .close:
            break
        }
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

    private func removeUnderlineNote(_ note: NoteEntry) {
        try? ReaderPersistence.shared.deleteNote(id: note.id)
        ReaderEventBus.shared.postRemoveUnderlineNote(
            noteId: note.id,
            page: Int(note.pageIndex),
            filePath: document.filePath
        )
        appState.refreshNotes()
        appState.showToast("已移除笔记")
    }

    /// 创建非空笔记并添加关联下划线：子区域不变，部分重叠则扩展/合并。
    private func saveUnderlineNote(word: String, noteText: String, boundsStr: String, page: Int) {
        let trimmedNoteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNoteText.isEmpty else {
            appState.showToast("请输入笔记内容")
            return
        }

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

        if samePageNotes.contains(where: { $0.boundsStr == boundsStr }) {
            appState.showToast("该选区已有笔记")
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
                noteText: trimmedNoteText,
                page: page,
                newRects: newRects,
                overlappingNotes: overlappingNotes
            )
            return
        }

        createUnderlineNote(
            word: word,
            noteText: trimmedNoteText,
            boundsStr: boundsStr,
            page: page,
            deletedNotesInfo: []
        )
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
                                     bounds: CGRect, boundsStr: String, page: Int,
                                     selectionAnchorRect: CGRect) {
        underlineDraft = nil
        activeNoteReview = nil
        ReaderPersistence.shared.initializeIfNeeded()

        // Determine if this is sentence mode (multi-word selection)
        let isSentenceMode = word.split(separator: " ").count > 3 || word.count > 25

        // Resolve the "already saved" state up front (synchronously) so the bubble renders the
        // correct saved/unsaved state on its very first frame. An entry is the *same word at the
        // same position* — keyed by word + context (sentence hash) — so the same spelling in a
        // different context (different sentence) is a separate entry and can still be added.
        let sentenceHash = session.sentenceHash(sentence)
        var existingEntryId: String?
        if !isSentenceMode {
            if let existing = try? ReaderPersistence.shared.getVocabularyByWordAndHash(
                word: word,
                sentenceHash: sentenceHash
            ) {
                existingEntryId = existing.id
                ReaderPersistence.shared.incrementQueryCount(id: existing.id)
            }
        }

        let request = TranslationBubbleRequest(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            word: word, sentence: sentence,
            sentenceHash: sentenceHash,
            bounds: bounds, boundsStr: boundsStr,
            page: page, selectionAnchorRect: selectionAnchorRect,
            result: nil, translationError: nil,
            existingEntryId: existingEntryId,
            isSentenceMode: isSentenceMode
        )
        translationOverlayModel.present(request)

        // Track which translation request this Task belongs to, so a delayed
        // streaming callback from a previous selection can't overwrite the
        // bubble of a fresh one (user dismissed and selected something else).
        let requestId = request.id

        Task {
            // Updates the bubble's `result` field as fields stream in.
            // Captured by both streaming-mode branches below.
            @MainActor func applyPartial(_ partial: TranslationResult) {
                translationOverlayModel.applyPartial(partial, requestID: requestId)
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
                    translationOverlayModel.complete(result, requestID: requestId)
                }
            } catch {
                await MainActor.run {
                    var detail = TranslationErrorFormatter.userMessage(from: error)
                    if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detail = "翻译失败：\(String(describing: error))"
                    }
                    translationOverlayModel.fail(detail, requestID: requestId)
                }
            }
        }
    }
}

private struct NoteAnchorOverlayView: View {
    let anchors: [NoteAnchorPosition]
    let onOpen: (NoteAnchorPosition) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(anchors) { anchor in
                Button {
                    onOpen(anchor)
                } label: {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.accentColor.opacity(0.88), in: Circle())
                        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .help("打开笔记")
                .position(anchor.point)
            }
        }
        .allowsHitTesting(!anchors.isEmpty)
    }
}

private struct NoteReviewPopoverView: View {
    let review: ActiveNoteReview
    let availableSize: CGSize
    let onOpenNotes: () -> Void
    let onDeleteItem: (String, Int) -> Void
    let onDeleteAll: () -> Void
    let onClose: () -> Void

    @State private var pendingDeletion: NoteReviewDeletion?

    private var noteItems: [NoteReviewItem] {
        review.notes.flatMap { note in
            NoteTextList.decode(note.note).enumerated().map { index, markdown in
                NoteReviewItem(
                    id: "\(note.id)#\(index)",
                    noteId: note.id,
                    itemIndex: index,
                    markdown: markdown,
                    createdAt: note.createdAt
                )
            }
        }
    }

    var body: some View {
        ReadingOverlayWindow(
            anchorRect: review.anchor.anchorRect,
            availableSize: availableSize,
            resetID: AnyHashable(review.id),
            configuration: ReadingOverlayWindowConfiguration(
                width: 420,
                initialContentHeight: 300,
                minimumContentHeight: 120,
                dismissesOnBackgroundTap: true
            ),
            onDismiss: onClose,
            header: { header },
            content: { content },
            footer: { footer }
        )
        .alert(item: $pendingDeletion) { deletion in
            switch deletion {
            case let .item(noteId, itemIndex):
                return Alert(
                    title: Text("删除这条笔记？"),
                    message: Text("删除后无法恢复。"),
                    primaryButton: .destructive(Text("删除")) {
                        onDeleteItem(noteId, itemIndex)
                    },
                    secondaryButton: .cancel()
                )
            case let .all(count):
                return Alert(
                    title: Text("删除全部笔记？"),
                    message: Text("这里的 \(count) 条笔记及对应划线都会被删除，且无法恢复。"),
                    primaryButton: .destructive(Text("全部删除"), action: onDeleteAll),
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("笔记")
                .font(.headline)
            Spacer()
            ReadingOverlayMoveHandle()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let first = review.notes.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("原文")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(ContextSentenceFormatting.displayParagraph(first.content))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            ForEach(noteItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let createdAt = ReadingInspectorDateFormat.timestampText(for: item.createdAt) {
                            Text(createdAt)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDeletion = .item(
                                noteId: item.noteId,
                                itemIndex: item.itemIndex
                            )
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .help("删除这条笔记")
                    }
                    MarkdownText(markdown: item.markdown)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                pendingDeletion = .all(count: noteItems.count)
            } label: {
                Label("删除全部", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .disabled(noteItems.isEmpty)
            Spacer()
            Button("打开右侧笔记", action: onOpenNotes)
                .buttonStyle(.borderless)
            Button("关闭", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

private struct NoteReviewItem: Identifiable {
    let id: String
    let noteId: String
    let itemIndex: Int
    let markdown: String
    let createdAt: Int64
}

private enum NoteReviewDeletion: Identifiable {
    case item(noteId: String, itemIndex: Int)
    case all(count: Int)

    var id: String {
        switch self {
        case let .item(noteId, itemIndex):
            return "item|\(noteId)|\(itemIndex)"
        case let .all(count):
            return "all|\(count)"
        }
    }
}
