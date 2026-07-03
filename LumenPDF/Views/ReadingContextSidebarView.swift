import SwiftUI

struct ReadingContextSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: ReadingContextMode = .vocabulary
    @State private var isProgrammaticScroll = true

    private var currentPdfPath: String? { appState.selectedDocument?.filePath }

    private var items: [ReadingContextItem] {
        guard let currentPdfPath else { return [] }
        let source: [ReadingContextItem]
        switch mode {
        case .vocabulary:
            source = appState.vocabulary
                .filter { $0.pdfPath == currentPdfPath }
                .map(ReadingContextItem.vocabulary)
        case .note:
            source = appState.notes
                .filter { $0.pdfPath == currentPdfPath }
                .map(ReadingContextItem.note)
        }
        return source.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(groupedItems, id: \.pageIndex) { group in
                                pageSection(group: group)
                            }
                        }
                        .padding(12)
                    }
                    .onAppear { scrollToCurrentPage(proxy) }
                    .onChange(of: appState.currentPageIndex) { _, _ in
                        scrollToCurrentPage(proxy)
                    }
                    .onChange(of: mode) { _, _ in
                        scrollToCurrentPage(proxy)
                    }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
        .background(.background)
        .onAppear {
            appState.refreshVocabulary()
            appState.refreshNotes()
        }
    }

    private var header: some View {
        ZStack {
            Picker("", selection: $mode) {
                ForEach(ReadingContextMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(width: 260)

            HStack {
                Spacer()
                Text("\(items.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quinary, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: mode.emptySystemImage)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("这个 PDF 还没有\(mode.title)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(mode.emptyHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
    }

    private var groupedItems: [(pageIndex: UInt32, items: [ReadingContextItem])] {
        let groups = Dictionary(grouping: items, by: \.pageIndex)
        return groups.keys.sorted().map { page in
            (pageIndex: page, items: groups[page] ?? [])
        }
    }

    private func pageSection(group: (pageIndex: UInt32, items: [ReadingContextItem])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P\(group.pageIndex + 1)")
                .id(group.pageIndex)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Int(group.pageIndex) == appState.currentPageIndex ? .blue : .secondary)
                .padding(.horizontal, 4)

            ForEach(group.items) { item in
                ReadingContextCard(item: item) {
                    jump(to: item)
                }
            }
        }
        .onAppear {
            syncPdfToSidebarPage(group.pageIndex)
        }
    }

    private func scrollToCurrentPage(_ proxy: ScrollViewProxy) {
        let current = UInt32(max(0, appState.currentPageIndex))
        let target = groupedItems.first { $0.pageIndex >= current }?.pageIndex
            ?? groupedItems.last?.pageIndex
        guard let target else { return }
        isProgrammaticScroll = true
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isProgrammaticScroll = false
        }
    }

    private func syncPdfToSidebarPage(_ pageIndex: UInt32) {
        guard !isProgrammaticScroll,
              Int(pageIndex) != appState.currentPageIndex,
              let currentPdfPath else { return }
        NotificationCenter.default.post(
            name: .jumpToPage,
            object: nil,
            userInfo: [
                "pageIndex": Int(pageIndex),
                "filePath": currentPdfPath
            ]
        )
    }

    private func jump(to item: ReadingContextItem) {
        appState.activeTab = .reader
        NotificationCenter.default.post(
            name: .jumpToSelectionBounds,
            object: nil,
            userInfo: [
                "pageIndex": Int(item.pageIndex),
                "filePath": item.pdfPath,
                "boundsStr": item.boundsStr,
                "itemId": item.id,
                "kind": item.kind.rawValue
            ]
        )
        appState.showToast("已定位到 P\(item.pageIndex + 1)")
    }
}

private enum ReadingContextMode: String, CaseIterable, Identifiable {
    case vocabulary
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: return "单词"
        case .note: return "笔记"
        }
    }

    var emptySystemImage: String {
        switch self {
        case .vocabulary: return "book.closed"
        case .note: return "note.text"
        }
    }

    var emptyHint: String {
        switch self {
        case .vocabulary: return "选中文本后保存到单词本，会显示在这里。"
        case .note: return "选中文本后保存为划线笔记，会显示在这里。"
        }
    }
}

private struct ReadingContextItem: Identifiable {
    enum Kind: String {
        case vocabulary
        case note

        var title: String {
            switch self {
            case .vocabulary: return "单词"
            case .note: return "笔记"
            }
        }

        var systemImage: String {
            switch self {
            case .vocabulary: return "book.closed"
            case .note: return "note.text"
            }
        }

        var tint: Color {
            switch self {
            case .vocabulary: return .yellow
            case .note: return .red
            }
        }
    }

    let id: String
    let kind: Kind
    let pageIndex: UInt32
    let pdfPath: String
    let boundsStr: String
    let title: String
    let subtitle: String
    let detail: String
    let noteMarkdownItems: [String]
    let createdAt: Int64

    static func vocabulary(_ entry: VocabularyEntry) -> ReadingContextItem {
        ReadingContextItem(
            id: entry.id,
            kind: .vocabulary,
            pageIndex: entry.pageIndex,
            pdfPath: entry.pdfPath,
            boundsStr: entry.selectionBounds,
            title: entry.word,
            subtitle: entry.contextTranslation,
            detail: ContextSentenceFormatting.displayParagraph(entry.sentence),
            noteMarkdownItems: [],
            createdAt: entry.createdAt
        )
    }

    static func note(_ note: NoteEntry) -> ReadingContextItem {
        let noteItems = NoteTextList.decode(note.note)
        return ReadingContextItem(
            id: note.id,
            kind: .note,
            pageIndex: note.pageIndex,
            pdfPath: note.pdfPath,
            boundsStr: note.boundsStr,
            title: ContextSentenceFormatting.displayParagraph(note.content),
            subtitle: noteItems.joined(separator: "\n"),
            detail: "",
            noteMarkdownItems: noteItems,
            createdAt: note.createdAt
        )
    }
}

private struct ReadingContextCard: View {
    let item: ReadingContextItem
    let onJump: () -> Void

    @State private var isExpanded = false

    private var isNote: Bool {
        item.kind == .note
    }

    private var titleLineLimit: Int? {
        guard isNote else { return 3 }
        return isExpanded ? nil : 4
    }

    private var subtitleLineLimit: Int? {
        guard isNote else { return 4 }
        return isExpanded ? nil : 6
    }

    private var expandsFullText: Bool {
        isNote && isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onJump) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Label(item.kind.title, systemImage: item.kind.systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("P\(item.pageIndex + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.title)
                        .font(item.kind == .vocabulary ? .headline : .callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(titleLineLimit)
                        .fixedSize(horizontal: false, vertical: expandsFullText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isNote {
                        noteMarkdownContent
                    } else if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(subtitleLineLimit)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !item.detail.isEmpty {
                        Text("“\(item.detail)”")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isNote {
                disclosureButton
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.kind.tint.opacity(item.kind == .vocabulary ? 0.75 : 0.55))
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var noteMarkdownContent: some View {
        if !item.noteMarkdownItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.noteMarkdownItems.enumerated()), id: \.offset) { _, markdown in
                    MarkdownText(markdown: markdown)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: expandsFullText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: isExpanded ? nil : 180, alignment: .top)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var disclosureButton: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Label(isExpanded ? "收起" : "展开", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isExpanded ? "收起笔记预览" : "展开完整笔记")
        }
    }
}
