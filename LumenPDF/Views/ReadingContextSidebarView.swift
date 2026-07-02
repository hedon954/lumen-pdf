import SwiftUI

struct ReadingContextSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var kindFilter: ReadingContextKindFilter = .all
    @State private var pageFilter: ReadingContextPageFilter = .all

    private var currentPdfPath: String? { appState.selectedDocument?.filePath }

    private var items: [ReadingContextItem] {
        guard let currentPdfPath else { return [] }

        let vocabularyItems = appState.vocabulary
            .filter { $0.pdfPath == currentPdfPath }
            .map(ReadingContextItem.vocabulary)
        let noteItems = appState.notes
            .filter { $0.pdfPath == currentPdfPath }
            .map(ReadingContextItem.note)

        return (vocabularyItems + noteItems)
            .filter { item in
                switch kindFilter {
                case .all: return true
                case .vocabulary: return item.kind == .vocabulary
                case .note: return item.kind == .note
                }
            }
            .filter { item in
                switch pageFilter {
                case .all: return true
                case .currentPage: return Int(item.pageIndex) == appState.currentPageIndex
                }
            }
            .sorted { lhs, rhs in
                if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
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
                    .onChange(of: appState.currentPageIndex) { _, pageIndex in
                        guard pageFilter == .currentPage else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(UInt32(pageIndex), anchor: .top)
                        }
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
        HStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .foregroundStyle(.secondary)
            Text("单词 / 笔记")
                .font(.headline)
            Spacer()
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quinary, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var filters: some View {
        VStack(spacing: 8) {
            Picker("类型", selection: $kindFilter) {
                ForEach(ReadingContextKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("范围", selection: $pageFilter) {
                ForEach(ReadingContextPageFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: pageFilter == .currentPage ? "doc.text.magnifyingglass" : "tray")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("选中文本后保存到单词本或笔记，会显示在这里。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
    }

    private var emptyTitle: String {
        if pageFilter == .currentPage {
            return "当前页暂无单词或笔记"
        }
        return "这个 PDF 还没有单词或笔记"
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

private enum ReadingContextKindFilter: String, CaseIterable, Identifiable {
    case all
    case vocabulary
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .vocabulary: return "单词"
        case .note: return "笔记"
        }
    }
}

private enum ReadingContextPageFilter: String, CaseIterable, Identifiable {
    case all
    case currentPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部范围"
        case .currentPage: return "本页"
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
            createdAt: entry.createdAt
        )
    }

    static func note(_ note: NoteEntry) -> ReadingContextItem {
        ReadingContextItem(
            id: note.id,
            kind: .note,
            pageIndex: note.pageIndex,
            pdfPath: note.pdfPath,
            boundsStr: note.boundsStr,
            title: ContextSentenceFormatting.displayParagraph(note.content),
            subtitle: note.note,
            detail: "",
            createdAt: note.createdAt
        )
    }
}

private struct ReadingContextCard: View {
    let item: ReadingContextItem
    let onJump: () -> Void

    var body: some View {
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
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
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
        .buttonStyle(.plain)
    }
}
