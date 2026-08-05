import SwiftUI
import Textual

struct TranslationBubble: View {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    let availableSize: CGSize
    let onSave: (TranslationResult) -> String?
    let onDelete: (String, Bool) -> Void
    let onDismiss: () -> Void

    @StateObject private var audio = AudioService()
    @State private var savedEntryId: String?
    @State private var savedToNote = false

    var body: some View {
        ReadingOverlayWindow(
            anchorRect: request.selectionAnchorRect,
            availableSize: availableSize,
            resetID: AnyHashable(request.id),
            configuration: ReadingOverlayWindowConfiguration(
                width: cardWidth,
                initialContentHeight: request.isSentenceMode ? 160 : 120,
                minimumContentHeight: 80,
                isResizable: true,
                minimumSize: CGSize(width: 340, height: 240),
                maximumSize: CGSize(width: 920, height: CGFloat.greatestFiniteMagnitude),
                dismissesOnBackgroundTap: true,
                showsFooter: showsFooter
            ),
            onDismiss: onDismiss,
            header: { header },
            content: { content },
            footer: { overlayFooter }
        )
        .onAppear(perform: syncSavedState)
        .onChange(of: request.id) { _, _ in syncSavedState() }
    }

    private func syncSavedState() {
        savedEntryId = request.existingEntryId
        savedToNote = false
    }

    private var cardWidth: CGFloat {
        let availableWidth = max(availableSize.width, 420)
        let cap = min(max(340, availableWidth - 96), 760)
        let base: CGFloat = request.isSentenceMode ? 560 : 380
        let text = request.isSentenceMode ? request.word : request.sentence
        return min(max(base, CGFloat(text.count) * 4.2), cap)
    }

    private var showsFooter: Bool {
        guard let result = request.result else { return false }
        return !isLoading && !result.isCompleteFailure && Self.hasAnyContent(result)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(headerTitle)
                    .font(request.isSentenceMode ? .headline : .title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(request.isSentenceMode ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)

                if let phonetic = request.result?.phonetic, !phonetic.isEmpty {
                    Text("[\(phonetic)]")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if request.result?.source == "fallback" {
                    Label("基础翻译", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                ReadingOverlayMoveHandle()

                Button {
                    audio.speak(request.result?.word ?? request.word)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help("朗读")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .padding(14)
    }

    private var headerTitle: String {
        if request.isSentenceMode {
            return ContextSentenceFormatting.displayParagraph(request.word)
        }
        return ContextSentenceFormatting.displayParagraph(request.result?.word ?? request.word)
    }

    @ViewBuilder
    private var content: some View {
        if let result = request.result, Self.hasAnyContent(result) {
            if result.isCompleteFailure {
                completeFailureView(result: result)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading {
                        streamingBanner
                    }
                    resultContent(result: result)
                }
            }
        } else if isLoading {
            loadingView
        } else {
            incompleteView
        }
    }

    private func resultContent(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            contentBody(result: result)
            errorSection(result: result)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var overlayFooter: some View {
        if let result = request.result, showsFooter {
            footer(result: result)
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            SpinnerView()
            Text("翻译中…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var incompleteView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("翻译未完成")
                .font(.headline)
            Text(request.translationError?.isEmpty == false ? request.translationError! : "请检查网络与 LLM 设置后重试。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamingBanner: some View {
        HStack(spacing: 6) {
            SpinnerView()
            Text("正在生成…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
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

    @ViewBuilder
    private func contentBody(result: TranslationResult) -> some View {
        if request.isSentenceMode {
            sentenceContent(result: result)
        } else {
            wordContent(result: result)
        }
    }

    private func sentenceContent(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BubbleSection("原文") {
                Text(ContextSentenceFormatting.displayParagraph(request.word))
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !sentenceTranslation(result).isEmpty {
                BubbleSection("译文") {
                    Text(sentenceTranslation(result))
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !result.contextExplanation.isEmpty {
                BubbleSection("解释") {
                    Text(result.contextExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !result.sentenceBreakdown.isEmpty {
                BubbleSection("拆解") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(result.sentenceBreakdown.enumerated()), id: \.offset) { index, chunk in
                            breakdownChunkView(index: index + 1, chunk: chunk)
                        }
                    }
                }
            }
        }
    }

    private func wordContent(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !result.contextTranslation.isEmpty {
                BubbleSection("语境翻译") {
                    Text(result.contextTranslation)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            if !result.contextExplanation.isEmpty {
                BubbleSection("语境解释") {
                    Text(result.contextExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !result.etymology.isEmpty {
                BubbleSection("词源 / 历史故事") {
                    Text(result.etymology)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !result.generalDefinition.isEmpty {
                BubbleSection("通用释义") {
                    Text(result.generalDefinition)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            BubbleSection("原文语境") {
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func sentenceTranslation(_ result: TranslationResult) -> String {
        if !result.contextSentenceTranslation.isEmpty {
            return result.contextSentenceTranslation
        }
        return result.contextTranslation
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
        }
    }

    private func warningCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func completeFailureView(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("翻译失败", systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("所有翻译途径均失败，请检查网络连接和 LLM 设置。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !result.llmErrorMessage.isEmpty {
                warningCard(title: "LLM 调用失败", text: result.llmErrorMessage)
            }
            if !result.fallbackErrorMessage.isEmpty {
                warningCard(title: "兜底翻译失败", text: result.fallbackErrorMessage)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(result: TranslationResult) -> some View {
        HStack {
            Spacer()
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
                    Label(request.isSentenceMode ? "保存到笔记" : "保存到单词本",
                          systemImage: request.isSentenceMode ? "note.text" : "bookmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Spinner

private struct SpinnerView: View {
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
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

// MARK: - Section label

private struct BubbleSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
