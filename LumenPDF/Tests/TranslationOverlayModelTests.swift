import XCTest
@testable import LumenPDF

@MainActor
final class TranslationOverlayModelTests: XCTestCase {
    func testPresentStartsLoadingAndDisablesRetry() {
        let model = TranslationOverlayModel()

        model.present(sampleRequest())

        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.canRetry)
        XCTAssertNotNil(model.request)
    }

    func testCanRetryAfterFailure() {
        let model = TranslationOverlayModel()
        let request = sampleRequest()
        model.present(request)

        model.fail("网络错误", requestID: request.id)

        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.canRetry)
        XCTAssertEqual(model.request?.translationError, "网络错误")
    }

    func testBeginRetryClearsErrorAndReturnsToLoading() {
        let model = TranslationOverlayModel()
        let request = sampleRequest()
        model.present(request)
        model.fail("网络错误", requestID: request.id)

        model.beginRetry()

        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.canRetry)
        XCTAssertNil(model.request?.result)
        XCTAssertNil(model.request?.translationError)
        XCTAssertEqual(model.request?.id, request.id)
    }

    func testRetryInvokesHandlerAfterClearingCurrentResult() {
        let model = TranslationOverlayModel()
        let request = sampleRequest()
        var retriedIDs: [UUID] = []
        model.bindRetryHandler { request in
            retriedIDs.append(request.id)
        }
        model.present(request)
        model.fail("网络错误", requestID: request.id)

        model.retry()

        XCTAssertEqual(retriedIDs, [request.id])
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.request?.translationError)
    }

    func testDismissCancelsRetry() {
        let model = TranslationOverlayModel()
        let request = sampleRequest()
        model.present(request)
        model.fail("网络错误", requestID: request.id)

        model.dismiss()

        XCTAssertNil(model.request)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canRetry)
    }

    private func sampleRequest() -> TranslationBubbleRequest {
        TranslationBubbleRequest(
            pdfPath: "/tmp/book.pdf",
            pdfName: "book.pdf",
            word: "manipulation",
            sentence: "DataFrame manipulation typically occurred locally.",
            sentenceHash: "hash",
            bounds: CGRect(x: 10, y: 20, width: 80, height: 16),
            boundsStr: "10,20,80,16",
            page: 12,
            selectionAnchorRect: CGRect(x: 40, y: 80, width: 80, height: 16)
        )
    }
}
