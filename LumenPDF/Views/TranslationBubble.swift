import SwiftUI
import AppKit
import Textual

struct TranslationBubble: View {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    let availableSize: CGSize
    let onSave: (TranslationResult) -> String?
    let onDelete: (String) -> Void
    let onAskExplanation: (String) -> Void
    let onDismiss: () -> Void

    @StateObject private var audio = AudioService()
    @State private var savedEntryId: String?
    /// Tracks whether the saved entry is a note (sentence mode) or vocabulary entry
    @State private var savedToNote: Bool = false

    // Drag offset — updated directly from AppKit mouse events (no SwiftUI gesture layer)
    @State private var offset: CGSize = .zero
    @State private var customCardSize: CGSize?
    @State private var measuredCardSize: CGSize = .zero
    @State private var measuredContentHeight: CGFloat = 0
    @State private var explanationShouldFollowStream = true
    @State private var explanationHasOverflow = false
    @State private var explanationQuestion: String = ""
    @State private var requestAnchorKey: String = ""

    private static let explanationBottomID = "explanation-bottom"

    var body: some View {
        card
            .offset(offset)
            // Suppress all implicit animations on the card during drag
            .animation(nil, value: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
            )
            .onAppear {
                requestAnchorKey = stableRequestAnchorKey
                syncSavedState()
            }
            // The bubble is reused in place when the user selects a different word without first
            // dismissing it. `onAppear` won't fire again, so re-sync on request identity changes —
            // otherwise it would keep showing the previous word's saved/unsaved state.
            .onChange(of: request.id) { _ in
                syncSavedState()
                explanationQuestion = ""
                let newAnchorKey = stableRequestAnchorKey
                if requestAnchorKey != newAnchorKey {
                    customCardSize = nil
                    measuredCardSize = .zero
                    measuredContentHeight = 0
                    explanationShouldFollowStream = true
                    explanationHasOverflow = false
                    offset = .zero
                    requestAnchorKey = newAnchorKey
                }
            }
    }

    /// Seed the local saved state from the request. `existingEntryId` is only ever a vocabulary
    /// entry (resolved by word + context before the bubble is shown), so it is never a note.
    private func syncSavedState() {
        savedEntryId = request.existingEntryId
        savedToNote = false
    }

    // MARK: - Card

    private var card: some View {
        return VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(resizeHotZones)
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .frame(width: cardWidth, height: customCardSize?.height)
        .frame(maxHeight: customCardSize == nil ? maximumAutomaticCardHeight : nil)
        .onSizeChange { measuredCardSize = $0 }
    }

    private var effectiveAvailableSize: CGSize {
        CGSize(width: max(availableSize.width, 900), height: max(availableSize.height, 600))
    }

    private var stableRequestAnchorKey: String {
        "\(request.isExplanationMode)-\(request.page)-\(request.boundsStr)-\(request.word)"
    }

    private var cardWidth: CGFloat {
        if let customCardSize {
            return customCardSize.width
        }

        if request.isExplanationMode {
            return min(max(effectiveAvailableSize.width * 0.48, 520), min(920, effectiveAvailableSize.width * 0.78))
        }

        let baseWidth: CGFloat = request.isSentenceMode ? 560 : 380
        let text = request.isSentenceMode ? request.word : request.sentence
        return min(max(baseWidth, CGFloat(text.count) * 4.2), 760)
    }

    private var shouldScrollContent: Bool {
        customCardSize != nil || measuredContentHeight > maximumAutomaticContentHeight
    }

    private var maximumAutomaticCardHeight: CGFloat? {
        guard request.isExplanationMode else { return nil }
        return min(max(effectiveAvailableSize.height * 0.72, 420), effectiveAvailableSize.height * 0.82)
    }

    private var maximumAutomaticContentHeight: CGFloat {
        if request.isExplanationMode {
            let cardLimit = maximumAutomaticCardHeight ?? (effectiveAvailableSize.height * 0.72)
            // Keep the whole explanation window within a proportional height of the
            // reader window. The header/divider and outer padding need reserved space,
            // so the scrollable body is slightly smaller than the card cap.
            return max(240, cardLimit - 86)
        }
        return request.isSentenceMode ? 560 : 520
    }

    private enum ResizeEdge {
        case trailing
        case bottom
        case corner

        var cursor: NSCursor {
            switch self {
            case .trailing:
                return .resizeLeftRight
            case .bottom:
                return .resizeUpDown
            case .corner:
                return .resizeDiagonal
            }
        }
    }

    private var resizeHotZones: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                Spacer()
                resizeZone(.trailing)
                    .frame(width: 8)
            }

            VStack(spacing: 0) {
                Spacer()
                resizeZone(.bottom)
                    .frame(height: 8)
            }

            resizeZone(.corner)
                .frame(width: 24, height: 24)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(5)
                }
        }
        .allowsHitTesting(true)
    }

    private func resizeZone(_ edge: ResizeEdge) -> some View {
        AppKitResizeCapture(cursor: edge.cursor) { delta in
            resizeCard(by: delta, edge: edge)
        }
    }

    private var minimumCardSize: CGSize {
        request.isExplanationMode
            ? CGSize(width: 500, height: 320)
            : CGSize(width: 340, height: 240)
    }

    private var maximumCardSize: CGSize {
        CGSize(
            width: max(minimumCardSize.width, effectiveAvailableSize.width * 0.90),
            height: max(minimumCardSize.height, effectiveAvailableSize.height * 0.90)
        )
    }

    private func resizeCard(by delta: CGSize, edge: ResizeEdge) {
        let current = customCardSize ?? CGSize(
            width: cardWidth,
            height: min(max(measuredCardSize.height, minimumCardSize.height), maximumCardSize.height)
        )

        var next = current
        if edge == .trailing || edge == .corner {
            next.width += delta.width
        }
        if edge == .bottom || edge == .corner {
            next.height += delta.height
        }

        customCardSize = CGSize(
            width: min(max(next.width, minimumCardSize.width), maximumCardSize.width),
            height: min(max(next.height, minimumCardSize.height), maximumCardSize.height)
        )
    }

    // MARK: - Header (AppKit drag handle)

    private var header: some View {
        HStack(alignment: .top) {
            Group {
                if request.isExplanationMode {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("AI 导读", systemImage: "sparkles")
                            .font(.headline)
                        Text("围绕当前选区连续追问")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        // 纵向排列：单词独占一行按词换行，避免与音标挤在同一行导致「拦腰断词」
                        Text(ContextSentenceFormatting.displayParagraph(request.result?.word ?? request.word))
                            .font(.title2.bold())
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        if let phonetic = request.result?.phonetic, !phonetic.isEmpty {
                            Text("[\(phonetic)]")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let src = request.result?.source, src == "fallback" {
                            Label(
                                (request.result?.llmErrorMessage.isEmpty == false)
                                    ? "基础翻译（LLM 未成功，见下方说明）"
                                    : "基础翻译",
                                systemImage: "info.circle"
                            )
                            .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption2).foregroundStyle(.tertiary)

                Button { audio.speak(request.result?.word ?? request.word) } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.plain).disabled(isLoading)

                Button { onDismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, request.isExplanationMode ? 10 : 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        // AppKit-level drag capture sits behind the content; buttons on top still fire normally
        .background(
            AppKitDragCapture { delta in
                offset.width  += delta.width
                offset.height += delta.height
            }
        )
        .cursor(.openHand)
    }

    // MARK: - Content body

    @ViewBuilder
    private var content: some View {
        // While streaming, show the partial result as soon as ANY field is
        // populated. Falling back to the full spinner only when we have
        // nothing to display avoids the awkward "blank → 5 s → everything"
        // transition the non-streaming version produced.
        if request.isExplanationMode && request.result == nil && !isLoading {
            explanationPromptContent
        } else if request.isExplanationMode && isLoading && !request.explanationMessages.isEmpty {
            explanationChatScrollContent
        } else if let result = request.result, Self.hasAnyContent(result) {
            if result.isCompleteFailure {
                completeFailureView(result: result)
            } else {
                if isLoading && !request.isExplanationMode {
                    streamingBanner
                }
                adaptiveContent(result: result)

                errorSection(result: result)

                if !isLoading {
                    Divider()
                    footer(result: result)
                }
            }
        } else if isLoading {
            HStack(spacing: 8) {
                SpinnerView()
                Text("翻译中…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("翻译未完成")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                Spacer(minLength: 24)
                Divider()
                Group {
                    if let detail = request.translationError, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("请检查网络与 LLM 设置后重试。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        }
    }

    @ViewBuilder
    private func adaptiveContent(result: TranslationResult) -> some View {
        if request.isExplanationMode {
            explanationChatScrollContent
        } else if shouldScrollContent {
            ScrollView {
                contentBody(result: result)
                    .onHeightChange { measuredContentHeight = $0 }
            }
            .frame(maxWidth: .infinity)
            .frame(height: customCardSize == nil ? maximumAutomaticContentHeight : nil)
            .frame(maxHeight: customCardSize == nil ? nil : .infinity)
        } else {
            contentBody(result: result)
                .onHeightChange { measuredContentHeight = $0 }
        }
    }

    // MARK: - Streaming banner

    /// Slim header rendered above the content while the LLM is still
    /// streaming. Lets the user see early fields while keeping a clear
    /// "still loading" affordance.
    private var streamingBanner: some View {
        HStack(spacing: 6) {
            SpinnerView()
            Text("正在生成…").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    /// Returns true if the result has at least one user-visible field filled
    /// in (anything other than `word` alone, since `word` defaults to the
    /// selection text and is always present).
    private static func hasAnyContent(_ r: TranslationResult) -> Bool {
        !r.phonetic.isEmpty
            || !r.partOfSpeech.isEmpty
            || !r.contextTranslation.isEmpty
            || !r.contextExplanation.isEmpty
            || !r.generalDefinition.isEmpty
            || !r.contextSentenceTranslation.isEmpty
            || !r.sentenceBreakdown.isEmpty
            || r.isCompleteFailure
    }

    // MARK: - Complete failure view

    @ViewBuilder
    private func completeFailureView(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("翻译失败")
                .font(.headline)
                .foregroundStyle(.red)

            Text("所有翻译途径均失败，请检查网络连接和 LLM 设置")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            // LLM error
            if !result.llmErrorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("LLM 调用失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(result.llmErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // Fallback error
            if !result.fallbackErrorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("兜底翻译失败", systemImage: "xmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Text(result.fallbackErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
    }

    // MARK: - Error section

    @ViewBuilder
    private func errorSection(result: TranslationResult) -> some View {
        // LLM error (shown even when fallback succeeded)
        if !result.llmErrorMessage.isEmpty || !result.fallbackErrorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !result.llmErrorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LLM 调用未成功", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(result.llmErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                if !result.fallbackErrorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("兜底翻译部分失败", systemImage: "info.circle")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(result.fallbackErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - Content body helper

    @ViewBuilder
    private func contentBody(result: TranslationResult) -> some View {
        if request.isExplanationMode {
            explanationChatContent()
                .padding(14)
        } else if request.isSentenceMode
            && result.contextTranslation.isEmpty
            && result.generalDefinition.isEmpty
            && result.phonetic.isEmpty
        {
            // Sentence translation mode: show original, translation, and (for
            // long / complex sentences) the per-fragment breakdown.
            VStack(alignment: .leading, spacing: 12) {
                BubbleSection("原文") {
                    Text(ContextSentenceFormatting.displayParagraph(request.word))
                        .font(.body)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.contextSentenceTranslation.isEmpty {
                    BubbleSection("译文") {
                        Text(result.contextSentenceTranslation)
                            .font(.body)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !result.sentenceBreakdown.isEmpty {
                    BubbleSection("拆解分析") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(result.sentenceBreakdown.enumerated()), id: \.offset) { idx, chunk in
                                breakdownChunkView(index: idx + 1, chunk: chunk)
                            }
                        }
                    }
                }
            }
            .padding(14)
        } else {
            // Word translation mode: show all fields.
            VStack(alignment: .leading, spacing: 12) {
                if !result.contextTranslation.isEmpty {
                    BubbleSection("语境翻译") {
                        Text(result.contextTranslation).font(.body)
                    }
                }
                if !result.contextExplanation.isEmpty {
                    BubbleSection("语境解释") {
                        Text(result.contextExplanation)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !result.generalDefinition.isEmpty {
                    BubbleSection("通用释义") {
                        Text(result.generalDefinition)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                BubbleSection("原文语境") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ContextSentenceFormatting.displayParagraph(request.sentence))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !result.contextSentenceTranslation.isEmpty {
                            Text(result.contextSentenceTranslation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
        }
    }

    // MARK: - Breakdown chunk (sentence mode)

    @ViewBuilder
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
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !chunk.translation.isEmpty {
                        Text(chunk.translation)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !chunk.explanation.isEmpty {
                Text(chunk.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }
            if !chunk.grammar.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("语法")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                    Text(chunk.grammar)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 18)
            }
        }
    }


    private var explanationChatScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                explanationScrollObserver
                    .frame(width: 0, height: 0)
                explanationChatContent()
                    .padding(14)
                    .onHeightChange { measuredContentHeight = $0 }
                Color.clear
                    .frame(height: 1)
                    .id(Self.explanationBottomID)
            }
            .scrollIndicators(.visible)
            .onChange(of: request.explanationMessages.count) { _, count in
                guard count > 2 else { return }
                scrollExplanationIfFollowing(proxy, animated: true)
            }
            .onChange(of: request.explanationMessages.last?.content ?? "") { _, _ in
                scrollExplanationIfFollowing(proxy, animated: false)
            }
            .onChange(of: measuredContentHeight) { _, _ in
                scrollExplanationIfFollowing(proxy, animated: false)
            }
            .onChange(of: isLoading) { _, _ in
                scrollExplanationIfFollowing(proxy, animated: true)
            }
            .onChange(of: explanationHasOverflow) { _, hasOverflow in
                if hasOverflow {
                    scrollExplanationIfFollowing(proxy, animated: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: customCardSize == nil ? maximumAutomaticContentHeight : nil)
        .frame(maxHeight: customCardSize == nil ? nil : .infinity)
    }

    private var explanationScrollObserver: some View {
        ExplanationScrollObserver { state, userScrolled in
            explanationHasOverflow = state.hasOverflow
            guard userScrolled else { return }
            explanationShouldFollowStream = state.isNearBottom || !state.hasOverflow
        }
    }

    private func scrollExplanationIfFollowing(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard explanationShouldFollowStream,
              explanationHasOverflow,
              currentAssistantHasStarted
        else { return }
        scrollExplanationToBottom(proxy, animated: animated)
    }

    private var currentAssistantHasStarted: Bool {
        guard request.explanationMessages.last?.role == .assistant else { return false }
        return request.explanationMessages.last?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    private func scrollExplanationToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        func perform(animated: Bool) {
            if animated {
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(Self.explanationBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.explanationBottomID, anchor: .bottom)
            }
        }

        DispatchQueue.main.async {
            perform(animated: animated)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            perform(animated: false)
        }
    }

    private func explanationChatContent() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            originalSelectionCard

            VStack(alignment: .leading, spacing: 12) {
                ForEach(request.explanationMessages) { message in
                    explanationMessageBubble(message)
                }
            }

            if !isLoading {
                explanationQuestionBar(defaultSubmitOnReturn: false, isFollowUp: true)
            }
        }
    }

    private var originalSelectionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("选中文本", systemImage: "text.viewfinder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ContextSentenceFormatting.displayParagraph(request.word))
                .font(.callout)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func explanationMessageBubble(_ message: ExplanationMessage) -> some View {
        switch message.role {
        case .user:
            userMessageBubble(message.content)
                .id(message.id)
        case .assistant:
            if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                assistantThinkingBubble
                    .id(message.id)
            } else {
                assistantMessageBubble(message.content, isStreaming: isLoading && request.explanationMessages.last?.id == message.id)
                    .id(message.id)
            }
        }
    }

    private func userMessageBubble(_ text: String) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 32)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(.primary)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                )
        }
    }

    private func assistantMessageBubble(_ markdown: String, isStreaming: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor.opacity(isStreaming ? 0.7 : 0.48))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                if isStreaming {
                    Label("正在生成", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MarkdownText(markdown: markdown)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7)
        )
    }

    private var assistantThinkingBubble: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor.opacity(0.48))
                .frame(width: 3, height: 30)
            HStack(spacing: 8) {
                SpinnerView()
                Text("正在思考…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7)
            )
        }
    }

    private var trimmedExplanationQuestion: String {
        explanationQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitExplanationQuestion() {
        guard !isLoading else { return }
        let question = trimmedExplanationQuestion
        explanationQuestion = ""
        onAskExplanation(question)
    }

    private func explanationQuestionBar(defaultSubmitOnReturn: Bool, isFollowUp: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isFollowUp ? "bubble.left.and.text.bubble.right" : "questionmark.bubble")
                .font(.callout)
                .foregroundStyle(Color.primary.opacity(0.68))
                .frame(width: 20)

            TextField(
                text: $explanationQuestion,
                prompt: Text(isFollowUp ? "继续追问…" : "想先问什么？留空则直接解释")
                    .foregroundStyle(.secondary)
            ) {
                EmptyView()
            }
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.primary)
                .submitLabel(.send)
                .onSubmit { submitExplanationQuestion() }
                .disabled(isLoading)

            explanationSubmitButton(defaultSubmitOnReturn: defaultSubmitOnReturn)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func explanationSubmitButton(defaultSubmitOnReturn: Bool) -> some View {
        let accessibilityTitle = trimmedExplanationQuestion.isEmpty
            ? (defaultSubmitOnReturn ? "直接解释" : "继续解释")
            : (defaultSubmitOnReturn ? "解释" : "继续追问")
        let button = Button {
            submitExplanationQuestion()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .help(accessibilityTitle)
        .accessibilityLabel(accessibilityTitle)
        .disabled(isLoading)

        if defaultSubmitOnReturn {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }


    private var explanationPromptContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                originalSelectionCard
                explanationQuestionBar(defaultSubmitOnReturn: true)
            }
            .padding(14)
            .onHeightChange { measuredContentHeight = $0 }
        }
        .frame(maxWidth: .infinity)
        .frame(height: customCardSize == nil ? maximumAutomaticContentHeight : nil)
        .frame(maxHeight: customCardSize == nil ? nil : .infinity)
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(result: TranslationResult) -> some View {
        HStack {
            Spacer()
            if let entryId = savedEntryId {
                HStack(spacing: 12) {
                    Label(savedToNote ? "已保存到笔记" : "已保存", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                    Button(role: .destructive) {
                        if savedToNote {
                            try? BridgeService.shared.deleteNote(id: entryId)
                        } else {
                            try? BridgeService.shared.deleteVocabulary(id: entryId)
                        }
                        savedEntryId = nil
                        onDelete(entryId)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    savedEntryId = onSave(result)
                    savedToNote = request.isSentenceMode || request.isExplanationMode
                } label: {
                    if request.isSentenceMode || request.isExplanationMode {
                        Label("保存到笔记", systemImage: "note.text")
                    } else {
                        Label("保存到单词本", systemImage: "bookmark")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - AppKit drag capture (bypasses SwiftUI gesture pipeline for frame-perfect drag)

/// Transparent NSView that processes mouseDown/mouseDragged at AppKit level.
/// Placed as .background() so SwiftUI buttons layered on top still receive clicks normally.
private struct AppKitDragCapture: NSViewRepresentable {
    /// Called on the main thread with each incremental drag delta (SwiftUI coordinate space).
    let onDelta: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDelta) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelta = onDelta
    }

    final class Coordinator: NSObject {
        var onDelta: (CGSize) -> Void
        lazy var view: CaptureView = CaptureView(coordinator: self)
        init(_ cb: @escaping (CGSize) -> Void) { onDelta = cb }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        /// Last mouse position in window coordinates.
        private var lastLoc: CGPoint?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {
            lastLoc = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let last = lastLoc else { return }
            let cur = event.locationInWindow
            // Window coords: Y increases upward; SwiftUI: Y increases downward → negate dy
            let delta = CGSize(width: cur.x - last.x, height: -(cur.y - last.y))
            lastLoc = cur
            coordinator?.onDelta(delta)
        }

        override func mouseUp(with event: NSEvent) {
            lastLoc = nil
        }

        // Accept the first mouse-down even when the window is not key
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - AppKit resize capture

private struct AppKitResizeCapture: NSViewRepresentable {
    let cursor: NSCursor
    let onDelta: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(cursor: cursor, onDelta: onDelta) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.cursor = cursor
        context.coordinator.onDelta = onDelta
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class Coordinator: NSObject {
        var cursor: NSCursor
        var onDelta: (CGSize) -> Void
        lazy var view: CaptureView = CaptureView(coordinator: self)
        init(cursor: NSCursor, onDelta: @escaping (CGSize) -> Void) {
            self.cursor = cursor
            self.onDelta = onDelta
        }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        private var lastLoc: CGPoint?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: coordinator?.cursor ?? .arrow)
        }

        override func mouseDown(with event: NSEvent) {
            lastLoc = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let last = lastLoc else { return }
            let cur = event.locationInWindow
            let delta = CGSize(width: cur.x - last.x, height: -(cur.y - last.y))
            lastLoc = cur
            coordinator?.onDelta(delta)
        }

        override func mouseUp(with event: NSEvent) {
            lastLoc = nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - AppKit scroll observer

private struct ExplanationScrollState: Equatable {
    let isNearBottom: Bool
    let hasOverflow: Bool
}

private struct ExplanationScrollObserver: NSViewRepresentable {
    let onChange: (ExplanationScrollState, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attachIfNeeded()
        context.coordinator.report(userScrolled: false)
    }

    final class Coordinator: NSObject {
        var onChange: (ExplanationScrollState, Bool) -> Void
        lazy var view: ProbeView = ProbeView(coordinator: self)
        private weak var scrollView: NSScrollView?
        private var observedClipView: NSClipView?
        private var lastState: ExplanationScrollState?

        init(onChange: @escaping (ExplanationScrollState, Bool) -> Void) {
            self.onChange = onChange
        }

        deinit {
            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }
        }

        func attachIfNeeded() {
            guard let found = view.enclosingScrollView else { return }
            guard found !== scrollView else { return }

            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }

            scrollView = found
            observedClipView = found.contentView
            found.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: found.contentView
            )
        }

        func report(userScrolled: Bool) {
            attachIfNeeded()
            guard let scrollView, let documentView = scrollView.documentView else { return }

            let visible = scrollView.contentView.bounds
            let documentBounds = documentView.bounds
            let threshold: CGFloat = 28
            let visibleHeight = visible.height
            let documentHeight = documentBounds.height
            let hasOverflow = documentHeight > visibleHeight + threshold

            let isNearBottom: Bool
            if !hasOverflow {
                isNearBottom = true
            } else if documentView.isFlipped {
                isNearBottom = visible.maxY >= documentBounds.maxY - threshold
            } else {
                isNearBottom = visible.minY <= documentBounds.minY + threshold
            }

            let state = ExplanationScrollState(isNearBottom: isNearBottom, hasOverflow: hasOverflow)
            if state != lastState || userScrolled {
                lastState = state
                DispatchQueue.main.async {
                    self.onChange(state, userScrolled)
                }
            }
        }

        @objc private func boundsDidChange() {
            report(userScrolled: true)
        }
    }

    final class ProbeView: NSView {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak coordinator] in
                coordinator?.attachIfNeeded()
                coordinator?.report(userScrolled: false)
            }
        }
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
        }
    }
}

// MARK: - Cursor modifier (macOS)

private extension View {
    func onSizeChange(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ViewSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ViewSizePreferenceKey.self, perform: onChange)
    }

    func onHeightChange(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ViewHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ViewHeightPreferenceKey.self, perform: onChange)
    }

    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct ViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension NSCursor {
    static var resizeDiagonal: NSCursor {
        if #available(macOS 11.0, *) {
            return NSCursor(image: NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil) ?? NSImage(), hotSpot: NSPoint(x: 6, y: 6))
        }
        return .crosshair
    }
}
