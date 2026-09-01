import AppKit
import SwiftUI
import Textual

struct TranslationBubble: View {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    let availableSize: CGSize
    let onSave: (TranslationResult) -> String?
    let onDelete: (String, Bool) -> Void
    let onExplain: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @AppStorage("target_language") private var targetLanguage = "简体中文"
    @StateObject private var audio = AudioService()
    @State private var savedEntryId: String?
    @State private var savedToNote = false
    @State private var copyConfirmation: String?
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ReadingOverlayWindow(
            anchorRect: request.selectionAnchorRect,
            availableSize: availableSize,
            resetID: AnyHashable(request.id),
            configuration: ReadingOverlayWindowConfiguration(
                width: cardWidth,
                initialContentHeight: initialContentHeight,
                minimumContentHeight: 80,
                isResizable: true,
                minimumSize: CGSize(width: 280, height: 180),
                maximumSize: CGSize(width: 920, height: CGFloat.greatestFiniteMagnitude),
                dismissesOnBackgroundTap: true,
                showsFooter: showsFooter,
                showsAnchorPointer: true,
                placementOrder: ReadingOverlayPlacement.lookUpOrder,
                preferredGap: 2,
                compactVerticalInset: true,
                opaqueChrome: true
            ),
            onDismiss: onDismiss,
            header: { header },
            content: { content },
            footer: { overlayFooter }
        )
        .onAppear(perform: syncSavedState)
        .onChange(of: request.id) { _, _ in syncSavedState() }
        .onDisappear { copyResetTask?.cancel() }
    }

    private func syncSavedState() {
        savedEntryId = request.existingEntryId
        savedToNote = false
        copyConfirmation = nil
        copyResetTask?.cancel()
    }

    private var languageStyle: TranslationPopoverPresentation.LanguageStyle {
        TranslationPopoverPresentation.languageStyle(targetLanguage: targetLanguage)
    }

    private var sourceText: String {
        TranslationPopoverPresentation.sourceText(
            isSentenceMode: request.isSentenceMode,
            selectedText: request.word,
            resultWord: request.result?.word
        )
    }

    private func primaryTranslation(from result: TranslationResult?) -> String {
        TranslationPopoverPresentation.primaryTranslation(
            isSentenceMode: request.isSentenceMode,
            contextTranslation: result?.contextTranslation ?? "",
            contextSentenceTranslation: result?.contextSentenceTranslation ?? ""
        )
    }

    private var cardWidth: CGFloat {
        let text = request.isSentenceMode ? request.word : request.sentence
        return TranslationPopoverGeometry.contentWidth(
            isSentenceMode: request.isSentenceMode,
            textCount: text.count,
            availableWidth: availableSize.width
        )
    }

    private var initialContentHeight: CGFloat {
        if request.translationError != nil || request.result?.isCompleteFailure == true {
            return 248
        }
        return request.isSentenceMode ? 200 : 168
    }

    private var showsFooter: Bool {
        guard let result = request.result else { return false }
        return !isLoading && !result.isCompleteFailure && Self.hasAnyContent(result)
    }

    private var showsRefreshButton: Bool {
        !isLoading && (request.result != nil || request.translationError != nil)
    }

    private var refreshHelp: String {
        if request.result?.isCompleteFailure == true || request.translationError != nil {
            return "重试"
        }
        return "重新生成"
    }

    private var header: some View {
        HStack(spacing: 8) {
            ReadingOverlayMoveHandle()
            Spacer(minLength: 8)
            if showsRefreshButton {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("translation.retry")
                .help(refreshHelp)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        if let result = request.result, Self.hasAnyContent(result) {
            if result.isCompleteFailure {
                VStack(alignment: .leading, spacing: 0) {
                    sourcePair(phonetic: result.phonetic)
                    Divider()
                    completeFailureView(result: result)
                }
            } else {
                resultContent(result: result)
            }
        } else if isLoading {
            VStack(alignment: .leading, spacing: 0) {
                sourcePair(phonetic: "")
                Divider()
                targetPair(text: "", isLoading: true, isFallback: false)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                sourcePair(phonetic: "")
                Divider()
                incompleteView
            }
        }
    }

    private func resultContent(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sourcePair(phonetic: result.phonetic)
            Divider()
            targetPair(
                text: primaryTranslation(from: result),
                isLoading: TranslationPopoverPresentation.showsStreamingProgress(
                    isLoading: isLoading,
                    primaryTranslation: primaryTranslation(from: result)
                ),
                isFallback: result.source == "fallback"
            )
            extraSections(result: result)
            errorSection(result: result)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var overlayFooter: some View {
        if let result = request.result, showsFooter {
            footer(result: result)
        }
    }

    private var incompleteView: some View {
        TranslationFailureCard(
            message: request.translationError?.isEmpty == false
                ? request.translationError!
                : "请检查网络与 LLM 设置后重试。",
            fallbackHeadline: "翻译未完成",
            style: .page,
            onRetry: onRetry
        )
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func hasAnyContent(_ result: TranslationResult) -> Bool {
        !result.phonetic.isEmpty
            || !result.partOfSpeech.isEmpty
            || !result.contextTranslation.isEmpty
            || !result.contextExplanation.isEmpty
            || !result.etymology.isEmpty
            || !result.generalDefinition.isEmpty
            || !result.contextSentenceTranslation.isEmpty
            || !result.sentenceBreakdown.isEmpty
            || result.isCompleteFailure
    }

    private func sourcePair(phonetic: String) -> some View {
        TranslationPopoverLanguagePair(
            languageLabel: languageStyle.sourceLabel,
            text: sourceText,
            phonetic: phonetic,
            isResult: false,
            isLoading: false,
            speakEnabled: !sourceText.isEmpty && !isLoading,
            onSpeak: {
                audio.speak(sourceText, languageCode: languageStyle.sourceSpeechCode)
            }
        )
        .accessibilityIdentifier("translation.source")
    }

    private func targetPair(text: String, isLoading: Bool, isFallback: Bool) -> some View {
        TranslationPopoverLanguagePair(
            languageLabel: languageStyle.targetLabel,
            text: text,
            phonetic: "",
            isResult: true,
            isLoading: isLoading,
            isFallback: isFallback,
            speakEnabled: !text.isEmpty,
            onSpeak: {
                audio.speak(text, languageCode: languageStyle.targetSpeechCode)
            }
        )
        .accessibilityIdentifier("translation.target")
    }

    @ViewBuilder
    private func extraSections(result: TranslationResult) -> some View {
        if request.isSentenceMode {
            sentenceExtras(result: result)
        } else {
            wordExtras(result: result)
        }
    }

    @ViewBuilder
    private func sentenceExtras(result: TranslationResult) -> some View {
        if !result.contextExplanation.isEmpty {
            Divider()
            TranslationPopoverDetailSection("解释") {
                Text(result.contextExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !result.sentenceBreakdown.isEmpty {
            Divider()
            TranslationPopoverDetailSection("拆解") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(result.sentenceBreakdown.enumerated()), id: \.offset) { index, chunk in
                        breakdownChunkView(index: index + 1, chunk: chunk)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordExtras(result: TranslationResult) -> some View {
        if !result.contextExplanation.isEmpty {
            Divider()
            TranslationPopoverDetailSection("语境解释") {
                Text(result.contextExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        if !result.etymology.isEmpty {
            Divider()
            TranslationPopoverDetailSection("词源 / 历史故事") {
                Text(result.etymology)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !result.generalDefinition.isEmpty {
            Divider()
            TranslationPopoverDetailSection("通用释义") {
                Text(result.generalDefinition)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        Divider()
        TranslationPopoverDetailSection("原文语境") {
            VStack(alignment: .leading, spacing: 8) {
                Text(ContextSentenceFormatting.displayParagraph(request.sentence))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !result.contextSentenceTranslation.isEmpty {
                    Text(result.contextSentenceTranslation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func breakdownChunkView(index: Int, chunk: SentenceChunk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index).")
                    .font(.callout.bold())
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 4) {
                    if !chunk.original.isEmpty {
                        Text(chunk.original)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !chunk.translation.isEmpty {
                        Text(chunk.translation)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !chunk.explanation.isEmpty {
                Text(chunk.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }

            if !chunk.grammar.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("语法")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.14), in: Capsule())
                        .foregroundStyle(.blue)
                    Text(chunk.grammar)
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder
    private func errorSection(result: TranslationResult) -> some View {
        if !result.llmErrorMessage.isEmpty || !result.fallbackErrorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !result.llmErrorMessage.isEmpty {
                    warningCard(title: "LLM 调用未成功", text: result.llmErrorMessage)
                }
                if !result.fallbackErrorMessage.isEmpty {
                    warningCard(title: "兜底翻译部分失败", text: result.fallbackErrorMessage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func warningCard(title: String, text: String) -> some View {
        TranslationFailureCard(
            message: text,
            fallbackHeadline: title,
            style: .nested,
            tintOverride: .orange
        )
    }

    private func completeFailureView(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if result.llmErrorMessage.isEmpty && result.fallbackErrorMessage.isEmpty {
                TranslationFailureCard(
                    message: "所有翻译途径均失败，请检查网络连接和 LLM 设置。",
                    fallbackHeadline: "翻译失败",
                    style: .page,
                    onRetry: onRetry
                )
            } else {
                if !result.llmErrorMessage.isEmpty {
                    TranslationFailureCard(
                        message: result.llmErrorMessage,
                        fallbackHeadline: "LLM 调用失败",
                        style: .nested
                    )
                }
                if !result.fallbackErrorMessage.isEmpty {
                    TranslationFailureCard(
                        message: result.fallbackErrorMessage,
                        fallbackHeadline: "兜底翻译失败",
                        style: .nested
                    )
                }
                Button(action: onRetry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("translation.failure.retry")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(result: TranslationResult) -> some View {
        HStack(spacing: 8) {
            Button(copyConfirmation ?? "拷贝译文") {
                copyPrimaryTranslation(from: result)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(primaryTranslation(from: result).isEmpty)
            .accessibilityIdentifier("translation.copy")

            Spacer()

            Button(action: onExplain) {
                Label("AI 解释", systemImage: "text.bubble")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("translation.explain")

            if let entryId = savedEntryId {
                HStack(spacing: 10) {
                    Label(savedToNote ? "已保存到笔记" : "已保存", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        onDelete(entryId, savedToNote)
                        savedEntryId = nil
                        savedToNote = false
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
            } else {
                Button {
                    savedEntryId = onSave(result)
                    savedToNote = request.isSentenceMode
                } label: {
                    Label(
                        request.isSentenceMode ? "保存到笔记" : "保存到单词本",
                        systemImage: request.isSentenceMode ? "note.text" : "bookmark"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func copyPrimaryTranslation(from result: TranslationResult) {
        let text = primaryTranslation(from: result)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyConfirmation = "已拷贝"
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            copyConfirmation = nil
        }
    }
}

// MARK: - Markdown text

struct MarkdownText: View {
    let markdown: String

    private var normalizedMarkdown: String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        StructuredText(markdown: normalizedMarkdown)
            .textual.textSelection(.enabled)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
