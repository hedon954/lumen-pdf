import XCTest
@testable import LumenPDF

final class LLMThinkingExtraConfigTests: XCTestCase {
    func testDashScopeAndIdeaLabUseEnableThinking() {
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                LLMThinkingExtraConfig.defaultJSON(
                    baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-plus"
                ),
                #"{"enable_thinking":false}"#
            )
        )
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                LLMThinkingExtraConfig.defaultJSON(
                    baseURL: "https://idealab.alibaba-inc.com/api/openai/v1",
                    model: "qwen3.7-flash"
                ),
                #"{"enable_thinking":false}"#
            )
        )
    }

    func testSelfHostedQwenUsesChatTemplateKwargs() {
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                LLMThinkingExtraConfig.defaultJSON(
                    baseURL: "http://127.0.0.1:8000/v1",
                    model: "Qwen/Qwen3-8B"
                ),
                #"{"chat_template_kwargs":{"enable_thinking":false}}"#
            )
        )
    }

    func testDeepSeekAndOpenRouterDefaults() {
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                LLMThinkingExtraConfig.defaultJSON(
                    baseURL: "https://api.deepseek.com/v1",
                    model: "deepseek-v4-flash"
                ),
                #"{"thinking":{"type":"disabled"}}"#
            )
        )
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                LLMThinkingExtraConfig.defaultJSON(
                    baseURL: "https://openrouter.ai/api/v1",
                    model: "qwen/qwen3-32b"
                ),
                #"{"reasoning":{"enabled":false}}"#
            )
        )
    }

    func testOpenAIDefaultIsEmpty() {
        XCTAssertEqual(
            LLMThinkingExtraConfig.defaultJSON(baseURL: "https://api.openai.com/v1", model: "gpt-4o"),
            ""
        )
    }
}

final class JSONSyntaxHighlighterTests: XCTestCase {
    func testHighlightsKeysStringsNumbersAndKeywords() {
        let source = #"{"enable_thinking": false, "n": 1, "name": "qwen"}"#
        let tokens = JSONSyntaxHighlighter.tokens(in: source)
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.key))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.punctuation))
    }

    func testUnclosedStringIsStillHighlighted() {
        let tokens = JSONSyntaxHighlighter.tokens(in: #"{"foo": "bar"#)
        XCTAssertEqual(tokens.last?.kind, .string)
    }
}
