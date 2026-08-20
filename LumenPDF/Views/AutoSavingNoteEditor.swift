import SwiftUI

enum NoteAutoSavePolicy {
    static let debounceNanoseconds: UInt64 = 450_000_000

    static func textToSave(_ text: String, lastSaved: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let last = lastSaved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != last else { return nil }
        return trimmed
    }
}

struct AutoSavingNoteEditor: View {
    let minLineLimit: Int
    let maxLineLimit: Int
    let onSave: (String) -> Bool

    @State private var text: String
    @State private var lastSavedText: String
    @State private var didSaveSuccessfully = false
    @State private var saveFailed = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(
        initialText: String,
        minLineLimit: Int = 2,
        maxLineLimit: Int = 12,
        onSave: @escaping (String) -> Bool
    ) {
        self.minLineLimit = minLineLimit
        self.maxLineLimit = maxLineLimit
        self.onSave = onSave
        _text = State(initialValue: initialText)
        _lastSavedText = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("输入笔记", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(minLineLimit...maxLineLimit)
                .focused($isFocused)
                .padding(8)
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(isFocused ? 0.18 : 0.08), lineWidth: 0.5)
                )
                .help("修改后自动保存")

            HStack(spacing: 8) {
                Text("修改后自动保存")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if saveFailed {
                    Label("保存失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else if didSaveSuccessfully {
                    Label("保存成功", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                }
            }
        }
        .onChange(of: text) { _, newValue in
            scheduleSave(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            saveTask?.cancel()
            persistIfNeeded(text)
        }
        .onDisappear {
            saveTask?.cancel()
            persistIfNeeded(text)
        }
    }

    private func scheduleSave(_ newValue: String) {
        didSaveSuccessfully = false
        saveFailed = false
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: NoteAutoSavePolicy.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            persistIfNeeded(newValue)
        }
    }

    private func persistIfNeeded(_ newValue: String) {
        guard let prepared = NoteAutoSavePolicy.textToSave(newValue, lastSaved: lastSavedText) else {
            return
        }
        if onSave(prepared) {
            lastSavedText = prepared
            didSaveSuccessfully = true
            saveFailed = false
        } else {
            saveFailed = true
            didSaveSuccessfully = false
        }
    }
}
