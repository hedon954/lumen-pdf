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
    static let extraConfigByBaseURLKey = "llm_extra_config_by_base_url"

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

    func persistExtraConfig(_ extraConfig: String, for baseURL: String) {
        let key = LLMEndpointIdentity.key(baseURL)
        var map = extraConfigMap()
        let trimmed = extraConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || trimmed.isEmpty {
            if !key.isEmpty {
                map.removeValue(forKey: key)
            }
        } else {
            map[key] = trimmed
        }
        defaults.set(map, forKey: Self.extraConfigByBaseURLKey)
    }

    func loadExtraConfig(for baseURL: String) -> String {
        let map = extraConfigMap()
        for key in LLMEndpointIdentity.lookupKeys(baseURL) {
            if let value = map[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        }
        return ""
    }

    private func extraConfigMap() -> [String: String] {
        defaults.dictionary(forKey: Self.extraConfigByBaseURLKey) as? [String: String] ?? [:]
    }
}

enum LLMExtraConfig {
    static let reservedKeys: Set<String> = ["messages", "stream", "stream_options"]

    static func validatedJSON(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw LLMExtraConfigError.invalidJSON
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMExtraConfigError.invalidJSON
        }
        guard let dictionary = object as? [String: Any] else {
            throw LLMExtraConfigError.notObject
        }
        let reserved = dictionary.keys.filter { reservedKeys.contains($0) }.sorted()
        if !reserved.isEmpty {
            throw LLMExtraConfigError.reservedKeys(reserved)
        }
        return trimmed
    }
}

enum LLMExtraConfigError: LocalizedError, Equatable {
    case invalidJSON
    case notObject
    case reservedKeys([String])

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Extra Config 不是合法 JSON。"
        case .notObject:
            return "Extra Config 必须是 JSON 对象，例如 {\"enable_thinking\": false}。"
        case let .reservedKeys(keys):
            return "Extra Config 不能包含 \(keys.joined(separator: "、"))。"
        }
    }
}
