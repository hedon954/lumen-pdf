import Foundation

enum ExplanationMessageRole: String, Equatable {
    case user
    case assistant
}

struct ExplanationMessage: Identifiable, Equatable {
    let id: UUID
    let role: ExplanationMessageRole
    var content: String
    var isError: Bool

    init(id: UUID = UUID(), role: ExplanationMessageRole, content: String, isError: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isError = isError
    }
}

struct ExplanationSession: Identifiable, Equatable {
    let id: UUID
    let selection: PDFSelectionContext
    var messages: [ExplanationMessage]
    var summary: String
    var isLoading: Bool
    var errorMessage: String?
    var savedNoteIdsByMessageId: [UUID: String]

    init(
        id: UUID = UUID(),
        selection: PDFSelectionContext,
        messages: [ExplanationMessage] = [],
        summary: String = "",
        isLoading: Bool = false,
        errorMessage: String? = nil,
        savedNoteIdsByMessageId: [UUID: String] = [:]
    ) {
        self.id = id
        self.selection = selection
        self.messages = messages
        self.summary = summary
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.savedNoteIdsByMessageId = savedNoteIdsByMessageId
    }

    var completedAssistantMessages: [ExplanationMessage] {
        messages.filter {
            $0.role == .assistant &&
            !$0.isError &&
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var hasSavedMessages: Bool {
        !savedNoteIdsByMessageId.isEmpty
    }
}

enum ReadingInspectorMode: String, CaseIterable, Identifiable {
    case context
    case guide
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .context: return "上下文"
        case .guide: return "导读"
        case .notes: return "笔记"
        }
    }

    var systemImage: String {
        switch self {
        case .context: return "sidebar.right"
        case .guide: return "sparkles"
        case .notes: return "note.text"
        }
    }
}
