import SwiftUI

struct ReadingContextPanel: View {
    @EnvironmentObject private var appState: AppState

    private enum ContextKind: String {
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

    private struct ContextItem: Identifiable {
        let id: String
        let kind: ContextKind
        let pageIndex: UInt32
        let pdfPath: String
        let boundsStr: String
        let title: String
        let subtitle: String
        let detail: String
        let createdAt: Int64
    }

    private var currentPdfPath: String? { appState.selectedDocument?.filePath }

    private var items: [ContextItem] {
        guard let currentPdfPath else { return [] }
        let vocabularyItems = appState.vocabulary
            .filter { $0.pdfPath == currentPdfPath }
            .map {
                ContextItem(
                    id: $0.id,
                    kind: .vocabulary,
                    pageIndex: $0.pageIndex,
                    pdfPath: $0.pdfPath,
                    boundsStr: $0.selectionBounds,
                    title: $0.word,
                    subtitle: $0.contextTranslation,
                    detail: ContextSentenceFormatting.displayParagraph($0.sentence),
                    createdAt: $0.createdAt
                )
            }

        let noteItems = ReadingInspectorNoteGroup
            .groups(from: appState.notes.filter { $0.pdfPath == currentPdfPath })
            .map {
                ContextItem(
                    id: $0.id,
                    kind: .note,
                    pageIndex: $0.pageIndex,
                    pdfPath: $0.pdfPath,
                    boundsStr: $0.boundsStr,
                    title: $0.title,
                    subtitle: $0.notes.first?.markdown ?? "",
                    detail: $0.notes.count > 1 ? "\($0.notes.count) 条笔记" : "",
                    createdAt: $0.createdAt
                )
            }

        return (vocabularyItems + noteItems)
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
                    title: "暂无上下文",
                    message: "保存单词或笔记后会显示在这里"
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
            appState.refreshNotes()
        }
    }

    private func contextCard(_ item: ContextItem) -> some View {
        Button {
            jump(to: item)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
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
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.kind.tint.opacity(0.62))
                    .frame(width: 3)
                    .padding(.vertical, 9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func jump(to item: ContextItem) {
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
