import SwiftUI

struct ReadingNotesPanel: View {
    @EnvironmentObject private var appState: AppState

    private var noteGroups: [ReadingInspectorNoteGroup] {
        guard let path = appState.selectedDocument?.filePath else { return [] }
        return ReadingInspectorNoteGroup.groups(
            from: appState.notes.filter { $0.pdfPath == path }
        )
    }

    var body: some View {
        Group {
            if noteGroups.isEmpty {
                ReadingInspectorEmptyState(
                    systemImage: "note.text",
                    title: "暂无笔记",
                    message: "划选文本后可创建笔记"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedByPage, id: \.pageIndex) { pageGroup in
                            pageSection(pageGroup)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear { appState.refreshNotes() }
    }

    private var groupedByPage: [(pageIndex: UInt32, items: [ReadingInspectorNoteGroup])] {
        let groups = Dictionary(grouping: noteGroups, by: \.pageIndex)
        return groups.keys.sorted().map { page in
            (pageIndex: page, items: groups[page] ?? [])
        }
    }

    private func pageSection(_ group: (pageIndex: UInt32, items: [ReadingInspectorNoteGroup])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P\(group.pageIndex + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Int(group.pageIndex) == appState.currentPageIndex ? .blue : .secondary)
                .padding(.horizontal, 3)

            ForEach(group.items) { noteGroup in
                ReadingInspectorNoteCard(group: noteGroup) {
                    jump(to: noteGroup)
                }
            }
        }
    }

    private func jump(to group: ReadingInspectorNoteGroup) {
        NotificationCenter.default.post(
            name: .jumpToSelectionBounds,
            object: nil,
            userInfo: [
                "pageIndex": Int(group.pageIndex),
                "filePath": group.pdfPath,
                "boundsStr": group.boundsStr,
                "itemId": group.sourceId,
                "kind": "note"
            ]
        )
        appState.showToast("已定位到 P\(group.pageIndex + 1)")
    }
}

private struct ReadingInspectorNoteCard: View {
    let group: ReadingInspectorNoteGroup
    let onJump: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onJump) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Label("笔记", systemImage: "note.text")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if group.notes.count > 1 {
                            Text("\(group.notes.count)条")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text("P\(group.pageIndex + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    Text(group.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: isExpanded)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    noteList
                }
            }
            .buttonStyle(.plain)

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
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red.opacity(0.55))
                .frame(width: 3)
                .padding(.vertical, 9)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var noteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                if index > 0 {
                    Divider().opacity(0.55)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let createdAt = ReadingInspectorDateFormat.timestampText(for: note.createdAt) {
                        Text(createdAt)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    MarkdownText(markdown: note.markdown)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 6)
                        .fixedSize(horizontal: false, vertical: isExpanded)
                }
            }
        }
        .frame(maxHeight: isExpanded ? nil : 180, alignment: .top)
        .clipped()
    }
}
