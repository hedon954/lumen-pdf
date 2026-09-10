import SwiftUI

@MainActor
final class ReadingPopoverModel: ObservableObject {
    enum Presentation {
        case translation(TranslationBubbleRequest)
        case noteDraft(UnderlineNoteDraft, (String) -> Void)
        case noteReview(ActiveNoteReview, NoteReviewActions)

        var anchorRect: CGRect {
            switch self {
            case let .translation(request): return request.selectionAnchorRect
            case let .noteDraft(draft, _): return draft.anchorRect
            case let .noteReview(review, _): return review.anchor.anchorRect
            }
        }
    }

    struct NoteReviewActions {
        let openNotes: () -> Void
        let saveItem: (String, Int, String, String, Int) -> Bool
        let append: (String) -> Bool
        let deleteItem: (String, Int) -> Void
        let deleteAll: () -> Void
    }

    @Published private(set) var presentation: Presentation?
    @Published private(set) var generation = UUID()
    @Published private(set) var isLoading = false

    var request: TranslationBubbleRequest? {
        guard case let .translation(request) = presentation else { return nil }
        return request
    }

    var noteReview: ActiveNoteReview? {
        guard case let .noteReview(review, _) = presentation else { return nil }
        return review
    }

    func presentNoteDraft(_ draft: UnderlineNoteDraft, onSave: @escaping (String) -> Void) {
        dismiss()
        generation = UUID()
        presentation = .noteDraft(draft, onSave)
    }

    func presentNoteReview(_ review: ActiveNoteReview, actions: NoteReviewActions) {
        dismiss()
        generation = UUID()
        presentation = .noteReview(review, actions)
    }

    func updateNoteReview(_ review: ActiveNoteReview) {
        guard case let .noteReview(current, actions) = presentation, current.id == review.id else { return }
        presentation = .noteReview(review, actions)
    }

    private var inFlight: Task<Void, Never>?
    private var retryHandler: (@MainActor (TranslationBubbleRequest) -> Void)?

    var canRetry: Bool {
        guard !isLoading, let request else { return false }
        return request.result != nil || request.translationError != nil
    }

    func present(_ request: TranslationBubbleRequest) {
        cancelInFlight()
        generation = UUID()
        presentation = .translation(request)
        isLoading = true
    }

    func bindRetryHandler(_ handler: @escaping @MainActor (TranslationBubbleRequest) -> Void) {
        retryHandler = handler
    }

    func retry() {
        guard canRetry, let request else { return }
        beginRetry()
        retryHandler?(request)
    }

    func beginRetry() {
        cancelInFlight()
        guard var request else { return }
        request.result = nil
        request.translationError = nil
        presentation = .translation(request)
        isLoading = true
    }

    func track(_ task: Task<Void, Never>) {
        inFlight = task
    }

    func applyPartial(_ result: TranslationResult, requestID: UUID) {
        updateRequest(id: requestID) { request in
            request.result = result
            request.translationError = nil
        }
    }

    func complete(_ result: TranslationResult, requestID: UUID) {
        guard updateRequest(id: requestID, mutation: { request in
            request.result = result
            request.translationError = nil
        }) else { return }
        isLoading = false
    }

    func fail(_ message: String, requestID: UUID) {
        guard updateRequest(id: requestID, mutation: { request in
            request.translationError = message
        }) else { return }
        isLoading = false
    }

    func dismiss() {
        cancelInFlight()
        retryHandler = nil
        presentation = nil
        isLoading = false
    }

    private func cancelInFlight() {
        inFlight?.cancel()
        inFlight = nil
    }

    @discardableResult
    private func updateRequest(
        id: UUID,
        mutation: (inout TranslationBubbleRequest) -> Void
    ) -> Bool {
        guard var request, request.id == id else { return false }
        mutation(&request)
        presentation = .translation(request)
        return true
    }
}
