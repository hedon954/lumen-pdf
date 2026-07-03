import Foundation

@MainActor
final class ReadingGuideService {
    private let bridge = BridgeService.shared

    func submitQuestion(
        _ question: String,
        session: ExplanationSession,
        onSessionChange: @escaping @MainActor (ExplanationSession) -> Void
    ) {
        bridge.initializeIfNeeded()

        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let compressedContext = Self.compressedExplanationContext(
            summary: session.summary,
            messages: session.messages
        )
        let userMessage = ExplanationMessage(
            role: .user,
            content: trimmedQuestion.isEmpty ? "直接解释" : trimmedQuestion
        )
        let assistantMessage = ExplanationMessage(role: .assistant, content: "")

        var pending = session
        pending.messages.append(userMessage)
        pending.messages.append(assistantMessage)
        pending.summary = compressedContext
        pending.isLoading = true
        pending.errorMessage = nil
        onSessionChange(pending)

        let sessionId = pending.id
        let assistantId = assistantMessage.id
        let focus = Self.explanationFocusPrompt(
            userQuestion: trimmedQuestion,
            compressedContext: compressedContext,
            originalSelection: session.selection.selectedText,
            originalContext: session.selection.surroundingText
        )

        Task {
            do {
                let result = try await bridge.explainSelectionStreaming(
                    selection: session.selection.selectedText,
                    context: session.selection.surroundingText,
                    focus: focus,
                    onPartial: { partial in
                        var updated = pending
                        guard updated.id == sessionId else { return }
                        updated.messages = Self.updatingAssistantMessage(
                            in: updated.messages,
                            id: assistantId,
                            content: partial.contextExplanation
                        )
                        updated.errorMessage = nil
                        onSessionChange(updated)
                    }
                )

                var completed = pending
                completed.messages = Self.updatingAssistantMessage(
                    in: completed.messages,
                    id: assistantId,
                    content: result.contextExplanation
                )
                completed.errorMessage = nil
                completed.isLoading = false
                onSessionChange(completed)
            } catch {
                var failed = pending
                let detail = Self.guideErrorMessage(from: error)
                failed.messages = Self.updatingAssistantMessage(
                    in: failed.messages,
                    id: assistantId,
                    content: detail,
                    isError: true
                )
                failed.errorMessage = nil
                failed.isLoading = false
                onSessionChange(failed)
            }
        }
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

        NotificationCenter.default.post(
            name: .addUnderlineNote,
            object: nil,
            userInfo: [
                "noteId": noteEntry.id,
                "pageIndex": session.selection.pageIndex,
                "boundsStr": session.selection.boundsStr,
                "filePath": session.selection.pdfPath
            ]
        )
        return noteEntry.id
    }

    func deleteSavedMessages(in session: ExplanationSession) {
        for noteId in session.savedNoteIdsByMessageId.values {
            try? bridge.deleteNote(id: noteId)
            NotificationCenter.default.post(
                name: .removeUnderlineNote,
                object: nil,
                userInfo: [
                    "noteId": noteId,
                    "pageIndex": session.selection.pageIndex,
                    "filePath": session.selection.pdfPath
                ]
            )
        }
    }

    private static func updatingAssistantMessage(
        in messages: [ExplanationMessage],
        id: UUID,
        content: String,
        isError: Bool = false
    ) -> [ExplanationMessage] {
        messages.map { message in
            guard message.id == id else { return message }
            var updated = message
            updated.content = content
            updated.isError = isError
            return updated
        }
    }

    private static func guideErrorMessage(from error: Error) -> String {
        let detail = TranslationErrorFormatter.userMessage(from: error)
            .replacingOccurrences(of: "翻译失败：", with: "导读调用失败：")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "导读调用失败：请检查 LLM 设置后重试。"
        }
        return detail
    }

    private static func compressedExplanationContext(
        summary: String,
        messages: [ExplanationMessage]
    ) -> String {
        let compactSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let completedMessages = messages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
