import SwiftUI
import PDFKit
import AppKit

struct PDFReaderView: View {
    let document: PdfDocument
    @ObservedObject var selectionActionBarModel: SelectionActionBarModel
    @ObservedObject var readingPopoverModel: ReadingPopoverModel
    let viewportTransitionController: ReaderViewportTransitionController
    let onExplainSelection: (PDFSelectionContext) -> Void
    let onOpenNotes: () -> Void
    @EnvironmentObject private var appState: AppState

    @State private var noteAnchorPositions: [NoteAnchorPosition] = []
    private var activeNoteReview: ActiveNoteReview? { readingPopoverModel.noteReview }
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
                onTextSelected: { selection in
                    guard !selection.word.isEmpty else { return }
                    readingPopoverModel.dismiss()
                    let readerFrame = proxy.frame(in: .named(ReaderRootCoordinateSpace.name))
                    let rootSelectionRect = selection.selectionAnchorRect.offsetBy(
                        dx: readerFrame.minX,
                        dy: readerFrame.minY
                    )
                    selectionActionBarModel.present(
                        anchorRect: rootSelectionRect,
                        hasExistingNote: exactUnderlineNote(markups: selection.effectivePageMarkups) != nil,
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
                translationSelection: translationSelectionEmphasis,
                onTranslationViewportChanged: {
                    readingPopoverModel.dismiss()
                },
                noteAnchorRequests: noteAnchorRequests,
                onNoteAnchorsChanged: { anchors in
                    if noteAnchorPositions != anchors {
                        noteAnchorPositions = anchors
                    }
                },
                viewportTransitionController: viewportTransitionController
            )

            NoteAnchorOverlayView(anchors: noteAnchorPositions) { anchor in
                let frame = proxy.frame(in: .named(ReaderRootCoordinateSpace.name))
                openNoteReview(anchor.offsetBy(dx: frame.minX, dy: frame.minY))
            }
            .zIndex(1)

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
            Button("") {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        }
        .id(document.id)
        .onChange(of: document.id) { _, _ in
            readingPopoverModel.dismiss()
            noteAnchorPositions = []
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshNotesList)) { _ in
            appState.refreshNotes()
        }
    }

    private var noteAnchorRequests: [NoteAnchorRequest] {
        NoteAnchorCatalog.savedNotes(appState.notes.filter { $0.pdfPath == document.filePath })
    }

    private var translationSelectionEmphasis: TranslationSelectionEmphasis? {
        guard let request = readingPopoverModel.request,
              request.pdfPath == document.filePath else { return nil }
        return TranslationSelectionEmphasis(
            id: request.id,
            filePath: request.pdfPath,
            pageMarkups: request.effectivePageMarkups
        )
    }

    private func openNoteReview(_ anchor: NoteAnchorPosition) {
        let reference = appState.notes.first(where: { $0.id == anchor.noteId })
        let notes = appState.notes.filter { note in
            note.pdfPath == document.filePath &&
                (note.id == anchor.noteId ||
                 (note.pageIndex == reference?.pageIndex && note.boundsStr == reference?.boundsStr))
        }
        selectionActionBarModel.dismiss()
        if notes.isEmpty {
            guard let markup = anchor.pageMarkup else { return }
            presentNoteDraft(UnderlineNoteDraft(
                word: markup.text, boundsStr: markup.boundsStr, page: markup.pageIndex,
                pageMarkups: [markup], anchor: anchor.point, anchorRect: anchor.anchorRect,
                appendingNoteId: nil, existingNoteText: ""
            ))
            return
        }
        let review = ActiveNoteReview(id: anchor.id, anchor: anchor, notes: notes.sorted { $0.createdAt < $1.createdAt })
        readingPopoverModel.presentNoteReview(review, actions: .init(
            openNotes: {
                readingPopoverModel.dismiss()
                onOpenNotes()
            },
            saveItem: { noteId, index, text, previous, count in
                let saved = appState.saveNoteItem(
                    noteId: noteId, itemIndex: index, text: text,
                    expectedText: previous, expectedCount: count
                )
                if saved { refreshActiveNoteReview(matching: review) }
                return saved
            },
            append: { text in
                guard let current = activeNoteReview,
                      let id = current.notes.last?.id,
                      appState.appendNoteItem(noteId: id, text: text) else { return false }
                refreshActiveNoteReview(matching: current)
                return true
            },
            deleteItem: deleteNoteReviewItem,
            deleteAll: {
                guard let current = activeNoteReview else { return }
                deleteAllNotes(in: current)
            }
        ))
    }

    private func presentNoteDraft(_ draft: UnderlineNoteDraft) {
        selectionActionBarModel.dismiss()
        readingPopoverModel.presentNoteDraft(draft) { text in
            if let id = draft.appendingNoteId {
                if !appState.appendNoteItem(noteId: id, text: text) {
                    appState.showToast("保存笔记失败")
                    return
                }
            } else {
                saveUnderlineNote(word: draft.word, noteText: text,
                                  pageMarkups: draft.effectivePageMarkups, preferredPage: draft.page)
            }
            readingPopoverModel.dismiss()
        }
    }

    private func deleteNoteReviewItem(noteId: String, itemIndex: Int) {
        guard let review = activeNoteReview,
              let note = appState.notes.first(where: { $0.id == noteId }),
              let remainingText = NoteTextList.removingItem(at: itemIndex, from: note.note)
        else {
            appState.showToast("删除笔记失败")
            return
        }

        do {
            if remainingText.isEmpty {
                try ReaderPersistence.shared.deleteNoteRemovingUnderline(
                    id: note.id,
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
                try ReaderPersistence.shared.deleteNoteRemovingUnderline(
                    id: note.id,
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
        // A final editor flush after dismissal must not reopen the popover.
        guard activeNoteReview?.id == review.id else { return }
        guard let reference = review.notes.first else {
            readingPopoverModel.dismiss()
            return
        }

        let remainingNotes = appState.notes.filter { note in
            note.pdfPath == reference.pdfPath &&
                note.pageIndex == reference.pageIndex &&
                note.boundsStr == reference.boundsStr
        }
        guard !remainingNotes.isEmpty else {
            readingPopoverModel.dismiss()
            return
        }

        readingPopoverModel.updateNoteReview(ActiveNoteReview(
            id: review.id,
            anchor: review.anchor,
            notes: remainingNotes.sorted { $0.createdAt < $1.createdAt }
        ))
    }

    // MARK: - Selection Action Bar

    private func handleSelectionAction(
        _ action: SelectionActionBarAction,
        selection: SelectionInfo,
        translationAnchorRect: CGRect
    ) {
        switch action {
        case .translate:
            selectionActionBarModel.dismiss()
            requestTranslation(
                word: selection.word,
                sentence: selection.sentence,
                bounds: selection.bounds,
                boundsStr: selection.boundsStr,
                page: selection.page,
                pageMarkups: selection.effectivePageMarkups,
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
                    boundsStr: selection.boundsStr,
                    pageMarkups: selection.effectivePageMarkups
                )
            )
        case .highlight:
            postFreeAnnotations(type: "highlight", selection: selection)
        case .underline:
            postFreeAnnotations(type: "underline", selection: selection)
        case .addNote:
            let existingNote = exactUnderlineNote(markups: selection.effectivePageMarkups)
            presentNoteDraft(UnderlineNoteDraft(
                word: selection.word,
                boundsStr: selection.boundsStr,
                page: selection.page,
                pageMarkups: selection.effectivePageMarkups,
                anchor: selection.menuAnchor,
                anchorRect: translationAnchorRect,
                appendingNoteId: existingNote?.id,
                existingNoteText: existingNote?.note ?? ""
            ))
        case .removeNote:
            if let existingNote = exactUnderlineNote(markups: selection.effectivePageMarkups) {
                removeUnderlineNote(existingNote)
            }
        case .close:
            break
        }
    }

    private func postFreeAnnotations(type: String, selection: SelectionInfo) {
        ReaderEventBus.shared.postFreeAnnotations(
            type: type,
            markups: selection.effectivePageMarkups,
            filePath: document.filePath
        )
    }

    private func exactUnderlineNote(markups: [PDFPageMarkup]) -> NoteEntry? {
        guard let existingNotes = try? ReaderPersistence.shared.listNotesByPdf(pdfPath: document.filePath) else {
            return nil
        }
        return existingNotes.first { note in
            UnderlineNoteMergePolicy.sameGeometry(notePageMarkups(note), markups)
        }
    }

    private func notePageMarkups(_ note: NoteEntry) -> [PDFPageMarkup] {
        PDFPageMarkupCodec.decode(
            note.pageMarkups,
            fallbackPage: Int(note.pageIndex),
            fallbackBoundsStr: note.boundsStr,
            fallbackText: note.content
        )
    }

    private func removeUnderlineNote(_ note: NoteEntry) {
        try? ReaderPersistence.shared.deleteNoteRemovingUnderline(
            id: note.id,
            filePath: document.filePath
        )
        appState.refreshNotes()
        appState.showToast("已移除笔记")
    }

    /// 创建非空笔记并添加关联下划线：子区域不变，部分重叠则扩展/合并。
    private func saveUnderlineNote(
        word: String,
        noteText: String,
        pageMarkups: [PDFPageMarkup],
        preferredPage: Int
    ) {
        let trimmedNoteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNoteText.isEmpty else {
            appState.showToast("请输入笔记内容")
            return
        }

        ReaderPersistence.shared.initializeIfNeeded()

        let newMarkups = PDFPageMarkupCodec.normalized(pageMarkups)
        guard !newMarkups.isEmpty else {
            appState.showToast("保存笔记失败")
            return
        }

        guard let existingNotes = try? ReaderPersistence.shared.listNotesByPdf(pdfPath: document.filePath) else {
            appState.showToast("保存笔记失败")
            return
        }

        if existingNotes.contains(where: {
            UnderlineNoteMergePolicy.sameGeometry(notePageMarkups($0), newMarkups)
        }) {
            appState.showToast("该选区已有笔记")
            return
        }

        // If the new selection is entirely inside an existing note, keep the existing note unchanged.
        if existingNotes.contains(where: { note in
            UnderlineNoteMergePolicy.markups(newMarkups, areCoveredBy: notePageMarkups(note))
        }) {
            appState.showToast("已在现有笔记范围内")
            return
        }

        let overlappingNotes = existingNotes.filter { note in
            UnderlineNoteMergePolicy.markups(newMarkups, overlap: notePageMarkups(note))
        }

        if !overlappingNotes.isEmpty {
            mergeUnderlineNote(
                word: word,
                noteText: trimmedNoteText,
                preferredPage: preferredPage,
                newMarkups: newMarkups,
                overlappingNotes: overlappingNotes
            )
            return
        }

        let primary = newMarkups.first(where: { $0.pageIndex == preferredPage }) ?? newMarkups[0]
        createUnderlineNote(
            word: word,
            noteText: trimmedNoteText,
            boundsStr: primary.boundsStr,
            page: primary.pageIndex,
            pageMarkups: newMarkups,
            deletedNotesInfo: []
        )
    }

    private func mergeUnderlineNote(
        word: String,
        noteText: String,
        preferredPage: Int,
        newMarkups: [PDFPageMarkup],
        overlappingNotes: [NoteEntry]
    ) {
        let deletedNotesInfo = overlappingNotes.map(NoteUndoInfo.init)
        let mergedMarkups = UnderlineNoteMergePolicy.mergePageMarkups(
            overlappingNotes.map { notePageMarkups($0) } + [newMarkups]
        )
        let primary = mergedMarkups.first(where: { $0.pageIndex == preferredPage }) ?? mergedMarkups[0]
        let mergedContent = UnderlineNoteMergePolicy.mergedNoteContent(
            existing: overlappingNotes.map(\.content),
            new: word
        )
        let mergedNoteText = UnderlineNoteMergePolicy.mergedNoteText(
            existing: overlappingNotes.map(\.note),
            new: noteText
        )

        let mergedNote = ReaderPersistence.shared.makeNoteHistorySnapshot(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(primary.pageIndex),
            content: mergedContent,
            note: mergedNoteText,
            boundsStr: primary.boundsStr,
            pageMarkups: mergedMarkups
        )
        do {
            try ReaderPersistence.shared.applyNoteHistorySnapshot(
                removing: deletedNotesInfo,
                restoring: [mergedNote]
            )
        } catch {
            appState.showToast("保存笔记失败")
            return
        }

        ReaderEventBus.shared.postAddUnderlineNote(
            noteId: mergedNote.id,
            markups: mergedMarkups,
            filePath: document.filePath,
            undoInfo: mergedNote,
            deletedNotesInfo: deletedNotesInfo
        )
        appState.refreshNotes()
        appState.showToast("已扩展笔记")
    }

    @discardableResult
    private func createUnderlineNote(
        word: String,
        noteText: String,
        boundsStr: String,
        page: Int,
        pageMarkups: [PDFPageMarkup],
        deletedNotesInfo: [NoteUndoInfo],
        toastMessage: String = "已添加笔记"
    ) -> NoteEntry? {
        guard let noteEntry = try? ReaderPersistence.shared.saveNote(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(page),
            content: word,
            note: noteText,
            boundsStr: boundsStr,
            pageMarkups: pageMarkups
        ) else {
            appState.showToast("保存笔记失败")
            return nil
        }

        ReaderEventBus.shared.postAddUnderlineNote(
            noteId: noteEntry.id,
            markups: pageMarkups,
            filePath: document.filePath,
            undoInfo: NoteUndoInfo(noteEntry),
            deletedNotesInfo: deletedNotesInfo
        )

        appState.refreshNotes()
        appState.showToast(toastMessage)
        return noteEntry
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
                                     pageMarkups: [PDFPageMarkup],
                                     selectionAnchorRect: CGRect) {
        ReaderPersistence.shared.initializeIfNeeded()

        // Determine if this is sentence mode (multi-word selection)
        let isSentenceMode = word.split(separator: " ").count > 3 || word.count > 25

        // Resolve the "already saved" state up front (synchronously) so the bubble renders the
        // correct saved/unsaved state on its very first frame. An entry is the *same word at the
        // same position* — keyed by word + context (sentence hash) — so the same spelling in a
        // different context (different sentence) is a separate entry and can still be added.
        let sentenceHash = ReadingSessionService.sentenceHash(sentence)
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
            page: page, pageMarkups: pageMarkups,
            selectionAnchorRect: selectionAnchorRect,
            result: nil, translationError: nil,
            existingEntryId: existingEntryId,
            isSentenceMode: isSentenceMode
        )
        let overlay = readingPopoverModel
        overlay.present(request)
        overlay.bindRetryHandler { request in
            Self.launchTranslation(on: overlay, request: request, skipCache: true)
        }
        Self.launchTranslation(on: overlay, request: request, skipCache: false)
    }

    @MainActor
    private static func launchTranslation(
        on overlay: ReadingPopoverModel,
        request: TranslationBubbleRequest,
        skipCache: Bool
    ) {
        let requestId = request.id
        let isSentenceMode = request.isSentenceMode
        let word = request.word
        let sentence = request.sentence

        let task = Task {
            @MainActor func applyPartial(_ partial: TranslationResult) {
                overlay.applyPartial(partial, requestID: requestId)
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
                        skipCache: skipCache,
                        onPartial: { partial in applyPartial(partial) }
                    )
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    overlay.complete(result, requestID: requestId)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    var detail = TranslationErrorFormatter.userMessage(from: error)
                    if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detail = "翻译失败：\(String(describing: error))"
                    }
                    overlay.fail(detail, requestID: requestId)
                }
            }
        }
        overlay.track(task)
    }
}
