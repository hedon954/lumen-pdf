import Foundation

final class LLMConfigurationHistory {
    static let shared = LLMConfigurationHistory()

    private enum StorageKey {
        static let baseURLs = "llm_recent_base_urls"
        static let modelsByBaseURL = "llm_recent_models_by_base_url"
    }

    private let defaults: UserDefaults
    private let maximumBaseURLs: Int
    private let maximumModelsPerBaseURL: Int

    init(
        defaults: UserDefaults = .standard,
        maximumBaseURLs: Int = 12,
        maximumModelsPerBaseURL: Int = 30
    ) {
        self.defaults = defaults
        self.maximumBaseURLs = maximumBaseURLs
        self.maximumModelsPerBaseURL = maximumModelsPerBaseURL
    }

    func remember(baseURL: String, model: String) {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else { return }

        var baseURLs = recentBaseURLs()
        baseURLs.removeAll {
            Self.canonicalBaseURLKey($0) == Self.canonicalBaseURLKey(trimmedBaseURL)
        }
        baseURLs.insert(trimmedBaseURL, at: 0)
        defaults.set(Array(baseURLs.prefix(maximumBaseURLs)), forKey: StorageKey.baseURLs)

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return }

        let baseURLKey = Self.canonicalBaseURLKey(trimmedBaseURL)
        var modelsByBaseURL = loadModelsByBaseURL()
        var models = modelsByBaseURL[baseURLKey] ?? []
        models.removeAll { $0 == trimmedModel }
        models.insert(trimmedModel, at: 0)
        modelsByBaseURL[baseURLKey] = Array(models.prefix(maximumModelsPerBaseURL))
        saveModelsByBaseURL(modelsByBaseURL)
    }

    func recentBaseURLs() -> [String] {
        defaults.stringArray(forKey: StorageKey.baseURLs) ?? []
    }

    func recentModels(for baseURL: String) -> [String] {
        loadModelsByBaseURL()[Self.canonicalBaseURLKey(baseURL)] ?? []
    }

    static func canonicalBaseURLKey(_ baseURL: String) -> String {
        baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private func loadModelsByBaseURL() -> [String: [String]] {
        guard let data = defaults.data(forKey: StorageKey.modelsByBaseURL),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }
        return value
    }

    private func saveModelsByBaseURL(_ value: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: StorageKey.modelsByBaseURL)
    }
}
