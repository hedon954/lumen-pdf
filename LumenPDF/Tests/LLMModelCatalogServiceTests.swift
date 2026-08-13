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
}
