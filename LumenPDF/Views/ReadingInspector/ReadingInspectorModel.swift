import Foundation

@MainActor
final class ReadingInspectorModel: ObservableObject {
    @Published var isVisible: Bool {
        didSet { restorationStore.updateInspectorVisibility(isVisible) }
    }
    @Published var width: Double {
        didSet { restorationStore.updateInspectorWidth(Self.clampedWidth(width)) }
    }
    @Published var mode: ReadingInspectorMode {
        didSet { restorationStore.updateInspectorMode(mode.rawValue) }
    }
    @Published var selection: PDFSelectionContext?
    @Published var guideSession: ExplanationSession?
    @Published private(set) var imageInputCapability: ImageInputCapability = .unknown
    @Published private(set) var isCheckingImageInputCapability = false

    private let guideService = ReadingGuideService()
    private let restorationStore: ReadingRestorationStore

    static let minimumWidth = ReadingRestorationState.minimumInspectorWidth
    static let defaultWidth = ReadingRestorationState.defaultInspectorWidth
    static let maximumWidth = ReadingRestorationState.maximumInspectorWidth

    init(restorationStore: ReadingRestorationStore = .shared) {
        self.restorationStore = restorationStore
        let inspector = restorationStore.state.inspector
        isVisible = inspector.isVisible
        width = Self.clampedWidth(inspector.width)

        if let storedMode = ReadingInspectorMode.storedMode(from: inspector.mode) {
            mode = storedMode
        } else {
            mode = .words
        }
    }

    func setWidth(_ width: CGFloat) {
        self.width = Self.clampedWidth(Double(width))
    }

    func startGuide(selection: PDFSelectionContext) {
        self.selection = selection
        guideSession = ExplanationSession(selection: selection)
        mode = .ai
        isVisible = true
    }

    func clearForDocumentChange(pdfPath: String?) {
        guard selection?.pdfPath != pdfPath else { return }
        selection = nil
        guideSession = nil
    }

    func submitGuideQuestion(_ question: String, imageURLs: [URL] = []) {
        guard let session = guideSession, !session.isLoading else { return }
        guideService.submitQuestion(
            question,
            imageURLs: imageURLs,
            session: session
        ) { [weak self] updated in
            guard self?.guideSession?.id == updated.id else { return }
            self?.guideSession = updated
        }
    }

    func retryGuideMessage(_ messageID: UUID) {
        guard let session = guideSession, !session.isLoading else { return }
        guideService.retryMessage(messageID, session: session) { [weak self] updated in
            guard self?.guideSession?.id == updated.id else { return }
            self?.guideSession = updated
        }
    }

    func refreshImageInputCapability() async {
        isCheckingImageInputCapability = true
        defer { isCheckingImageInputCapability = false }
        do {
            imageInputCapability = try await BridgeService.shared.detectImageInputCapability()
        } catch {
            imageInputCapability = .unknown
        }
    }

    func saveAssistantMessage(_ message: ExplanationMessage) -> String? {
        guard var session = guideSession,
              session.savedNoteIdsByMessageId[message.id] == nil,
              let noteId = guideService.saveAssistantMessage(message, session: session)
        else { return nil }

        session.savedNoteIdsByMessageId[message.id] = noteId
        guideSession = session
        return noteId
    }

    func saveAllAssistantMessages() -> [String] {
        guard let session = guideSession else { return [] }
        var savedIds: [String] = []
        for message in session.completedAssistantMessages
        where session.savedNoteIdsByMessageId[message.id] == nil {
            if let noteId = saveAssistantMessage(message) {
                savedIds.append(noteId)
            }
        }
        return savedIds
    }

    func deleteSavedAssistantMessages() {
        guard var session = guideSession, session.hasSavedMessages else { return }
        guideService.deleteSavedMessages(in: session)
        session.savedNoteIdsByMessageId = [:]
        guideSession = session
    }

    private static func clampedWidth(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }
}
