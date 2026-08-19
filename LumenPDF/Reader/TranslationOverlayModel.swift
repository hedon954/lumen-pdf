import SwiftUI

@MainActor
final class TranslationOverlayModel: ObservableObject {
    @Published private(set) var request: TranslationBubbleRequest?
    @Published private(set) var isLoading = false

    private var inFlight: Task<Void, Never>?
    private var retryHandler: (@MainActor (TranslationBubbleRequest) -> Void)?

    var canRetry: Bool {
        guard !isLoading, let request else { return false }
        return request.result != nil || request.translationError != nil
    }

    func present(_ request: TranslationBubbleRequest) {
        cancelInFlight()
        self.request = request
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
        self.request = request
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
        request = nil
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
        self.request = request
        return true
    }
}
