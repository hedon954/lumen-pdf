import Foundation
import Security

enum KeychainService {
    private static let service = "com.LumenPDF.app"
    private static let legacyReinstallService = "com.LumenPDF.app.reinstall-stable"
    private static let legacyLLMBaseURLKey = "llm_legacy_api_key_base_url"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        guard upsertProtectedItem(key: key, data: data) == errSecSuccess else { return }
        deleteLegacyItems(key: key)
    }

    static func load(key: String) -> String? {
        if let value = loadItem(
            key: key,
            service: service,
            useDataProtectionKeychain: true
        ) {
            return value
        }

        // Previous builds wrote file-based keychain items with an ACL tied to
        // an ad-hoc binary. Never show an authentication dialog during launch:
        // migrate only when the current stable signature can already read the
        // old item. Otherwise the user can enter the value once in Settings.
        for legacy in legacyItemLocations {
            guard let value = loadItem(
                key: key,
                service: legacy.service,
                useDataProtectionKeychain: legacy.useDataProtectionKeychain
            ) else { continue }
            save(key: key, value: value)
            return value
        }
        return nil
    }

    static func saveLLMAPIKey(_ apiKey: String, for baseURL: String) {
        var vault = loadLLMAPIKeyVault(legacyBaseURL: baseURL)
        vault.setKey(apiKey, for: baseURL)
        guard let encoded = vault.encoded() else { return }
        save(key: "llm_api_key", value: encoded)
    }

    static func loadLLMAPIKey(for baseURL: String) -> String? {
        guard let rawValue = load(key: "llm_api_key") else { return nil }
        let result = LLMAPIKeyVault.decode(
            rawValue,
            legacyBaseURL: legacyLLMBaseURL(fallback: baseURL)
        )
        if result.didMigrate, let encoded = result.vault.encoded() {
            save(key: "llm_api_key", value: encoded)
        }
        return result.vault.key(for: baseURL)
    }

    private static func loadLLMAPIKeyVault(legacyBaseURL: String) -> LLMAPIKeyVault {
        guard let rawValue = load(key: "llm_api_key") else {
            return LLMAPIKeyVault()
        }
        return LLMAPIKeyVault.decode(
            rawValue,
            legacyBaseURL: legacyLLMBaseURL(fallback: legacyBaseURL)
        ).vault
    }

    private static func legacyLLMBaseURL(fallback: String) -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: legacyLLMBaseURLKey), !stored.isEmpty {
            return stored
        }
        let canonical = LLMConfigurationHistory.canonicalBaseURLKey(fallback)
        defaults.set(canonical, forKey: legacyLLMBaseURLKey)
        return canonical
    }

    private static func upsertProtectedItem(key: String, data: Data) -> OSStatus {
        let lookup = itemQuery(
            key: key,
            service: service,
            useDataProtectionKeychain: true
        )
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return updateStatus
        }
        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        var attributes = lookup
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func loadItem(
        key: String,
        service: String,
        useDataProtectionKeychain: Bool
    ) -> String? {
        var query = itemQuery(
            key: key,
            service: service,
            useDataProtectionKeychain: useDataProtectionKeychain
        )
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func itemQuery(
        key: String,
        service: String,
        useDataProtectionKeychain: Bool
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]
    }

    private static let legacyItemLocations: [(service: String, useDataProtectionKeychain: Bool)] = [
        (legacyReinstallService, false),
        (service, false),
    ]

    private static func deleteLegacyItems(key: String) {
        for legacy in legacyItemLocations {
            let query = itemQuery(
                key: key,
                service: legacy.service,
                useDataProtectionKeychain: legacy.useDataProtectionKeychain
            )
            _ = SecItemDelete(query as CFDictionary)
        }
    }
}

struct LLMAPIKeyVault: Codable, Equatable {
    private static let currentVersion = 2

    private var version = currentVersion
    private(set) var keysByBaseURL: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case version
        case keysByBaseURL
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        keysByBaseURL = try container.decode(
            [String: String].self,
            forKey: .keysByBaseURL
        )
    }

    func key(for baseURL: String) -> String? {
        let value = keysByBaseURL[Self.canonicalBaseURL(baseURL)] ?? ""
        return value.isEmpty ? nil : value
    }

    mutating func setKey(_ apiKey: String, for baseURL: String) {
        let canonicalBaseURL = Self.canonicalBaseURL(baseURL)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            keysByBaseURL.removeValue(forKey: canonicalBaseURL)
        } else {
            keysByBaseURL[canonicalBaseURL] = trimmedKey
        }
    }

    func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(
        _ rawValue: String,
        legacyBaseURL: String
    ) -> (vault: LLMAPIKeyVault, didMigrate: Bool) {
        if let data = rawValue.data(using: .utf8),
           let decodedVault = try? JSONDecoder().decode(LLMAPIKeyVault.self, from: data)
        {
            guard decodedVault.version < currentVersion else {
                return (decodedVault, false)
            }

            var upgradedVault = LLMAPIKeyVault()
            if let currentKey = decodedVault.key(for: legacyBaseURL) {
                upgradedVault.setKey(currentKey, for: legacyBaseURL)
            }
            return (upgradedVault, true)
        }

        var vault = LLMAPIKeyVault()
        vault.setKey(rawValue, for: legacyBaseURL)
        return (vault, true)
    }

    private static func canonicalBaseURL(_ baseURL: String) -> String {
        LLMConfigurationHistory.canonicalBaseURLKey(baseURL)
    }
}
