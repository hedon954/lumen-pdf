import Foundation

@MainActor
final class ReadingInspectorModel: ObservableObject {
    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: Self.visibleKey) }
    }
    @Published var width: Double {
        didSet { UserDefaults.standard.set(Self.clampedWidth(width), forKey: Self.widthKey) }
    }
    @Published var mode: ReadingInspectorMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    @Published var selection: PDFSelectionContext?
    @Published var guideSession: ExplanationSession?

    private let guideService = ReadingGuideService()

    static let minimumWidth: Double = 300
    static let defaultWidth: Double = 360
    static let maximumWidth: Double = 460

    private static let visibleKey = "show_reading_inspector"
    private static let widthKey = "reading_inspector_width"
    private static let modeKey = "reading_inspector_mode"

    init() {
        if UserDefaults.standard.object(forKey: Self.visibleKey) == nil {
            isVisible = true
        } else {
            isVisible = UserDefaults.standard.bool(forKey: Self.visibleKey)
        }

        let storedWidth = UserDefaults.standard.double(forKey: Self.widthKey)
        width = Self.clampedWidth(storedWidth == 0 ? Self.defaultWidth : storedWidth)

        if let rawMode = UserDefaults.standard.string(forKey: Self.modeKey),
           let storedMode = ReadingInspectorMode(rawValue: rawMode) {
            mode = storedMode
        } else {
            mode = .context
        }
    }

    func setWidth(_ width: CGFloat) {
        self.width = Self.clampedWidth(Double(width))
    }

    func startGuide(selection: PDFSelectionContext) {
        self.selection = selection
        guideSession = ExplanationSession(selection: selection)
        mode = .guide
        isVisible = true
    }

    func clearForDocumentChange(pdfPath: String?) {
        guard selection?.pdfPath != pdfPath else { return }
        selection = nil
        guideSession = nil
    }

    func submitGuideQuestion(_ question: String) {
        guard let session = guideSession, !session.isLoading else { return }
        guideService.submitQuestion(question, session: session) { [weak self] updated in
            guard self?.guideSession?.id == updated.id else { return }
            self?.guideSession = updated
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
