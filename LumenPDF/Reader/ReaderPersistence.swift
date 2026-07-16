import Foundation

final class ReaderPersistence {
    static let shared = ReaderPersistence()

    private let bridge: BridgeService

    init(bridge: BridgeService = .shared) {
        self.bridge = bridge
    }

    func initializeIfNeeded() {
        bridge.initializeIfNeeded()
    }

    func translateStreaming(
        word: String,
        sentence: String,
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        try await bridge.translateStreaming(word: word, sentence: sentence, onPartial: onPartial)
    }

    func translateSentenceStreaming(
        sentence: String,
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        try await bridge.translateSentenceStreaming(sentence: sentence, onPartial: onPartial)
    }

    @discardableResult
    func saveVocabulary(
        word: String,
        sentence: String,
        sentenceHash: String,
        pdfPath: String,
        pdfName: String,
        pageIndex: UInt32,
        selectionBounds: String,
        phonetic: String,
        partOfSpeech: String,
        contextTranslation: String,
        contextExplanation: String,
        etymology: String,
        generalDefinition: String,
        contextSentenceTranslation: String,
        translationSource: String,
        annotationId: String? = nil
    ) throws -> VocabularyEntry {
        try bridge.saveVocabulary(
            word: word,
            sentence: sentence,
            sentenceHash: sentenceHash,
            pdfPath: pdfPath,
            pdfName: pdfName,
            pageIndex: pageIndex,
            selectionBounds: selectionBounds,
            phonetic: phonetic,
            partOfSpeech: partOfSpeech,
            contextTranslation: contextTranslation,
            contextExplanation: contextExplanation,
            etymology: etymology,
            generalDefinition: generalDefinition,
            contextSentenceTranslation: contextSentenceTranslation,
            translationSource: translationSource,
            annotationId: annotationId
        )
    }

    func getVocabularyByWordAndHash(word: String, sentenceHash: String) throws -> VocabularyEntry? {
        try bridge.getVocabularyByWordAndHash(word: word, sentenceHash: sentenceHash)
    }

    func listVocabulary() throws -> [VocabularyEntry] {
        try bridge.listVocabulary()
    }

    func deleteVocabulary(id: String) throws {
        try bridge.deleteVocabulary(id: id)
    }

    @discardableResult
    func updateVocabulary(
        id: String,
        phonetic: String,
        partOfSpeech: String,
        contextTranslation: String,
        contextExplanation: String,
        etymology: String,
        generalDefinition: String,
        contextSentenceTranslation: String
    ) throws -> VocabularyEntry {
        try bridge.updateVocabulary(
            id: id,
            phonetic: phonetic,
            partOfSpeech: partOfSpeech,
            contextTranslation: contextTranslation,
            contextExplanation: contextExplanation,
            etymology: etymology,
            generalDefinition: generalDefinition,
            contextSentenceTranslation: contextSentenceTranslation
        )
    }

    func incrementQueryCount(id: String) {
        bridge.incrementQueryCount(id: id)
    }

    @discardableResult
    func upsertPdfDocument(filePath: String, fileName: String, totalPages: UInt32) throws -> PdfDocument {
        try bridge.upsertPdfDocument(filePath: filePath, fileName: fileName, totalPages: totalPages)
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) throws {
        try bridge.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
    }

    @discardableResult
    func saveNote(
        pdfPath: String,
        pdfName: String,
        pageIndex: UInt32,
        content: String,
        note: String,
        boundsStr: String
    ) throws -> NoteEntry {
        try bridge.saveNote(
            pdfPath: pdfPath,
            pdfName: pdfName,
            pageIndex: pageIndex,
            content: content,
            note: note,
            boundsStr: boundsStr
        )
    }

    func listNotesByPdf(pdfPath: String) throws -> [NoteEntry] {
        try bridge.listNotesByPdf(pdfPath: pdfPath)
    }

    func deleteNote(id: String) throws {
        try bridge.deleteNote(id: id)
    }

    @discardableResult
    func updateNote(id: String, note: String) throws -> NoteEntry {
        try bridge.updateNote(id: id, note: note)
    }

    func exportNotesMarkdown(pdfPath: String? = nil) -> String {
        bridge.exportNotesMarkdown(pdfPath: pdfPath)
    }
}
