import XCTest
@testable import LumenPDF

final class PromptTemplateValidatorTests: XCTestCase {
    func testWordPromptRequiresEverySupportedRuntimeVariable() {
        let result = PromptTemplateValidator.validateUserPrompt(
            "Translate {word} to {lang}",
            kind: .word
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("{sentence}") })
    }

    func testUnknownVariableIsRejectedWithoutTreatingJSONBracesAsVariables() {
        let template = #"{"word":"{word}","language":"{language}","sentence":"{sentence}","target":"{lang}"}"#
        let result = PromptTemplateValidator.validateUserPrompt(template, kind: .word)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("{language}") })
    }

    func testValidExplanationPromptPasses() {
        let result = PromptTemplateValidator.validateUserPrompt(
            "Explain {selection} with {context} for {lang}; focus: {focus}",
            kind: .explanation
        )

        XCTAssertTrue(result.isValid)
    }

    func testValidatePairCombinesUserAndSystemErrors() {
        let result = PromptTemplateValidator.validatePair(
            userPrompt: "Translate {word} to {lang}",
            systemPrompt: "",
            kind: .word
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("{sentence}") })
        XCTAssertTrue(result.errors.contains { $0.contains("System Prompt 不能为空") })
        XCTAssertEqual(result.variables, ["word", "lang"])
    }
}
