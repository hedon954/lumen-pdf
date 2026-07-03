import Foundation

final class SettingsRuntimeService {
    static let shared = SettingsRuntimeService()

    private let bridge: BridgeService

    init(bridge: BridgeService = .shared) {
        self.bridge = bridge
    }

    func normalizedLLMBaseURL(_ rawValue: String) -> String {
        BridgeService.normalizedLLMBaseURL(rawValue)
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
        explanationSystemPrompt: String
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
            explanationSystemPrompt: explanationSystemPrompt
        )
    }
}
