import SwiftUI

extension NoteEntry: Identifiable {}

struct NoteListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var editingNote: NoteEntry?
    @State private var showExportSheet = false
    @State private var exportContent = ""

    private var filtered: [NoteEntry] {
        guard !searchText.isEmpty else { return appState.notes }
        let q = searchText.lowercased()
        return appState.notes.filter {
            $0.content.lowercased().contains(q)
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
                                onEdit: { editingNote = $0 },
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
        .sheet(item: $editingNote) { note in
            NoteEditSheet(note: note) { appState.refreshNotes() }
        }
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
        try? BridgeService.shared.deleteNote(id: note.id)
        // Remove underline annotation from PDF when deleting note
        NotificationCenter.default.post(
            name: .removeUnderlineNote,
            object: nil,
            userInfo: ["noteId": note.id, "pageIndex": Int(note.pageIndex), "filePath": note.pdfPath]
        )
        appState.refreshNotes()
    }

    private func jumpToPDF(note: NoteEntry) {
        if let doc = appState.library.first(where: { $0.filePath == note.pdfPath }) {
            appState.selectedDocument = doc
            appState.activeTab = .reader
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(
                    name: .jumpToPage, object: nil,
                    userInfo: ["pageIndex": Int(note.pageIndex), "filePath": note.pdfPath]
                )
            }
        }
    }
}

// MARK: - Note Card View

struct NoteCardView: View {
    let note: NoteEntry
    let onEdit: (NoteEntry) -> Void
    let onDelete: (NoteEntry) -> Void
    let onJump: (NoteEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Content (highlighted text)
            Text(note.content)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // User note
            if !note.note.isEmpty {
                Text(note.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
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

                Button { onEdit(note) } label: {
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

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

// MARK: - Note Edit Sheet

struct NoteEditSheet: View {
    let note: NoteEntry
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String

    init(note: NoteEntry, onSave: @escaping () -> Void) {
        self.note = note
        self.onSave = onSave
        _noteText = State(initialValue: note.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑笔记").font(.title2.bold())

            Divider()

            Text("划线内容：")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(note.content)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))

            Text("笔记：")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextEditor(text: $noteText)
                .font(.body)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            HStack {
                Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                Text("\(note.pdfName)  P\(note.pageIndex + 1)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    try? BridgeService.shared.updateNote(id: note.id, note: noteText)
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 400)
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