import XCTest
@testable import LumenPDF

final class LLMModelCatalogServiceTests: XCTestCase {
    private let service = LLMModelCatalogService()

    func testModelListURLAppendsModelsToCompatibleBaseURL() throws {
        let url = try service.modelListURL(
            for: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/models"
        )
    }

    func testDecodeModelIDsSupportsOpenAIEnvelopeAndDeduplicates() throws {
        let data = Data(
            """
            {
              "object": "list",
              "data": [
                {"id": "qwen3.7-max", "object": "model"},
                {"id": "qwen3.7-max", "object": "model"},
                {"id": "qwen3.7-plus", "object": "model"}
              ]
            }
            """.utf8
        )

        XCTAssertEqual(
            try service.decodeModelIDs(from: data),
            ["qwen3.7-max", "qwen3.7-plus"]
        )
    }

    func testDecodeModelIDsSupportsStringModelList() throws {
        let data = Data(
            """
            {
              "models": ["custom-model-b", "custom-model-a"]
            }
            """.utf8
        )

        XCTAssertEqual(
            try service.decodeModelIDs(from: data),
            ["custom-model-a", "custom-model-b"]
        )
    }

    func testOpenCodePresetUsesOfficialZenEndpointAndFiltersUnsupportedProtocols() throws {
        let preset = try XCTUnwrap(
            LLMProviderPreset.builtIn.first { $0.id == "opencode-zen" }
        )

        XCTAssertEqual(preset.baseURL, "https://opencode.ai/zen/v1")
        XCTAssertTrue(preset.supports(modelID: "deepseek-v4-flash"))
        XCTAssertTrue(preset.supports(modelID: "kimi-k3"))
        XCTAssertFalse(preset.supports(modelID: "gpt-5.6-terra"))
        XCTAssertFalse(preset.supports(modelID: "claude-sonnet-5"))
        XCTAssertFalse(preset.supports(modelID: "gemini-3.6-flash"))
        XCTAssertFalse(preset.supports(modelID: "qwen3.6-plus"))

        XCTAssertEqual(
            try service.modelListURL(for: preset.baseURL).absoluteString,
            "https://opencode.ai/zen/v1/models"
        )
    }

    func testEveryBuiltInProviderHasOfficialAPIKeyLink() {
        let expectedLinks = [
            "openai": "https://platform.openai.com/api-keys",
            "aliyun-cn": "https://bailian.console.aliyun.com/?tab=model#/api-key",
            "aliyun-intl": "https://modelstudio.console.alibabacloud.com/?tab=model#/api-key",
            "deepseek": "https://platform.deepseek.com/api_keys",
            "openrouter": "https://openrouter.ai/settings/keys",
            "opencode-zen": "https://opencode.ai/zen",
            "gemini": "https://aistudio.google.com/app/apikey",
            "siliconflow": "https://cloud.siliconflow.cn/account/ak",
            "zhipu": "https://bigmodel.cn/usercenter/proj-mgmt/apikeys",
            "minimax-cn": "https://platform.minimaxi.com/console/access?tab=api-keys",
            "volcengine": "https://console.volcengine.com/ark/region:ark+cn-beijing/apikey"
        ]

        XCTAssertEqual(LLMProviderPreset.builtIn.count, expectedLinks.count)
        for provider in LLMProviderPreset.builtIn {
            XCTAssertEqual(provider.apiKeyURL.scheme, "https", provider.id)
            XCTAssertEqual(
                provider.apiKeyURL.absoluteString,
                expectedLinks[provider.id],
                provider.id
            )
        }
    }
}
