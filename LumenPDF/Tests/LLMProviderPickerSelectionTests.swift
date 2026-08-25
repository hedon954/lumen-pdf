import XCTest
@testable import LumenPDF

final class LLMProviderPickerSelectionTests: XCTestCase {
    func testMatchingUsesCanonicalURLAndDoesNotSnapToNearestBuiltIn() {
        XCTAssertEqual(
            LLMProviderPreset.matching(baseURL: "https://api.deepseek.com/v1/")?.id,
            "deepseek"
        )
        XCTAssertNil(LLMProviderPreset.matching(baseURL: "https://api.openai.com"))
        XCTAssertNil(LLMProviderPreset.matching(baseURL: "https://api.deepseek.com/v1/proxy"))
        XCTAssertNil(LLMProviderPreset.matching(baseURL: "https://api.deepseek.com.evil.example/v1"))
        XCTAssertNil(LLMProviderPreset.matching(baseURL: "https://llm.example.com/v1"))
    }

    func testUnmatchedBaseURLResolvesToOther() {
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: "https://llm.example.com/v1"),
            .other
        )
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: "https://api.deepseek.com.evil.example/v1"),
            .other
        )
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: "https://api.deepseek.com/v1/proxy"),
            .other
        )
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: ""),
            .other
        )
    }

    func testBuiltInBaseURLResolvesToMatchingProviderNotOther() throws {
        let deepseek = try XCTUnwrap(LLMProviderPickerSelection.builtInPreset(id: "deepseek"))
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: deepseek.baseURL),
            .builtIn(deepseek)
        )
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: "https://api.deepseek.com/v1/"),
            .builtIn(deepseek)
        )
        XCTAssertNotEqual(
            LLMProviderPickerSelection.resolved(baseURL: deepseek.baseURL),
            .other
        )
    }

    func testPreferOtherOverridesBuiltInMatchUntilURLChanges() throws {
        let deepseek = try XCTUnwrap(LLMProviderPickerSelection.builtInPreset(id: "deepseek"))
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: deepseek.baseURL, preferOther: true),
            .other
        )
    }

    func testSelectingOtherDoesNotResetFieldsWhenAlreadyCustom() {
        XCTAssertNil(
            LLMProviderPickerSelection.restoredCustomBaseURL(
                currentBaseURL: "https://llm.example.com/v1",
                lastCustomBaseURL: "https://other.example/v1"
            )
        )
    }

    func testSelectingOtherDoesNotResetFieldsWithoutARememberedCustomURL() throws {
        let deepseek = try XCTUnwrap(LLMProviderPickerSelection.builtInPreset(id: "deepseek"))
        XCTAssertNil(
            LLMProviderPickerSelection.restoredCustomBaseURL(
                currentBaseURL: deepseek.baseURL,
                lastCustomBaseURL: ""
            )
        )
        XCTAssertNil(
            LLMProviderPickerSelection.restoredCustomBaseURL(
                currentBaseURL: deepseek.baseURL,
                lastCustomBaseURL: deepseek.baseURL
            )
        )
    }

    func testSelectingOtherRestoresLastCustomURLInsteadOfClobbering() throws {
        let deepseek = try XCTUnwrap(LLMProviderPickerSelection.builtInPreset(id: "deepseek"))
        XCTAssertEqual(
            LLMProviderPickerSelection.restoredCustomBaseURL(
                currentBaseURL: deepseek.baseURL,
                lastCustomBaseURL: "https://llm.example.com/v1"
            ),
            "https://llm.example.com/v1"
        )
    }

    func testSelectingBuiltInStillAppliesPresetBaseURL() throws {
        let deepseek = try XCTUnwrap(LLMProviderPickerSelection.builtInPreset(id: "deepseek"))
        let openai = try XCTUnwrap(LLMProviderPickerSelection.builtInPreset(id: "openai"))

        XCTAssertEqual(deepseek.baseURL, "https://api.deepseek.com/v1")
        XCTAssertEqual(openai.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(
            LLMProviderPickerSelection.resolved(baseURL: deepseek.baseURL),
            .builtIn(deepseek)
        )
    }
}
