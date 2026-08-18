import XCTest
@testable import LumenPDF

final class GuideConversationPolicyTests: XCTestCase {
    func testCannotSendWhileWaitingForAssistantReply() {
        var session = sampleSession()
        session.messages = [
            ExplanationMessage(role: .user, content: "那怎么办"),
            ExplanationMessage(role: .assistant, content: "")
        ]
        session.isLoading = true
        XCTAssertFalse(GuideConversationPolicy.canSend(session))

        session.isLoading = false
        XCTAssertFalse(GuideConversationPolicy.canSend(session))
    }

    func testCanSendAfterSuccessfulOrFailedReply() {
        var session = sampleSession()
        session.messages = [
            ExplanationMessage(role: .user, content: "那怎么办"),
            ExplanationMessage(role: .assistant, content: "可以换一种共识算法")
        ]
        XCTAssertTrue(GuideConversationPolicy.canSend(session))

        session.messages = [
            ExplanationMessage(role: .user, content: "那怎么办"),
            ExplanationMessage(role: .assistant, content: "模型没有返回任何可用正文。", isError: true)
        ]
        XCTAssertTrue(GuideConversationPolicy.canSend(session))
    }

    func testEmptySuccessfulReplyIsTreatedAsFailure() {
        XCTAssertTrue(GuideConversationPolicy.isEmptySuccess(""))
        XCTAssertTrue(GuideConversationPolicy.isEmptySuccess("   \n"))
        XCTAssertFalse(GuideConversationPolicy.isEmptySuccess("解释文本"))
        XCTAssertEqual(
            GuideConversationPolicy.emptyReplyMessage(tokens: 0),
            "AI 没有返回任何内容。这次调用的输出 Token 为 0，模型很可能没有真正生成回复。请查看「设置 → 调用日志」中的原始响应。"
        )
    }

    private func sampleSession() -> ExplanationSession {
        ExplanationSession(
            selection: PDFSelectionContext(
                pdfPath: "/tmp/demo.pdf",
                pdfName: "demo.pdf",
                pageIndex: 0,
                selectedText: "selected",
                surroundingText: "context",
                bounds: .zero,
                boundsStr: ""
            )
        )
    }
}
