import Foundation
import PDFKit

enum WorkspaceSearchPDFExtractor {
    static func originalChunks(
        from document: PDFDocument?,
        pdfPath: String,
        pdfName: String
    ) -> [WorkspaceSearchOriginalDraft] {
        guard let document, !pdfPath.isEmpty else { return [] }

        var drafts: [WorkspaceSearchOriginalDraft] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let raw = page.string,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            let chunks = WorkspaceSearchPageChunker.chunks(from: raw)
            for (offset, text) in chunks.enumerated() {
                drafts.append(
                    WorkspaceSearchOriginalDraft(
                        id: "original:\(pdfPath)#\(pageIndex)#\(offset)",
                        pdfPath: pdfPath,
                        pdfName: pdfName,
                        pageIndex: pageIndex,
                        text: text
                    )
                )
            }
        }
        return drafts
    }

    static func underlines(
        items: [FreeMarkupStore.Item],
        document: PDFDocument?,
        pdfPath: String,
        pdfName: String
    ) -> [WorkspaceSearchUnderlineDraft] {
        guard let document, !pdfPath.isEmpty else { return [] }

        return items.compactMap { item in
            let text = markupText(item, in: document)
            guard !text.isEmpty else { return nil }
            return WorkspaceSearchUnderlineDraft(
                id: "\(pdfPath)#\(item.page)#\(item.boundsStr)#\(item.type)",
                pdfPath: pdfPath,
                pdfName: pdfName,
                pageIndex: item.page,
                boundsStr: item.boundsStr,
                text: text,
                type: item.type
            )
        }
    }

    static func markupText(_ item: FreeMarkupStore.Item, in document: PDFDocument) -> String {
        guard let page = document.page(at: item.page) else { return "" }
        let rects = AnnotationBoundsCodec.parse(item.boundsStr)
        let texts = rects.compactMap { rect -> String? in
            page.selection(for: rect)?.string
        }
        return ContextSentenceFormatting.displayParagraph(texts.joined(separator: " "))
    }
}

enum WorkspaceSearchSourceMapper {
    static func notes(from entries: [NoteEntry]) -> [WorkspaceSearchNoteDraft] {
        entries.map { note in
            WorkspaceSearchNoteDraft(
                id: note.id,
                pdfPath: note.pdfPath,
                pdfName: note.pdfName,
                pageIndex: Int(note.pageIndex),
                boundsStr: note.boundsStr,
                content: note.content,
                noteStorage: note.note
            )
        }
    }

    static func words(from entries: [VocabularyEntry]) -> [WorkspaceSearchWordDraft] {
        entries.map { word in
            WorkspaceSearchWordDraft(
                id: word.id,
                word: word.word,
                sentence: word.sentence,
                pdfPath: word.pdfPath,
                pdfName: word.pdfName,
                pageIndex: Int(word.pageIndex),
                boundsStr: word.selectionBounds,
                phonetic: word.phonetic,
                partOfSpeech: word.partOfSpeech,
                contextTranslation: word.contextTranslation,
                contextExplanation: word.contextExplanation,
                etymology: word.etymology,
                generalDefinition: word.generalDefinition,
                contextSentenceTranslation: word.contextSentenceTranslation
            )
        }
    }

    static func explanations(from session: ExplanationSession?) -> [WorkspaceSearchExplanationDraft] {
        guard let session else { return [] }
        return session.messages.compactMap { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, !message.isError else { return nil }
            return WorkspaceSearchExplanationDraft(
                id: message.id.uuidString,
                pdfPath: session.selection.pdfPath,
                pdfName: session.selection.pdfName,
                pageIndex: session.selection.pageIndex,
                boundsStr: session.selection.boundsStr,
                roleTitle: message.role == .assistant ? "AI 解释" : "追问",
                content: content
            )
        }
    }
}

enum WorkspaceSearchIndex {
    @MainActor
    static func records(
        for kind: WorkspaceSearchKind,
        notes: [NoteEntry],
        words: [VocabularyEntry],
        document: PDFDocument?,
        pdfPath: String?,
        pdfName: String?,
        markupItems: [FreeMarkupStore.Item],
        session: ExplanationSession?
    ) -> [WorkspaceSearchRecord] {
        let path = pdfPath ?? ""
        let name = pdfName ?? ""
        switch kind {
        case .note:
            return WorkspaceSearchCatalog.records(
                notes: WorkspaceSearchSourceMapper.notes(from: notes)
            )
        case .word:
            return WorkspaceSearchCatalog.records(
                words: WorkspaceSearchSourceMapper.words(from: words)
            )
        case .underline:
            return WorkspaceSearchCatalog.records(
                underlines: WorkspaceSearchPDFExtractor.underlines(
                    items: markupItems,
                    document: document,
                    pdfPath: path,
                    pdfName: name
                )
            )
        case .original:
            return WorkspaceSearchCatalog.records(
                originalChunks: WorkspaceSearchPDFExtractor.originalChunks(
                    from: document,
                    pdfPath: path,
                    pdfName: name
                )
            )
        case .explanation:
            return WorkspaceSearchCatalog.records(
                explanations: WorkspaceSearchSourceMapper.explanations(from: session)
            )
        }
    }
}
