import XCTest
@testable import LumenPDF

final class TranslationFailurePresentationTests: XCTestCase {
    func testQuotaDumpSurfacesCauseAndFoldsDiagnostics() {
        let message = """
        LLM 接口调用失败：该场景总额度已消耗完，请联系 ideaLAB 平台 [p_api_AK] \
        模型没有返回任何可用正文。 请求地址：https://idealab.alibaba-inc.com/api/openai/v1/chat/completions \
        模型：qwen-flash 收到 155 字节，成功解析 1 个流式帧，忽略 0 个无法识别的帧。 \
        Token 用量为 0，说明接口几乎没有生成输出，模型很可能没有真正开始推理。 \
        网关错误：该场景总额度已消耗完，请联系 ideaLAB 平台 [p_api_AK] \
        原始响应预览：{"error": {"message": "该场景总额度已消耗完，请联系 ideaLAB 平台 [p_api_AK]", "type": "invalid_request_error"}, "type": "error"}
        """

        let card = TranslationFailurePresentation.parse(message, fallbackHeadline: "翻译未完成")

        XCTAssertEqual(card.cause, .quota)
        XCTAssertEqual(card.channel, .llm)
        XCTAssertEqual(card.headline, "额度已用完")
        XCTAssertEqual(card.summary, "该场景总额度已消耗完，请联系 ideaLAB 平台")
        XCTAssertEqual(card.highlightValue("模型"), "qwen-flash")
        XCTAssertEqual(card.highlightValue("业务码"), "p_api_AK")
        XCTAssertEqual(card.highlightValue("类型"), "invalid_request_error")
        XCTAssertEqual(card.diagnosticValue("请求地址"), "https://idealab.alibaba-inc.com/api/openai/v1/chat/completions")
        XCTAssertEqual(card.diagnosticValue("流式解析"), "155 字节 · 1 帧")
        XCTAssertEqual(card.diagnosticValue("Token"), "0（模型未开始推理）")
        XCTAssertTrue(card.hasTechnicalDetails)
        XCTAssertFalse(card.summary.contains("请求地址"))
        XCTAssertFalse(card.summary.contains("原始响应"))
        XCTAssertTrue(card.rawPreview?.contains("\"type\"") == true)
        XCTAssertTrue(card.hint.contains("配额") || card.hint.contains("设置"))
    }

    func testCompactAPIKeyMessageStaysShort() {
        let card = TranslationFailurePresentation.parse(
            "LLM 接口调用失败：API Key 无效或已失效，请在「设置」中更新后重试。",
            fallbackHeadline: "翻译未完成"
        )

        XCTAssertEqual(card.cause, .authentication)
        XCTAssertEqual(card.headline, "认证失败")
        XCTAssertTrue(card.summary.contains("API Key"))
        XCTAssertFalse(card.hasTechnicalDetails)
    }

    func testConfigurationMessageUsesSettingsHint() {
        let card = TranslationFailurePresentation.parse(
            "LLM 未就绪：请先在「设置」中填写 API Base URL、API Key 与模型，保存后再试。",
            fallbackHeadline: "翻译未完成"
        )

        XCTAssertEqual(card.channel, .configuration)
        XCTAssertEqual(card.cause, .configuration)
        XCTAssertEqual(card.headline, "LLM 未就绪")
        XCTAssertTrue(card.summary.contains("设置"))
    }

    func testFallbackErrorKeepsChannel() {
        let card = TranslationFailurePresentation.parse(
            "兜底翻译接口（MyMemory）失败：network error",
            fallbackHeadline: "兜底翻译失败"
        )

        XCTAssertEqual(card.channel, .fallback)
        XCTAssertEqual(card.cause, .network)
        XCTAssertEqual(card.headline, "网络请求失败")
        XCTAssertTrue(card.summary.localizedCaseInsensitiveContains("network error"))
    }

    func testEmptyDiagnosticDumpStillHasReadableSummary() {
        let message = """
        LLM 接口调用失败：模型没有返回任何可用正文。 请求地址：https://example.test/v1/chat/completions \
        模型：qwen3.6-flash 收到 12 字节，成功解析 0 个流式帧，忽略 0 个无法识别的帧。 \
        Token 用量为 0，说明接口几乎没有生成输出，模型很可能没有真正开始推理。 \
        原始响应完全为空：常见于网关返回空 body、流式协议不匹配，或请求在到达模型前被拒绝。
        """
        let card = TranslationFailurePresentation.parse(message, fallbackHeadline: "翻译未完成")

        XCTAssertEqual(card.cause, .emptyOutput)
        XCTAssertEqual(card.headline, "模型没有返回内容")
        XCTAssertFalse(card.summary.isEmpty)
        XCTAssertEqual(card.highlightValue("模型"), "qwen3.6-flash")
        XCTAssertEqual(card.diagnosticValue("请求地址"), "https://example.test/v1/chat/completions")
        XCTAssertTrue(card.hasTechnicalDetails)
    }

    func testWordModeUserHintPrefixIsRecognized() {
        let card = TranslationFailurePresentation.parse(
            "LLM 接口失败：该场景总额度已消耗完，请联系 ideaLAB 平台 [p_api_AK]",
            fallbackHeadline: "LLM 调用失败"
        )

        XCTAssertEqual(card.channel, .llm)
        XCTAssertEqual(card.cause, .quota)
        XCTAssertEqual(card.headline, "额度已用完")
        XCTAssertEqual(card.highlightValue("业务码"), "p_api_AK")
        XCTAssertFalse(card.summary.contains("["))
    }

    func testEmptyMessageUsesFallbackCopy() {
        let card = TranslationFailurePresentation.parse("", fallbackHeadline: "翻译未完成")

        XCTAssertEqual(card.headline, "翻译未完成")
        XCTAssertEqual(card.summary, "请检查网络与 LLM 设置后重试。")
        XCTAssertFalse(card.hasTechnicalDetails)
    }
}

private extension TranslationFailurePresentation {
    func highlightValue(_ label: String) -> String? {
        highlights.first { $0.label == label }?.value
    }

    func diagnosticValue(_ label: String) -> String? {
        diagnostics.first { $0.label == label }?.value
    }
}
