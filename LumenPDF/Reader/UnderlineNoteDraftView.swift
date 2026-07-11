import SwiftUI

struct UnderlineNoteDraftView: View {
    let draft: UnderlineNoteDraft
    let availableSize: CGSize
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var noteText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ReadingOverlayWindow(
            anchorRect: overlayAnchorRect,
            availableSize: availableSize,
            resetID: resetID,
            configuration: ReadingOverlayWindowConfiguration(
                width: 380,
                initialContentHeight: 150,
                minimumContentHeight: 120
            ),
            onDismiss: onCancel,
            header: { header },
            content: { content },
            footer: { footer }
        )
        .onAppear { isFocused = true }
    }

    private var overlayAnchorRect: CGRect {
        draft.anchorRect.isEmpty
            ? CGRect(x: draft.anchor.x - 80, y: max(0, draft.anchor.y - 8), width: 160, height: 44)
            : draft.anchorRect
    }

    private var resetID: AnyHashable {
        AnyHashable("\(draft.page)|\(draft.boundsStr)|\(draft.appendingNoteId ?? "new")")
    }

    private var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedNoteText.isEmpty
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(draft.appendingNoteId == nil ? "添加笔记" : "追加笔记")
                .font(.headline)
            Spacer()
            Button(action: onCancel) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text(ContextSentenceFormatting.displayParagraph(draft.word))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $noteText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 74)
                .focused($isFocused)
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text(draft.appendingNoteId == nil ? "请输入笔记内容；保存后会添加笔记划线" : "请输入要追加的笔记内容")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("取消", action: onCancel)
                .buttonStyle(.borderless)
            Button("保存") {
                guard canSave else { return }
                onSave(trimmedNoteText)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}
