import SwiftUI

@MainActor
final class TranslationOverlayModel: ObservableObject {
    @Published private(set) var request: TranslationBubbleRequest?
    @Published private(set) var isLoading = false

    func present(_ request: TranslationBubbleRequest) {
        self.request = request
        isLoading = true
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
        request = nil
        isLoading = false
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
