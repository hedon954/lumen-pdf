import Foundation

final class SettingsRuntimeService {
    static let shared = SettingsRuntimeService()

    private let bridge: BridgeService
    private let settingsStore: LLMSettingsStore

    init(
        bridge: BridgeService = .shared,
        settingsStore: LLMSettingsStore = LLMSettingsStore()
    ) {
        self.bridge = bridge
        self.settingsStore = settingsStore
    }

    func normalizedLLMBaseURL(_ rawValue: String) -> String {
        BridgeService.normalizedLLMBaseURL(rawValue)
    }

    func persistAndUpdateConfig(
        baseURL: String,
        apiKey: String,
        model: String,
        targetLanguage: String,
        wordPromptTemplate: String,
        sentencePromptTemplate: String,
        explanationPromptTemplate: String,
        wordSystemPrompt: String,
        sentenceSystemPrompt: String,
        explanationSystemPrompt: String,
        extraConfig: String
    ) throws -> (baseURL: String, model: String) {
        let snapshot = LLMSettingsStore.snapshot(baseURL: baseURL, model: model)
        let validatedExtra = try LLMExtraConfig.validatedJSON(extraConfig)
        if !snapshot.baseURL.isEmpty {
            try KeychainService.saveLLMAPIKey(apiKey, for: snapshot.baseURL)
            settingsStore.persistExtraConfig(validatedExtra, for: snapshot.baseURL)
        }
        let persisted = settingsStore.persist(baseURL: snapshot.baseURL, model: snapshot.model)
        try updateConfig(
            baseURL: persisted.baseURL,
            apiKey: apiKey,
            model: persisted.model,
            targetLanguage: targetLanguage,
            wordPromptTemplate: wordPromptTemplate,
            sentencePromptTemplate: sentencePromptTemplate,
            explanationPromptTemplate: explanationPromptTemplate,
            wordSystemPrompt: wordSystemPrompt,
            sentenceSystemPrompt: sentenceSystemPrompt,
            explanationSystemPrompt: explanationSystemPrompt,
            extraConfig: validatedExtra
        )
        return persisted
    }

    func updateConfig(
        baseURL: String,
        apiKey: String,
        model: String,
        targetLanguage: String,
        wordPromptTemplate: String,
        sentencePromptTemplate: String,
        explanationPromptTemplate: String,
        wordSystemPrompt: String,
        sentenceSystemPrompt: String,
        explanationSystemPrompt: String,
        extraConfig: String
    ) throws {
        try bridge.updateConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            targetLanguage: targetLanguage,
            wordPromptTemplate: wordPromptTemplate,
            sentencePromptTemplate: sentencePromptTemplate,
            explanationPromptTemplate: explanationPromptTemplate,
            wordSystemPrompt: wordSystemPrompt,
            sentenceSystemPrompt: sentenceSystemPrompt,
            explanationSystemPrompt: explanationSystemPrompt,
            extraConfig: extraConfig
        )
    }
}
