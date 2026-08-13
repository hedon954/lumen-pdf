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
    var retryRequest: ExplanationRetryRequest?

    init(
        id: UUID = UUID(),
        role: ExplanationMessageRole,
        content: String,
        isError: Bool = false,
        retryRequest: ExplanationRetryRequest? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isError = isError
        self.retryRequest = retryRequest
    }
}

struct ExplanationRetryRequest: Equatable {
    let focus: String
    let imageURLs: [URL]
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
    case words
    case notes
    case ai

    var id: String { rawValue }

    static func storedMode(from rawValue: String) -> Self? {
        if let mode = Self(rawValue: rawValue) {
            return mode
        }

        switch rawValue {
        case "context": return .words
        case "guide": return .ai
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .words: return "单词"
        case .notes: return "笔记"
        case .ai: return "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .words: return "book.closed"
        case .notes: return "note.text"
        case .ai: return "sparkles"
        }
    }
}
