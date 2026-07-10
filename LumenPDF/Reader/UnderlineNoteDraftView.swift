import SwiftUI

struct UnderlineNoteDraftView: View {
    let draft: UnderlineNoteDraft
    let dragGesture: AnyGesture<DragGesture.Value>
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var noteText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .contentShape(Rectangle())
            .gesture(dragGesture)

            ScrollView {
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
            .frame(maxHeight: 260)

            HStack(alignment: .center) {
                Text(draft.appendingNoteId == nil ? "可留空；保存后会添加笔记划线" : "会追加到现有笔记")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.borderless)
                Button("保存") {
                    onSave(noteText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(width: 380)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        .onAppear { isFocused = true }
    }
}
