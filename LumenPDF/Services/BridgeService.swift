import Foundation

// File-scope type-aliased references to UniFFI top-level functions.
// BridgeService methods have the same names → would shadow them inside the class.
// By capturing them here at file scope, we can call them unambiguously.
private let _initialize: (String, AppConfig) throws -> Void              = initialize(dbPath:config:)
private let _updateLlmConfig: (AppConfig) throws -> Void                 = updateLlmConfig(config:)
private let _saveVocabulary: (SaveVocabularyRequest) throws -> VocabularyEntry = saveVocabulary(req:)
private let _getVocabularyEntry: (String) throws -> VocabularyEntry?     = getVocabularyEntry(id:)
private let _getVocabByHash: (String, String) throws -> VocabularyEntry? = getVocabularyByWordAndHash(word:sentenceHash:)
private let _listVocabulary: () throws -> [VocabularyEntry]              = listVocabulary
private let _deleteVocabulary: (String) throws -> Void                   = deleteVocabulary(id:)
private let _updateAnnotation: (String, String) throws -> Void           = updateVocabularyAnnotation(id:annotationId:)
private let _incrementQueryCount: (String) throws -> Void                = incrementVocabularyQueryCount(id:)
private let _updateVocabulary: (UpdateVocabularyRequest) throws -> VocabularyEntry = updateVocabulary(req:)
private let _upsertPdf: (UpsertPdfRequest) throws -> PdfDocument         = upsertPdfDocument(req:)
private let _savePosition: (String, UInt32, Double) throws -> Void       = saveReadingPosition(filePath:page:scrollOffset:)
private let _listPdfDocuments: () throws -> [PdfDocument]                = listPdfDocuments
private let _deletePdfDocument: (String) throws -> Void                  = deletePdfDocument(filePath:)
private let _saveNote: (SaveNoteRequest) throws -> NoteEntry             = saveNote(req:)
private let _listNotes: () throws -> [NoteEntry]                         = listNotes
private let _listNotesByPdf: (String) throws -> [NoteEntry]              = listNotesByPdf(pdfPath:)
private let _deleteNote: (String) throws -> Void                         = deleteNote(id:)
private let _updateNote: (UpdateNoteRequest) throws -> NoteEntry         = updateNote(req:)
private let _exportNotesMarkdown: (String?) throws -> String             = exportNotesMarkdown(pdfPath:)

/// Wraps all UniFFI-generated top-level calls and manages app initialization.
final class BridgeService {
    static let shared = BridgeService()

    private var isInitialized = false
    private let dbURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LumenPDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("data.db")
    }

    func initializeIfNeeded() {
        guard !isInitialized else { return }
        let baseURL = Self.normalizedLLMBaseURL(
            UserDefaults.standard.string(forKey: "llm_base_url") ?? "https://api.openai.com/v1"
        )
        let config = AppConfig(
            llmBaseUrl: baseURL,
            llmApiKey: KeychainService.loadLLMAPIKey(for: baseURL) ?? "",
            llmModel: UserDefaults.standard.string(forKey: "llm_model") ?? "gpt-4o-mini",
            targetLanguage: UserDefaults.standard.string(forKey: "target_language") ?? "简体中文",
            wordPromptTemplate: UserDefaults.standard.string(forKey: "word_prompt_template") ?? "",
            sentencePromptTemplate: UserDefaults.standard.string(forKey: "sentence_prompt_template") ?? "",
            explanationPromptTemplate: UserDefaults.standard.string(forKey: "explanation_prompt_template") ?? "",
            wordSystemPrompt: UserDefaults.standard.string(forKey: "word_system_prompt") ?? "",
            sentenceSystemPrompt: UserDefaults.standard.string(forKey: "sentence_system_prompt") ?? "",
            explanationSystemPrompt: UserDefaults.standard.string(forKey: "explanation_system_prompt") ?? ""
        )
        guard (try? _initialize(dbURL.path, config)) != nil else {
            // Do not flip isInitialized — allow retry on next launch / next call path.
            return
        }
        isInitialized = true
    }

    /// Hot-swap LLM config — takes effect for the very next translation call.
    func updateConfig(
        baseURL: String,
        apiKey: String,
        model: String,
        targetLanguage: String,
        wordPromptTemplate: String,
        sentencePromptTemplate: String,
        explanationPromptTemplate: String,
        wordSystemPrompt: String,
        sentenceSystemPrompt: String,
        explanationSystemPrompt: String
    ) throws {
        try _updateLlmConfig(AppConfig(
            llmBaseUrl: Self.normalizedLLMBaseURL(baseURL),
            llmApiKey: apiKey,
            llmModel: model,
            targetLanguage: targetLanguage,
            wordPromptTemplate: wordPromptTemplate,
            sentencePromptTemplate: sentencePromptTemplate,
            explanationPromptTemplate: explanationPromptTemplate,
            wordSystemPrompt: wordSystemPrompt,
            sentenceSystemPrompt: sentenceSystemPrompt,
            explanationSystemPrompt: explanationSystemPrompt
        ))
    }

    static func normalizedLLMBaseURL(_ rawValue: String) -> String {
        let fallback = "https://api.openai.com/v1"
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil
        else {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }

        let normalized = components.string ?? trimmed
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Translation

    func translate(word: String, sentence: String) async throws -> TranslationResult {
        let word = PDFExtractedTextCollapser.collapse(word)
        let sentence = PDFExtractedTextCollapser.collapse(sentence)
        let auditID = await beginAudit(
            kind: .wordTranslation,
            input: "选中单词：\(word)\n\n上下文：\(sentence)"
        )
        do {
            // translate(request:) has different param label — no shadowing conflict
            let result = try await LumenPDF.translate(
                request: TranslationRequest(word: word, sentence: sentence)
            )
            await finishAudit(auditID, result: result)
            return result
        } catch {
            await failAudit(auditID, error: error)
            throw error
        }
    }

    /// Translate a full sentence without word-level analysis.
    /// Use this when the user selects a phrase/sentence instead of a single word.
    func translateSentence(sentence: String) async throws -> TranslationResult {
        let sentence = PDFExtractedTextCollapser.collapse(sentence)
        let auditID = await beginAudit(kind: .sentenceTranslation, input: sentence)
        do {
            let result = try await LumenPDF.translateSentence(sentence: sentence)
            await finishAudit(auditID, result: result)
            return result
        } catch {
            await failAudit(auditID, error: error)
            throw error
        }
    }

    /// Streaming word-level translation. `onPartial` fires repeatedly on
    /// `MainActor` while fields stream in; the returned `TranslationResult`
    /// is the final, complete result (also matching the last `onPartial`).
    func translateStreaming(
        word: String,
        sentence: String,
        skipCache: Bool = false,
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        let word = PDFExtractedTextCollapser.collapse(word)
        let sentence = PDFExtractedTextCollapser.collapse(sentence)
        let auditID = await beginAudit(
            kind: .wordTranslation,
            input: "选中单词：\(word)\n\n上下文：\(sentence)"
        )
        let receiver = TranslationStreamReceiver(onPartial: onPartial)
        do {
            let result = try await LumenPDF.translateStreaming(
                request: TranslationRequest(word: word, sentence: sentence),
                callback: receiver,
                skipCache: skipCache
            )
            await finishAudit(auditID, result: result)
            return result
        } catch {
            await failAudit(auditID, error: error)
            throw error
        }
    }

    /// Streaming sentence translation. `onPartial` fires as soon as any
    /// `context_sentence_translation` text is available.
    func translateSentenceStreaming(
        sentence: String,
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        let sentence = PDFExtractedTextCollapser.collapse(sentence)
        let auditID = await beginAudit(kind: .sentenceTranslation, input: sentence)
        let receiver = TranslationStreamReceiver(onPartial: onPartial)
        do {
            let result = try await LumenPDF.translateSentenceStreaming(
                sentence: sentence,
                callback: receiver
            )
            await finishAudit(auditID, result: result)
            return result
        } catch {
            await failAudit(auditID, error: error)
            throw error
        }
    }

    /// Streaming explanation for selected text. The selected text and its surrounding
    /// sentence are sent to the LLM, and partial explanation text is emitted through
    /// `contextExplanation` as it streams back.
    func explainSelectionStreaming(
        selection: String,
        context: String,
        focus: String,
        images: [ImageAttachment],
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        let selection = PDFExtractedTextCollapser.collapse(selection)
        let context = PDFExtractedTextCollapser.collapse(context)
        let imageSummary = images.isEmpty
            ? ""
            : "\n\n附加图片：\(images.map(\.fileName).joined(separator: "、"))"
        let auditID = await beginAudit(
            kind: .selectionExplanation,
            input: "选中文本：\(selection)\n\n上下文：\(context)\n\n关注点：\(focus)\(imageSummary)"
        )
        let receiver = TranslationStreamReceiver(onPartial: onPartial)
        do {
            let result = try await LumenPDF.explainSelectionStreaming(
                selection: selection,
                context: context,
                focus: focus,
                images: images,
                callback: receiver
            )
            await finishAudit(auditID, result: result)
            return result
        } catch {
            await failAudit(auditID, error: error)
            throw error
        }
    }

    func detectImageInputCapability() async throws -> ImageInputCapability {
        // This is internal feature negotiation for the reading inspector, not a
        // reading action initiated by the user. It must not pollute the audit
        // trail or Token/cost statistics.
        try await LumenPDF.detectImageInputCapability()
    }

    private func beginAudit(kind: LLMCallKind, input: String) async -> UUID {
        let model = UserDefaults.standard.string(forKey: "llm_model") ?? ""
        let baseURL = Self.normalizedLLMBaseURL(
            UserDefaults.standard.string(forKey: "llm_base_url") ?? ""
        )
        return await MainActor.run {
            LLMCallLogStore.shared.begin(
                kind: kind,
                model: model,
                baseURL: baseURL,
                input: input
            )
        }
    }

    private func finishAudit(_ id: UUID, result: TranslationResult) async {
        let warning = [result.llmErrorMessage, result.fallbackErrorMessage]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        await MainActor.run {
            LLMCallLogStore.shared.finish(
                id: id,
                output: Self.auditOutput(from: result),
                source: result.source,
                promptTokens: result.promptTokens,
                completionTokens: result.completionTokens,
                totalTokens: result.totalTokens,
                warning: warning,
                failed: result.isCompleteFailure
            )
        }
    }

    private func failAudit(_ id: UUID, error: Error) async {
        let message = TranslationErrorFormatter.userMessage(from: error)
        await MainActor.run {
            LLMCallLogStore.shared.fail(id: id, error: message)
        }
    }

    private static func auditOutput(from result: TranslationResult) -> String {
        let sections = [
            result.contextTranslation,
            result.contextSentenceTranslation,
            result.contextExplanation,
            result.etymology,
            result.generalDefinition
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Vocabulary

    @discardableResult
    func saveVocabulary(
        word: String, sentence: String, sentenceHash: String,
        pdfPath: String, pdfName: String, pageIndex: UInt32,
        selectionBounds: String, phonetic: String, partOfSpeech: String,
        contextTranslation: String, contextExplanation: String,
        etymology: String,
        generalDefinition: String, contextSentenceTranslation: String,
        translationSource: String,
        annotationId: String? = nil
    ) throws -> VocabularyEntry {
        try _saveVocabulary(SaveVocabularyRequest(
            word: word, sentence: sentence, sentenceHash: sentenceHash,
            pdfPath: pdfPath, pdfName: pdfName, pageIndex: pageIndex,
            selectionBounds: selectionBounds, phonetic: phonetic,
            partOfSpeech: partOfSpeech, contextTranslation: contextTranslation,
            contextExplanation: contextExplanation, etymology: etymology,
            generalDefinition: generalDefinition,
            contextSentenceTranslation: contextSentenceTranslation,
            translationSource: translationSource, annotationId: annotationId
        ))
    }

    func getVocabularyEntry(id: String) throws -> VocabularyEntry? {
        try _getVocabularyEntry(id)
    }

    func getVocabularyByWordAndHash(word: String, sentenceHash: String) throws -> VocabularyEntry? {
        try _getVocabByHash(word, sentenceHash)
    }

    func listVocabulary() throws -> [VocabularyEntry] {
        try _listVocabulary()
    }

    func deleteVocabulary(id: String) throws {
        try _deleteVocabulary(id)
    }

    func updateVocabularyAnnotation(id: String, annotationId: String) throws {
        try _updateAnnotation(id, annotationId)
    }

    func incrementQueryCount(id: String) {
        try? _incrementQueryCount(id)
    }

    @discardableResult
    func updateVocabulary(id: String, phonetic: String, partOfSpeech: String,
                          contextTranslation: String, contextExplanation: String,
                          etymology: String,
                          generalDefinition: String, contextSentenceTranslation: String) throws -> VocabularyEntry {
        try _updateVocabulary(UpdateVocabularyRequest(
            id: id, phonetic: phonetic, partOfSpeech: partOfSpeech,
            contextTranslation: contextTranslation, contextExplanation: contextExplanation,
            etymology: etymology,
            generalDefinition: generalDefinition,
            contextSentenceTranslation: contextSentenceTranslation
        ))
    }

    // MARK: - PDF Documents

    @discardableResult
    func upsertPdfDocument(filePath: String, fileName: String, totalPages: UInt32) throws -> PdfDocument {
        try _upsertPdf(UpsertPdfRequest(filePath: filePath, fileName: fileName, totalPages: totalPages))
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) throws {
        try _savePosition(filePath, page, scrollOffset)
    }

    func listPdfDocuments() throws -> [PdfDocument] {
        try _listPdfDocuments()
    }

    func deletePdfDocument(filePath: String) throws {
        try _deletePdfDocument(filePath)
    }

    // MARK: - Notes

    @discardableResult
    func saveNote(
        pdfPath: String, pdfName: String, pageIndex: UInt32,
        content: String, note: String, boundsStr: String
    ) throws -> NoteEntry {
        let normalizedContent = ContextSentenceFormatting.displayParagraph(content)
        return try _saveNote(SaveNoteRequest(
            pdfPath: pdfPath,
            pdfName: pdfName,
            pageIndex: pageIndex,
            content: normalizedContent,
            note: NoteTextList.storageString(from: note),
            boundsStr: boundsStr
        ))
    }

    func listNotes() throws -> [NoteEntry] {
        try _listNotes()
    }

    func listNotesByPdf(pdfPath: String) throws -> [NoteEntry] {
        try _listNotesByPdf(pdfPath)
    }

    func deleteNote(id: String) throws {
        try _deleteNote(id)
    }

    @discardableResult
    func updateNote(id: String, note: String) throws -> NoteEntry {
        try _updateNote(UpdateNoteRequest(id: id, note: NoteTextList.storageString(from: note)))
    }

    func exportNotesMarkdown(pdfPath: String? = nil) -> String {
        let notes: [NoteEntry]
        if let pdfPath {
            notes = (try? _listNotesByPdf(pdfPath)) ?? []
        } else {
            notes = (try? _listNotes()) ?? []
        }
        guard !notes.isEmpty else { return "# 笔记导出\n\n暂无笔记。" }

        var markdown = "# 笔记导出 - LumenPDF\n\n"
        let grouped = Dictionary(grouping: notes) { $0.pdfName }
        for pdfName in grouped.keys.sorted() {
            markdown += "## 📄 \(pdfName)\n\n"
            for note in (grouped[pdfName] ?? []).sorted(by: { $0.pageIndex < $1.pageIndex }) {
                markdown += "### Page \(note.pageIndex + 1)\n\n"
                markdown += "> \(note.content)\n\n"
                let noteMarkdown = NoteTextList.markdown(note.note)
                if !noteMarkdown.isEmpty {
                    markdown += "**笔记：**\n\n\(noteMarkdown)\n\n"
                }
                markdown += "---\n\n"
            }
        }
        return markdown
    }
}

// MARK: - Streaming receiver

/// Adapter from UniFFI's `TranslationStreamCallback` protocol to a Swift
/// `@MainActor` closure. Rust may invoke `onProgress` on any thread (the
/// streaming consumer task), so we hop to `MainActor` before touching UI.
private final class TranslationStreamReceiver: TranslationStreamCallback {
    private let onPartial: @MainActor (TranslationResult) -> Void

    init(onPartial: @escaping @MainActor (TranslationResult) -> Void) {
        self.onPartial = onPartial
    }

    func onProgress(partial: TranslationResult) {
        let snapshot = partial
        Task { @MainActor in
            self.onPartial(snapshot)
        }
    }
}
