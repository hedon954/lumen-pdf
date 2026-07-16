import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReadingGuidePanel: View {
    @ObservedObject var model: ReadingInspectorModel
    @EnvironmentObject private var appState: AppState

    @State private var question = ""
    @State private var shouldFollowStream = true
    @State private var hasOverflow = false
    @State private var contentHeight: CGFloat = 0
    @State private var isImageImporterPresented = false
    @State private var attachedImageURLs: [URL] = []
    @FocusState private var isQuestionFocused: Bool

    private static let bottomID = "reading-guide-bottom"

    var body: some View {
        VStack(spacing: 0) {
            if let session = model.guideSession {
                guideContent(session)
            } else {
                ReadingInspectorEmptyState(
                    systemImage: "sparkles",
                    title: "选择文本开始 AI 解读",
                    message: "在 PDF 中划选文本后点击「解释」"
                )
            }
        }
        .onChange(of: model.guideSession?.id) { _, _ in
            question = ""
            shouldFollowStream = true
            focusQuestion()
        }
        .onChange(of: model.guideSession?.isLoading ?? false) { _, loading in
            if !loading {
                focusQuestion()
            }
        }
    }

    private func guideContent(_ session: ExplanationSession) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    GuideScrollObserver { state, userScrolled in
                        hasOverflow = state.hasOverflow
                        guard userScrolled else { return }
                        shouldFollowStream = state.isNearBottom || !state.hasOverflow
                    }
                    .frame(width: 0, height: 0)

                    VStack(alignment: .leading, spacing: 12) {
                        selectionCard(session.selection)

                        if session.messages.isEmpty {
                            Text("输入一个问题，或留空直接解释当前选区。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(session.messages) { message in
                                messageView(message, isStreaming: session.isLoading && session.messages.last?.id == message.id)
                                    .id(message.id)
                            }
                        }

                        if let error = session.errorMessage, !error.isEmpty {
                            assistantFailureMessage(error)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                    }
                    .padding(12)
                    .onHeightChange { contentHeight = $0 }
                }
                .onAppear {
                    scrollIfNeeded(proxy, animated: false)
                    focusQuestion()
                }
                .onChange(of: session.messages.count) { _, _ in
                    shouldFollowStream = true
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: session.messages.last?.content ?? "") { _, _ in
                    scrollIfNeeded(proxy, animated: false)
                }
                .onChange(of: contentHeight) { _, _ in
                    scrollIfNeeded(proxy, animated: false)
                }
                .onChange(of: session.isLoading) { _, _ in
                    scrollIfNeeded(proxy, animated: true)
                }
            }

            Divider()
            footer(session)
        }
    }

    private func selectionCard(_ selection: PDFSelectionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("选中文本", systemImage: "text.viewfinder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("P\(selection.pageIndex + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(ContextSentenceFormatting.displayParagraph(selection.selectedText))
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func messageView(_ message: ExplanationMessage, isStreaming: Bool) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 24)
                Text(message.content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(.primary)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 0.5)
                    }
            }
        case .assistant:
            if message.isError {
                assistantFailureMessage(message.content)
            } else if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isStreaming {
                assistantThinking
            } else if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyView()
            } else {
                assistantMessage(message, isStreaming: isStreaming)
            }
        }
    }

    private func assistantMessage(_ message: ExplanationMessage, isStreaming: Bool) -> some View {
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
                MarkdownText(markdown: message.content)
                if !isStreaming {
                    HStack {
                        Spacer()
                        if model.guideSession?.savedNoteIdsByMessageId[message.id] != nil {
                            Label("已保存", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                if model.saveAssistantMessage(message) != nil {
                                    appState.refreshNotes()
                                    appState.showToast("AI 回复已保存到笔记")
                                } else {
                                    appState.showToast("保存笔记失败")
                                }
                            } label: {
                                Label("保存", systemImage: "note.text")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var assistantThinking: some View {
        HStack(spacing: 8) {
            InspectorSpinner()
            Text("正在思考...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private func assistantFailureMessage(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.red.opacity(0.55))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 7) {
                Label("AI 调用失败", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.red.opacity(0.16), lineWidth: 0.5)
        }
    }

    private func footer(_ session: ExplanationSession) -> some View {
        VStack(spacing: 8) {
            questionBar(isLoading: session.isLoading)
            HStack {
                Spacer()
                if session.hasSavedMessages {
                    Label("已保存到笔记", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        model.deleteSavedAssistantMessages()
                        appState.refreshNotes()
                        appState.showToast("已删除保存的 AI 回复")
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("删除本次已保存的 AI 回复")
                } else {
                    Button {
                        let saved = model.saveAllAssistantMessages()
                        appState.refreshNotes()
                        appState.showToast(saved.isEmpty ? "暂无可保存的 AI 回复" : "AI 回复已保存到笔记")
                    } label: {
                        Label("保存全部", systemImage: "note.text")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.completedAssistantMessages.isEmpty)
                }
            }
        }
        .padding(12)
    }

    private func questionBar(isLoading: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .padding(.bottom, 5)

                    ZStack(alignment: .topLeading) {
                        if question.isEmpty {
                            Text("继续追问，留空则直接解释")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $question)
                            .font(.callout)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: questionEditorHeight, maxHeight: questionEditorHeight)
                            .focused($isQuestionFocused)
                            .disabled(isLoading)
                    }

                    Button {
                        isImageImporterPresented = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .help("附加图片（当前会随问题记录图片文件名）")

                    Button {
                        submitQuestion()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .keyboardShortcut(.defaultAction)
                    .help("发送（⌘↩ 或默认按钮）")
                }

                if !attachedImageURLs.isEmpty {
                    attachedImagesStrip
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isQuestionFocused ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.18),
                    lineWidth: isQuestionFocused ? 1.1 : 0.8
                )
        }
        .fileImporter(
            isPresented: $isImageImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                attachedImageURLs.append(contentsOf: urls)
            }
        }
    }

    private var questionEditorHeight: CGFloat {
        let explicitLines = question.components(separatedBy: .newlines).count
        let wrappedLines = max(1, question.count / 34 + 1)
        let lines = min(10, max(explicitLines, wrappedLines))
        return CGFloat(lines) * 20 + 14
    }

    private var attachedImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(attachedImageURLs.enumerated()), id: \.offset) { index, url in
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                        Button {
                            attachedImageURLs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                }
            }
        }
    }

    private func submitQuestion() {
        shouldFollowStream = true
        var questionToSubmit = question
        if !attachedImageURLs.isEmpty {
            let names = attachedImageURLs.map(\.lastPathComponent).joined(separator: ", ")
            questionToSubmit += "\n\n[附加图片：\(names)]"
        }
        question = ""
        attachedImageURLs = []
        model.submitGuideQuestion(questionToSubmit)
    }

    private func focusQuestion() {
        DispatchQueue.main.async {
            isQuestionFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isQuestionFocused = true
        }
    }

    private func scrollIfNeeded(_ proxy: ScrollViewProxy, animated: Bool) {
        guard shouldFollowStream, hasOverflow || model.guideSession?.messages.isEmpty == false else { return }
        scrollToBottom(proxy, animated: animated)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }
}

private struct InspectorSpinner: View {
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

private struct GuideScrollState: Equatable {
    let isNearBottom: Bool
    let hasOverflow: Bool
}

private struct GuideScrollObserver: NSViewRepresentable {
    let onChange: (GuideScrollState, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attachIfNeeded()
        context.coordinator.report(userScrolled: false)
    }

    final class Coordinator: NSObject {
        var onChange: (GuideScrollState, Bool) -> Void
        lazy var view = ProbeView(coordinator: self)
        private weak var scrollView: NSScrollView?
        private var observedClipView: NSClipView?
        private var lastState: GuideScrollState?

        init(onChange: @escaping (GuideScrollState, Bool) -> Void) {
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
            let hasOverflow = documentBounds.height > visible.height + threshold
            let isNearBottom: Bool
            if !hasOverflow {
                isNearBottom = true
            } else if documentView.isFlipped {
                isNearBottom = visible.maxY >= documentBounds.maxY - threshold
            } else {
                isNearBottom = visible.minY <= documentBounds.minY + threshold
            }

            let state = GuideScrollState(isNearBottom: isNearBottom, hasOverflow: hasOverflow)
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

private extension View {
    func onHeightChange(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: GuideHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(GuideHeightPreferenceKey.self, perform: onChange)
    }
}

private struct GuideHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
