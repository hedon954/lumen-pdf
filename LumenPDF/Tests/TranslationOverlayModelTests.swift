import XCTest
@testable import LumenPDF

@MainActor
final class ReadingPopoverModelTests: XCTestCase {
    func testPresentStartsLoadingAndDisablesRetry() {
        let model = ReadingPopoverModel()

        model.present(sampleRequest())

        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.canRetry)
        XCTAssertNotNil(model.request)
    }

    func testCanRetryAfterFailure() {
        let model = ReadingPopoverModel()
        let request = sampleRequest()
        model.present(request)

        model.fail("网络错误", requestID: request.id)

        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.canRetry)
        XCTAssertEqual(model.request?.translationError, "网络错误")
    }

    func testBeginRetryClearsErrorAndReturnsToLoading() {
        let model = ReadingPopoverModel()
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
        let model = ReadingPopoverModel()
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
        let model = ReadingPopoverModel()
        let request = sampleRequest()
        model.present(request)
        model.fail("网络错误", requestID: request.id)

        model.dismiss()

        XCTAssertNil(model.request)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canRetry)
    }

    func testNoteDraftReplacesTranslationAndRejectsItsLateReply() {
        let model = ReadingPopoverModel()
        let request = sampleRequest()
        model.present(request)
        let draft = UnderlineNoteDraft(
            word: "word", boundsStr: "10,20,80,16", page: 0, pageMarkups: [],
            anchor: .zero, anchorRect: request.selectionAnchorRect,
            appendingNoteId: nil, existingNoteText: ""
        )
        model.presentNoteDraft(draft, onSave: { _ in })
        model.fail("late translation", requestID: request.id)
        XCTAssertNil(model.request)
        XCTAssertFalse(model.isLoading)
        guard case .noteDraft = model.presentation else { return XCTFail("Draft must remain visible") }
        model.dismiss()
        XCTAssertNil(model.presentation)
    }

    func testDismissedReviewCannotReopenFromFinalEditorSave() {
        let model = ReadingPopoverModel()
        let review = ActiveNoteReview(
            id: "review", anchor: NoteAnchorPosition(id: "anchor", noteId: "note", pageIndex: 0,
                                                    point: .zero, anchorRect: .zero), notes: []
        )
        model.presentNoteReview(review, actions: .init(
            openNotes: {}, saveItem: { _, _, _, _, _ in true }, append: { _ in true },
            deleteItem: { _, _ in }, deleteAll: {}
        ))
        model.dismiss()
        model.updateNoteReview(review)
        XCTAssertNil(model.presentation)
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
