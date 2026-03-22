import SwiftUI

// VocabularyEntry has `id: String` — just declare conformance so sheet(item:) works.
extension VocabularyEntry: Identifiable {}

struct VocabularyListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var audio = AudioService()
    @State private var searchText = ""
    @State private var editingEntry: VocabularyEntry?

    private var filtered: [VocabularyEntry] {
        guard !searchText.isEmpty else { return appState.vocabulary }
        let q = searchText.lowercased()
        return appState.vocabulary.filter {
            $0.word.lowercased().contains(q)
            || $0.contextTranslation.lowercased().contains(q)
            || $0.generalDefinition.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索单词…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(8)

            Divider()

            if appState.vocabulary.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("还没有保存单词")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if filtered.isEmpty {
                Spacer()
                Text("没有匹配结果")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered, id: \.id) { entry in
                    VocabularyRow(entry: entry, audio: audio)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { delete(entry) } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button { editingEntry = entry } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .onTapGesture { jumpToPDF(entry: entry) }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear { appState.refreshVocabulary() }
        .sheet(item: $editingEntry) { entry in
            VocabularyEditSheet(entry: entry) {
                appState.refreshVocabulary()
            }
        }
    }

    private func delete(_ entry: VocabularyEntry) {
        try? BridgeService.shared.deleteVocabulary(id: entry.id)
        appState.refreshVocabulary()
    }

    private func jumpToPDF(entry: VocabularyEntry) {
        if let doc = appState.library.first(where: { $0.filePath == entry.pdfPath }) {
            appState.selectedDocument = doc
            appState.activeTab = .reader
            // After the PDF loads, scroll to the page via notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(
                    name: .jumpToPage,
                    object: nil,
                    userInfo: ["pageIndex": Int(entry.pageIndex), "filePath": entry.pdfPath]
                )
            }
        }
    }
}

// MARK: - Row

private struct VocabularyRow: View {
    let entry: VocabularyEntry
    let audio: AudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Word + phonetic + POS + pronounce
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.word)
                    .font(.callout.bold())

                if !entry.phonetic.isEmpty {
                    Text("[\(entry.phonetic)]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !entry.partOfSpeech.isEmpty {
                    Text(entry.partOfSpeech)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Spacer()

                Button { audio.speak(entry.word) } label: {
                    Image(systemName: "speaker.wave.1")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Context translation
            if !entry.contextTranslation.isEmpty {
                Text(entry.contextTranslation)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }

            // General definition
            if !entry.generalDefinition.isEmpty {
                Text(entry.generalDefinition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Original sentence
            if !entry.sentence.isEmpty {
                Text("「\(entry.sentence)」")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .lineLimit(2)
            }

            // Source + page + query count + translation source badge
            HStack(spacing: 8) {
                Label("\(entry.pdfName) · P\(entry.pageIndex + 1)", systemImage: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if entry.queryCount > 0 {
                    Label("\(entry.queryCount)次查询", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(sourceLabel(entry.translationSource))
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(sourceBadgeColor(entry.translationSource).opacity(0.12), in: Capsule())
                    .foregroundStyle(sourceBadgeColor(entry.translationSource))
            }
        }
        .padding(.vertical, 4)
    }

    private func sourceLabel(_ src: String) -> String {
        switch src {
        case "llm": return "AI 翻译"
        case "fallback": return "基础翻译"
        case "cache": return "缓存"
        default: return src
        }
    }

    private func sourceBadgeColor(_ src: String) -> Color {
        switch src {
        case "llm": return .purple
        case "fallback": return .orange
        default: return .gray
        }
    }
}

// MARK: - Edit sheet

private struct VocabularyEditSheet: View {
    let entry: VocabularyEntry
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var annotationNote: String

    init(entry: VocabularyEntry, onSave: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        _annotationNote = State(initialValue: entry.annotationId ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑「\(entry.word)」")
                .font(.title2.bold())

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("个人备注").font(.caption.bold()).foregroundStyle(.secondary)
                TextEditor(text: $annotationNote)
                    .font(.callout)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }

            // Read-only info
            Group {
                infoRow("音标", entry.phonetic)
                infoRow("语境释义", entry.contextTranslation)
                infoRow("通用释义", entry.generalDefinition)
                infoRow("来源", "\(entry.pdfName) P\(entry.pageIndex + 1)")
            }

            Spacer()

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    try? BridgeService.shared.updateVocabularyAnnotation(
                        id: entry.id,
                        annotationId: annotationNote
                    )
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380, height: 420)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

extension Notification.Name {
    static let jumpToPage = Notification.Name("jumpToPage")
}
