import Foundation
import UniformTypeIdentifiers

@MainActor
final class ReadingGuideService {
    private let bridge = BridgeService.shared

    func submitQuestion(
        _ question: String,
        imageURLs: [URL],
        session: ExplanationSession,
        onSessionChange: @escaping ExplanationSessionApply
    ) {
        bridge.initializeIfNeeded()

        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let compressedContext = Self.compressedExplanationContext(
            summary: session.summary,
            messages: session.messages
        )
        var displayedQuestion = trimmedQuestion.isEmpty ? "直接解释" : trimmedQuestion
        if !imageURLs.isEmpty {
            let names = imageURLs.map(\.lastPathComponent).joined(separator: "、")
            displayedQuestion += "\n\n图片：\(names)"
        }
        let userMessage = ExplanationMessage(
            role: .user,
            content: displayedQuestion
        )
        let focus = Self.explanationFocusPrompt(
            userQuestion: trimmedQuestion,
            compressedContext: compressedContext,
            originalSelection: PDFExtractedTextCollapser.collapse(session.selection.selectedText),
            originalContext: PDFExtractedTextCollapser.collapse(session.selection.surroundingText)
        )
        let retryRequest = ExplanationRetryRequest(focus: focus, imageURLs: imageURLs)
        let assistantMessage = ExplanationMessage(
            role: .assistant,
            content: "",
            retryRequest: retryRequest
        )

        let pending = onSessionChange { current in
            guard current.id == session.id, GuideConversationPolicy.canSend(current) else {
                return nil
            }
            var updated = current
            updated.messages.append(userMessage)
            updated.messages.append(assistantMessage)
            updated.summary = compressedContext
            updated.isLoading = true
            updated.errorMessage = nil
            updated.inFlightAssistantID = assistantMessage.id
            return updated
        }
        guard let pending else { return }

        execute(
            retryRequest,
            assistantID: assistantMessage.id,
            sessionID: pending.id,
            selection: PDFExtractedTextCollapser.collapse(pending.selection.selectedText),
            context: PDFExtractedTextCollapser.collapse(pending.selection.surroundingText),
            onSessionChange: onSessionChange
        )
    }

    func retryMessage(
        _ messageID: UUID,
        session: ExplanationSession,
        onSessionChange: @escaping ExplanationSessionApply
    ) {
        guard let message = session.messages.first(where: { $0.id == messageID }),
              message.role == .assistant,
              let request = message.retryRequest
        else { return }

        let pending = onSessionChange { current in
            guard current.id == session.id, !current.isLoading else {
                return nil
            }
            var updated = current
            updated.messages = Self.updatingAssistantMessage(
                in: updated.messages,
                id: messageID,
                content: "",
                isError: false,
                retryRequest: request
            )
            updated.isLoading = true
            updated.errorMessage = nil
            updated.inFlightAssistantID = messageID
            return updated
        }
        guard let pending else { return }

        execute(
            request,
            assistantID: messageID,
            sessionID: pending.id,
            selection: PDFExtractedTextCollapser.collapse(pending.selection.selectedText),
            context: PDFExtractedTextCollapser.collapse(pending.selection.surroundingText),
            onSessionChange: onSessionChange
        )
    }

    private func execute(
        _ request: ExplanationRetryRequest,
        assistantID: UUID,
        sessionID: UUID,
        selection: String,
        context: String,
        onSessionChange: @escaping ExplanationSessionApply
    ) {
        Task {
            do {
                let preparedImages = try await Task.detached(priority: .userInitiated) {
                    try Self.prepareImages(from: request.imageURLs)
                }.value
                let images = preparedImages.map {
                    ImageAttachment(
                        fileName: $0.fileName,
                        mimeType: $0.mimeType,
                        base64Data: $0.base64Data
                    )
                }
                let result = try await bridge.explainSelectionStreaming(
                    selection: selection,
                    context: context,
                    focus: request.focus,
                    images: images,
                    onPartial: { partial in
                        _ = onSessionChange { current in
                            guard current.id == sessionID,
                                  current.inFlightAssistantID == assistantID else { return nil }
                            var updated = current
                            updated.messages = Self.updatingAssistantMessage(
                                in: updated.messages,
                                id: assistantID,
                                content: partial.contextExplanation,
                                retryRequest: request
                            )
                            updated.errorMessage = nil
                            return updated
                        }
                    }
                )

                let explanation = result.contextExplanation
                if GuideConversationPolicy.isEmptySuccess(explanation) {
                    throw GuideEmptyReplyError(
                        message: GuideConversationPolicy.emptyReplyMessage(tokens: result.completionTokens)
                    )
                }

                _ = onSessionChange { current in
                    guard current.id == sessionID,
                          current.inFlightAssistantID == assistantID else { return nil }
                    var completed = current
                    completed.messages = Self.updatingAssistantMessage(
                        in: completed.messages,
                        id: assistantID,
                        content: explanation,
                        retryRequest: nil
                    )
                    completed.errorMessage = nil
                    completed.isLoading = false
                    completed.inFlightAssistantID = nil
                    return completed
                }
            } catch {
                _ = onSessionChange { current in
                    guard current.id == sessionID,
                          current.inFlightAssistantID == assistantID else { return nil }
                    var failed = current
                    let detail = Self.guideErrorMessage(from: error)
                    failed.messages = Self.updatingAssistantMessage(
                        in: failed.messages,
                        id: assistantID,
                        content: detail,
                        isError: true,
                        retryRequest: request
                    )
                    failed.errorMessage = nil
                    failed.isLoading = false
                    failed.inFlightAssistantID = nil
                    return failed
                }
            }
        }
    }

    nonisolated private static func prepareImages(from urls: [URL]) throws -> [PreparedGuideImage] {
        try urls.map(prepareImage)
    }

    nonisolated private static func prepareImage(from url: URL) throws -> PreparedGuideImage {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let sourceData = try Data(contentsOf: url, options: .mappedIfSafe)
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let extensionType = UTType(filenameExtension: url.pathExtension)
        guard let mimeType = resourceType?.preferredMIMEType
            ?? extensionType?.preferredMIMEType
        else {
            throw GuideImagePreparationError.unknownMimeType(url.lastPathComponent)
        }

        return PreparedGuideImage(
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            base64Data: sourceData.base64EncodedString()
        )
    }

    func saveAssistantMessage(_ message: ExplanationMessage, session: ExplanationSession) -> String? {
        let noteText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noteText.isEmpty else { return nil }

        guard let noteEntry = try? bridge.saveNote(
            pdfPath: session.selection.pdfPath,
            pdfName: session.selection.pdfName,
            pageIndex: UInt32(session.selection.pageIndex),
            content: session.selection.selectedText,
            note: noteText,
            boundsStr: session.selection.boundsStr
        ) else {
            return nil
        }

        ReaderEventBus.shared.postAddUnderlineNote(
            noteId: noteEntry.id,
            page: session.selection.pageIndex,
            boundsStr: session.selection.boundsStr,
            filePath: session.selection.pdfPath
        )
        return noteEntry.id
    }

    func deleteSavedMessages(in session: ExplanationSession) {
        for noteId in session.savedNoteIdsByMessageId.values {
            try? bridge.deleteNote(id: noteId)
            ReaderEventBus.shared.postRemoveUnderlineNote(
                noteId: noteId,
                page: session.selection.pageIndex,
                filePath: session.selection.pdfPath
            )
        }
    }

    private static func updatingAssistantMessage(
        in messages: [ExplanationMessage],
        id: UUID,
        content: String,
        isError: Bool = false,
        retryRequest: ExplanationRetryRequest?
    ) -> [ExplanationMessage] {
        messages.map { message in
            guard message.id == id else { return message }
            var updated = message
            updated.content = content
            updated.isError = isError
            updated.retryRequest = retryRequest
            return updated
        }
    }

    private static func guideErrorMessage(from error: Error) -> String {
        if let empty = error as? GuideEmptyReplyError {
            return empty.localizedDescription
        }
        let detail = TranslationErrorFormatter.userMessage(from: error)
            .replacingOccurrences(of: "翻译失败：", with: "AI 调用失败：")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "AI 调用失败：请检查 LLM 设置后重试。"
        }
        return detail
    }

    private static func compressedExplanationContext(
        summary: String,
        messages: [ExplanationMessage]
    ) -> String {
        let compactSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let completedMessages = messages.filter {
            !$0.isError
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let recentMessages = completedMessages.suffix(20).map { message in
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role): \(truncated(message.content, limit: message.role == .user ? 220 : 620))"
        }.joined(separator: "\n---\n")

        let olderCount = max(0, completedMessages.count - 20)
        var sections: [String] = []
        if !compactSummary.isEmpty {
            sections.append("Existing compressed context:\n\(truncated(compactSummary, limit: 700))")
        }
        if olderCount > 0 {
            let olderDigest = completedMessages.prefix(olderCount).map { message in
                let role = message.role == .user ? "User" : "Assistant"
                return "- \(role): \(truncated(message.content, limit: 180))"
            }.joined(separator: "\n")
            sections.append("Older messages digest:\n\(olderDigest)")
        }
        if !recentMessages.isEmpty {
            sections.append("Recent messages:\n\(recentMessages)")
        }
        return truncated(sections.joined(separator: "\n\n"), limit: 3_600)
    }

    private static func explanationFocusPrompt(
        userQuestion: String,
        compressedContext: String,
        originalSelection: String,
        originalContext: String
    ) -> String {
        var parts: [String] = []
        parts.append("Original selected text / 原始选中文案（不要压缩或改写，以此为准）:\n\(originalSelection)")
        if !originalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           originalContext != originalSelection {
            parts.append("Original surrounding context / 原始上下文（不要压缩或改写）:\n\(originalContext)")
        }
        let question = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty {
            parts.append("Current user question / 当前用户问题:\n\(question)")
        }
        let context = compressedContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.isEmpty {
            parts.append("Conversation context summary / 对话上下文摘要（用于多轮追问，必要时纠正或延续前文）:\n\(context)")
        }
        parts.append("""
        Conversation style / 对话衔接要求:
        - Continue the same reading conversation instead of restarting the explanation.
        - Answer the newest user question directly.
        - Ground every answer in the original selected text.
        - Prefer concise paragraphs or short bullets over repeating the full prior explanation.
        """)
        return parts.joined(separator: "\n\n")
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: max(0, limit))
        return String(text[..<index]) + "..."
    }
}

private struct PreparedGuideImage: Sendable {
    let fileName: String
    let mimeType: String
    let base64Data: String
}

private enum GuideEmptyReplyError: LocalizedError {
    case message(String)

    init(message: String) {
        self = .message(message)
    }

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}

private enum GuideImagePreparationError: LocalizedError {
    case unknownMimeType(String)

    var errorDescription: String? {
        switch self {
        case .unknownMimeType(let name):
            return "无法识别图片「\(name)」的格式。"
        }
    }
}
