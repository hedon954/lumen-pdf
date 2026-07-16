import XCTest
@testable import LumenPDF

final class LLMConfigurationHistoryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LLMConfigurationHistoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRememberKeepsMostRecentBaseURLAndModelFirst() {
        let history = LLMConfigurationHistory(defaults: defaults)

        history.remember(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini"
        )
        history.remember(
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-v4-flash"
        )
        history.remember(
            baseURL: "https://api.openai.com/v1/",
            model: "gpt-5-mini"
        )

        XCTAssertEqual(
            history.recentBaseURLs(),
            [
                "https://api.openai.com/v1/",
                "https://api.deepseek.com/v1"
            ]
        )
        XCTAssertEqual(
            history.recentModels(for: "https://api.openai.com/v1"),
            ["gpt-5-mini", "gpt-4o-mini"]
        )
    }

    func testModelsAreScopedByBaseURL() {
        let history = LLMConfigurationHistory(defaults: defaults)

        history.remember(baseURL: "https://example.com/v1", model: "custom-a")
        history.remember(baseURL: "https://other.example/v1", model: "custom-b")

        XCTAssertEqual(
            history.recentModels(for: "https://example.com/v1"),
            ["custom-a"]
        )
        XCTAssertEqual(
            history.recentModels(for: "https://other.example/v1"),
            ["custom-b"]
        )
    }
}
