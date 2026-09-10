import SwiftUI

struct NoteReviewPopoverView: View {
    let review: ActiveNoteReview
    let availableSize: CGSize
    let overlayAnchorRect: CGRect
    let onOpenNotes: () -> Void
    let onSaveItem: (String, Int, String, String, Int) -> Bool
    let onAppend: (String) -> Bool
    let onDeleteItem: (String, Int) -> Void
    let onDeleteAll: () -> Void
    let onClose: () -> Void

    @State private var pendingDeletion: NoteReviewDeletion?
    @State private var newNoteText = ""
    @State private var appendFailed = false
    @FocusState private var isAddingNote: Bool

    private var noteItems: [NoteReviewItem] {
        review.notes.flatMap { note in
            NoteTextList.decode(note.note).enumerated().map { index, markdown in
                NoteReviewItem(
                    id: "\(note.id)#\(index)#\(NoteTextList.decode(note.note).count)",
                    noteId: note.id,
                    itemIndex: index,
                    itemCount: NoteTextList.decode(note.note).count,
                    markdown: markdown,
                    createdAt: note.createdAt
                )
            }
        }
    }

    var body: some View {
        ReadingOverlayWindow(
            anchorRect: overlayAnchorRect,
            availableSize: availableSize,
            resetID: AnyHashable(review.id),
            configuration: ReadingOverlayWindowConfiguration(
                width: 420,
                initialContentHeight: 300,
                minimumContentHeight: 120
            ),
            onDismiss: onClose,
            header: { header },
            content: { content },
            footer: { footer }
        )
        .alert(item: $pendingDeletion) { deletion in
            switch deletion {
            case let .item(noteId, itemIndex):
                return Alert(
                    title: Text("删除这条笔记？"),
                    message: Text("删除后无法恢复。"),
                    primaryButton: .destructive(Text("删除")) {
                        onDeleteItem(noteId, itemIndex)
                    },
                    secondaryButton: .cancel()
                )
            case let .all(count):
                return Alert(
                    title: Text("删除全部笔记？"),
                    message: Text("这里的 \(count) 条笔记及对应划线都会被删除，且无法恢复。"),
                    primaryButton: .destructive(Text("全部删除"), action: onDeleteAll),
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("笔记")
                .font(.headline)
            Spacer()
            ReadingOverlayMoveHandle()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let first = review.notes.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("原文")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(ContextSentenceFormatting.displayParagraph(first.content))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            ForEach(noteItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let createdAt = ReadingInspectorDateFormat.timestampText(for: item.createdAt) {
                            Text(createdAt)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDeletion = .item(
                                noteId: item.noteId,
                                itemIndex: item.itemIndex
                            )
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .help("删除这条笔记")
                    }
                    AutoSavingNoteEditor(
                        initialText: item.markdown,
                        minLineLimit: 3,
                        maxLineLimit: 16,
                        onSaveWithPreviousText: { text, previousText in
                            onSaveItem(item.noteId, item.itemIndex, text, previousText, item.itemCount)
                        }
                    )
                    .id(item.id)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("添加新笔记…", text: $newNoteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isAddingNote)
                    .padding(8)
                    .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("noteReview.newNote")
                Button("添加", action: appendNote)
                    .buttonStyle(.borderedProminent)
                    .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("noteReview.add")
            }
            if appendFailed {
                Text("添加失败，内容已保留，请重试")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(role: .destructive) {
                    pendingDeletion = .all(count: noteItems.count)
                } label: {
                    Label("删除全部", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(noteItems.isEmpty)
                Spacer()
                Button("打开右侧笔记", action: onOpenNotes)
                    .buttonStyle(.borderless)
                Button("关闭", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private func appendNote() {
        guard onAppend(newNoteText) else {
            appendFailed = true
            return
        }
        newNoteText = ""
        appendFailed = false
        isAddingNote = true
    }
}

private struct NoteReviewItem: Identifiable {
    let id: String
    let noteId: String
    let itemIndex: Int
    let itemCount: Int
    let markdown: String
    let createdAt: Int64
}

private enum NoteReviewDeletion: Identifiable {
    case item(noteId: String, itemIndex: Int)
    case all(count: Int)

    var id: String {
        switch self {
        case let .item(noteId, itemIndex):
            return "item|\(noteId)|\(itemIndex)"
        case let .all(count):
            return "all|\(count)"
        }
    }
}
