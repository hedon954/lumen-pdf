import XCTest
@testable import LumenPDF

final class LLMSettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPersistWritesNormalizedBaseURLAndTrimmedModel() {
        let store = LLMSettingsStore(defaults: defaults)

        let persisted = store.persist(
            baseURL: " https://api.openai.com ",
            model: "  gpt-4.1-mini  "
        )

        XCTAssertEqual(persisted.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(persisted.model, "gpt-4.1-mini")
        XCTAssertEqual(
            defaults.string(forKey: LLMSettingsStore.baseURLKey),
            "https://api.openai.com/v1"
        )
        XCTAssertEqual(
            defaults.string(forKey: LLMSettingsStore.modelKey),
            "gpt-4.1-mini"
        )
    }

    func testLoadReturnsPersistedValuesAfterReread() {
        let writer = LLMSettingsStore(defaults: defaults)
        writer.persist(
            baseURL: "https://api.deepseek.com/v1/",
            model: "deepseek-v4-flash"
        )

        let reader = LLMSettingsStore(defaults: defaults)
        XCTAssertEqual(reader.loadBaseURL(), "https://api.deepseek.com/v1")
        XCTAssertEqual(reader.loadModel(), "deepseek-v4-flash")
    }

    func testEmptyBaseURLIsNotReplacedWithOpenAIDefault() {
        let store = LLMSettingsStore(defaults: defaults)
        let persisted = store.persist(baseURL: "  ", model: "gpt-4o-mini")

        XCTAssertEqual(persisted.baseURL, "")
        XCTAssertEqual(store.loadBaseURL(), "")
        XCTAssertEqual(store.loadModel(), "gpt-4o-mini")
    }

    func testExtraConfigIsIsolatedByBaseURLAndSurvivesOpenAIAlias() {
        let store = LLMSettingsStore(defaults: defaults)
        store.persistExtraConfig(
            #"{"thinking_budget":0}"#,
            for: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        )
        store.persistExtraConfig(#"{"foo":1}"#, for: "https://api.openai.com/v1")

        XCTAssertEqual(
            store.loadExtraConfig(for: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
            #"{"thinking_budget":0}"#
        )
        XCTAssertEqual(
            store.loadExtraConfig(for: "https://api.openai.com"),
            #"{"foo":1}"#
        )
        XCTAssertEqual(store.loadExtraConfig(for: "https://api.deepseek.com/v1"), "")
    }

    func testEffectiveExtraConfigUsesProviderDefaultWhenUnmodified() {
        let store = LLMSettingsStore(defaults: defaults)
        let extra = store.effectiveExtraConfig(
            for: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-plus"
        )
        XCTAssertTrue(LLMExtraConfig.jsonEquals(extra, #"{"enable_thinking":false}"#))
        XCTAssertTrue(extra.contains("\n"))
    }

    func testEffectiveExtraConfigPrefersStoredUserValue() {
        let store = LLMSettingsStore(defaults: defaults)
        store.persistExtraConfig(#"{"enable_thinking":true}"#, for: "https://dashscope.aliyuncs.com/compatible-mode/v1")
        let extra = store.effectiveExtraConfig(
            for: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-plus"
        )
        XCTAssertTrue(LLMExtraConfig.jsonEquals(extra, #"{"enable_thinking":true}"#))
    }

    func testEmptyObjectIsAUserOverrideNotTheDefault() {
        let store = LLMSettingsStore(defaults: defaults)
        store.persistExtraConfig("{}", for: "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                store.effectiveExtraConfig(
                    for: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-plus"
                ),
                "{}"
            )
        )
    }
}

final class LLMExtraConfigTests: XCTestCase {
    func testEmptyAndObjectAreAccepted() throws {
        XCTAssertEqual(try LLMExtraConfig.validatedJSON("  "), "")
        let pretty = try LLMExtraConfig.validatedJSON(#"{"enable_thinking": false}"#)
        XCTAssertTrue(LLMExtraConfig.jsonEquals(pretty, #"{"enable_thinking":false}"#))
        XCTAssertTrue(pretty.contains("\n"))
    }

    func testPrettyPrintedAndJsonEquals() {
        XCTAssertEqual(LLMExtraConfig.prettyPrinted("  "), "")
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                #"{"b":1,"a":2}"#,
                LLMExtraConfig.prettyPrinted(#"{"a":2,"b":1}"#)
            )
        )
        XCTAssertEqual(LLMExtraConfig.prettyPrinted("{"), "{")
    }

    func testRejectsInvalidJSONArrayAndReservedKeys() {
        XCTAssertThrowsError(try LLMExtraConfig.validatedJSON("{"))
        XCTAssertThrowsError(try LLMExtraConfig.validatedJSON("[1, 2]"))
        XCTAssertThrowsError(try LLMExtraConfig.validatedJSON(#"{"messages": []}"#))
        XCTAssertThrowsError(try LLMExtraConfig.validatedJSON(#"{"stream": true}"#))
    }

    func testLiveJSONUsesProviderDefaultWhenEmpty() throws {
        XCTAssertTrue(
            LLMExtraConfig.jsonEquals(
                try LLMExtraConfig.liveJSON(
                    "  ",
                    baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-plus"
                ),
                #"{"enable_thinking":false}"#
            )
        )
        XCTAssertEqual(
            try LLMExtraConfig.liveJSON("{}", baseURL: "https://api.openai.com/v1", model: "gpt-4o"),
            LLMExtraConfig.prettyPrinted("{}")
        )
        XCTAssertThrowsError(
            try LLMExtraConfig.liveJSON(#"{"messages":[]}"#, baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        )
    }
}

final class LLMEndpointIdentityTests: XCTestCase {
    func testOpenAIURLsWithAndWithoutV1AreTheSameEndpoint() {
        XCTAssertTrue(
            LLMEndpointIdentity.isSame(
                "https://api.openai.com",
                "https://api.openai.com/v1/"
            )
        )
        XCTAssertEqual(
            LLMEndpointIdentity.key("https://API.OpenAI.com"),
            "https://api.openai.com/v1"
        )
    }

    func testLookupKeysIncludeLegacyUnnormalizedAlias() {
        let keys = LLMEndpointIdentity.lookupKeys("https://api.openai.com/v1")
        XCTAssertEqual(keys.first, "https://api.openai.com/v1")
        XCTAssertTrue(keys.contains("https://api.openai.com"))
    }

    func testDifferentProvidersAreNotTheSameEndpoint() {
        XCTAssertFalse(
            LLMEndpointIdentity.isSame(
                "https://api.openai.com/v1",
                "https://api.deepseek.com/v1"
            )
        )
    }
}
