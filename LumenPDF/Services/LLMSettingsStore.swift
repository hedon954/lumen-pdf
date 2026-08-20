import Foundation

enum LLMEndpointIdentity {
    static func key(_ baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return LLMConfigurationHistory.canonicalBaseURLKey(
            BridgeService.normalizedLLMBaseURL(trimmed)
        )
    }

    static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        let left = key(lhs)
        let right = key(rhs)
        return !left.isEmpty && left == right
    }

    static func lookupKeys(_ baseURL: String) -> [String] {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var keys: [String] = []

        func add(_ value: String) {
            let canonical = LLMConfigurationHistory.canonicalBaseURLKey(value)
            guard !canonical.isEmpty, !keys.contains(canonical) else { return }
            keys.append(canonical)
        }

        if !trimmed.isEmpty {
            add(BridgeService.normalizedLLMBaseURL(trimmed))
            add(trimmed)
            let identity = key(trimmed)
            if identity.hasSuffix("/v1") {
                add(String(identity.dropLast(3)))
            }
        }
        return keys
    }
}

struct LLMSettingsStore {
    static let baseURLKey = "llm_base_url"
    static let modelKey = "llm_model"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @discardableResult
    func persist(baseURL: String, model: String) -> (baseURL: String, model: String) {
        let snapshot = Self.snapshot(baseURL: baseURL, model: model)
        defaults.set(snapshot.baseURL, forKey: Self.baseURLKey)
        defaults.set(snapshot.model, forKey: Self.modelKey)
        return snapshot
    }

    static func snapshot(baseURL: String, model: String) -> (baseURL: String, model: String) {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = trimmedBaseURL.isEmpty
            ? ""
            : BridgeService.normalizedLLMBaseURL(trimmedBaseURL)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalizedBaseURL, trimmedModel)
    }

    func loadBaseURL() -> String {
        let stored = defaults.string(forKey: Self.baseURLKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : BridgeService.normalizedLLMBaseURL(trimmed)
    }

    func loadModel() -> String {
        defaults.string(forKey: Self.modelKey) ?? ""
    }
}
