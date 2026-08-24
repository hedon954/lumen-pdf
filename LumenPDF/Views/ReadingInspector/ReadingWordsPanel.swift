import SwiftUI

struct ReadingWordsPanel: View {
    @EnvironmentObject private var appState: AppState

    private struct WordItem: Identifiable {
        let id: String
        let pageIndex: UInt32
        let pdfPath: String
        let boundsStr: String
        let title: String
        let subtitle: String
        let detail: String
        let createdAt: Int64
    }

    private var currentPdfPath: String? { appState.selectedDocument?.filePath }

    private var items: [WordItem] {
        guard let currentPdfPath else { return [] }
        return appState.vocabulary
            .filter { $0.pdfPath == currentPdfPath }
            .map {
                WordItem(
                    id: $0.id,
                    pageIndex: $0.pageIndex,
                    pdfPath: $0.pdfPath,
                    boundsStr: $0.selectionBounds,
                    title: $0.word,
                    subtitle: $0.contextTranslation,
                    detail: ContextSentenceFormatting.displayParagraph($0.sentence),
                    createdAt: $0.createdAt
                )
            }
            .sorted { lhs, rhs in
                let current = UInt32(max(0, appState.currentPageIndex))
                let lhsDistance = abs(Int(lhs.pageIndex) - Int(current))
                let rhsDistance = abs(Int(rhs.pageIndex) - Int(current))
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
            .prefix(36)
            .map { $0 }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ReadingInspectorEmptyState(
                    systemImage: "text.magnifyingglass",
                    title: "暂无单词",
                    message: "保存单词后会显示在这里"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            contextCard(item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear {
            appState.refreshVocabulary()
        }
    }

    private func contextCard(_ item: WordItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                jump(to: item)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Label("单词", systemImage: "book.closed")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("P\(item.pageIndex + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Color.clear.frame(width: 18, height: 1)
                    }

                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                delete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.72))
            }
            .buttonStyle(.plain)
            .padding(10)
            .help("删除单词")
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.yellow.opacity(0.62))
                .frame(width: 3)
                .padding(.vertical, 9)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func delete(_ item: WordItem) {
        do {
            try ReaderPersistence.shared.deleteVocabularyRemovingHighlight(
                id: item.id,
                page: Int(item.pageIndex),
                filePath: item.pdfPath
            )
            appState.refreshVocabulary()
            appState.showToast("已删除单词")
        } catch {
            appState.showToast("删除单词失败")
        }
    }

    private func jump(to item: WordItem) {
        ReaderEventBus.shared.postJumpToSelectionBounds(
            page: Int(item.pageIndex),
            filePath: item.pdfPath,
            boundsStr: item.boundsStr,
            itemId: item.id,
            kind: "vocabulary"
        )
        appState.showToast("已定位到 P\(item.pageIndex + 1)")
    }
}
