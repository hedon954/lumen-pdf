import SwiftUI

extension NoteEntry: Identifiable {}

struct NoteListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showExportSheet = false
    @State private var exportContent = ""

    private var filtered: [NoteEntry] {
        guard !searchText.isEmpty else { return appState.notes }
        let q = searchText.lowercased()
        return appState.notes.filter {
            ContextSentenceFormatting.displayParagraph($0.content).lowercased().contains(q)
            || $0.note.lowercased().contains(q)
            || $0.pdfName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + Export button
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索笔记…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 18)

                Button {
                    exportContent = BridgeService.shared.exportNotesMarkdown()
                    showExportSheet = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            .padding(12)

            Divider()

            if appState.notes.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Spacer()
                Text("没有匹配结果").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { note in
                            NoteCardView(
                                note: note,
                                onSaveItem: { itemIndex, text in
                                    appState.saveNoteItem(noteId: note.id, itemIndex: itemIndex, text: text)
                                },
                                onDelete: { delete($0) },
                                onJump: { jumpToPDF(note: $0) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .onAppear { appState.refreshNotes() }
        .sheet(isPresented: $showExportSheet) {
            NoteExportView(content: $exportContent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("还没有笔记").foregroundStyle(.secondary)
            Text("选中文本后点击「笔记」按钮添加").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func delete(_ note: NoteEntry) {
        try? BridgeService.shared.deleteNoteRemovingUnderline(
            id: note.id,
            page: Int(note.pageIndex),
            filePath: note.pdfPath
        )
        appState.refreshNotes()
    }

    private func jumpToPDF(note: NoteEntry) {
        appState.openLibraryDocument(filePath: note.pdfPath, page: Int(note.pageIndex))
    }
}

// MARK: - Note Card View

struct NoteCardView: View {
    let note: NoteEntry
    let onSaveItem: (Int, String) -> Bool
    let onDelete: (NoteEntry) -> Void
    let onJump: (NoteEntry) -> Void

    private var displayContent: String {
        ContextSentenceFormatting.displayParagraph(note.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Content (highlighted text)
            Text(displayContent)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // User notes
            let noteItems = NoteTextList.decode(note.note)
            if !noteItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(noteItems.enumerated()), id: \.offset) { index, item in
                        AutoSavingNoteEditor(
                            initialText: item,
                            minLineLimit: 2,
                            maxLineLimit: 12,
                            onSave: { text in
                                onSaveItem(index, text)
                            }
                        )
                        .id("\(note.id)#\(index)")
                    }
                }
            }

            // Footer
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                Button {
                    onJump(note)
                } label: {
                    Text("\(note.pdfName)  P\(note.pageIndex + 1)")
                        .font(.caption2).foregroundStyle(.secondary).underline()
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive) { onDelete(note) } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Note Export View

struct NoteExportView: View {
    @Binding var content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("导出笔记").font(.title2.bold())
            Divider()

            ScrollView {
                Text(content)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxHeight: 400)

            HStack {
                Button("关闭") { dismiss() }
                Spacer()
                Button("复制到剪贴板") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }
                Button("保存为文件") {
                    saveToFile()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500, height: 520)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "LumenPDF_Notes.md"
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
