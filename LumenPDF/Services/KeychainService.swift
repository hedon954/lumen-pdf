import Foundation
import Security

enum KeychainServiceError: LocalizedError, Equatable {
    case encodingFailed
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "无法保存 API Key，请重新输入后再试。"
        case let .saveFailed(status):
            return KeychainSaveFailureMessage.userFacing(status)
        }
    }
}

enum KeychainSaveFailureMessage {
    static func userFacing(_ status: OSStatus) -> String {
        switch status {
        case errSecMissingEntitlement:
            return "无法保存 API Key。当前安装无法写入钥匙串。"
        case errSecNotAvailable, errSecInteractionNotAllowed:
            return "无法保存 API Key。请先解锁 Mac 后再保存。"
        case errSecAuthFailed:
            return "无法保存 API Key。钥匙串验证失败，请解锁后再试。"
        default:
            return "无法保存 API Key，请稍后重试。"
        }
    }
}

enum KeychainWriteFallback {
    /// Data-protection Keychain needs a restricted entitlement. Ad-hoc and
    /// non-sandboxed release builds do not have it, so -34018 is expected
    /// until we retry the same item on the file-based keychain.
    static func shouldUseFileBasedKeychain(after status: OSStatus) -> Bool {
        status == errSecMissingEntitlement
    }
}

enum KeychainService {
    private static let service = "com.LumenPDF.app"
    private static let legacyReinstallService = "com.LumenPDF.app.reinstall-stable"
    private static let legacyLLMBaseURLKey = "llm_legacy_api_key_base_url"

    static func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        let result = upsertProtectedItem(key: key, data: data)
        guard result.status == errSecSuccess else {
            throw KeychainServiceError.saveFailed(result.status)
        }
        deleteLegacyItems(
            key: key,
            preservingFileBasedServiceItem: result.usedFileBasedKeychain
        )
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
            try? save(key: key, value: value)
            return value
        }
        return nil
    }

    static func saveLLMAPIKey(_ apiKey: String, for baseURL: String) throws {
        var vault = loadLLMAPIKeyVault(legacyBaseURL: baseURL)
        vault.setKey(apiKey, for: baseURL)
        guard let encoded = vault.encoded() else {
            throw KeychainServiceError.encodingFailed
        }
        try save(key: "llm_api_key", value: encoded)
    }

    static func loadLLMAPIKey(for baseURL: String) -> String? {
        guard let rawValue = load(key: "llm_api_key") else { return nil }
        let result = LLMAPIKeyVault.decode(
            rawValue,
            legacyBaseURL: legacyLLMBaseURL(fallback: baseURL)
        )
        if result.didMigrate, let encoded = result.vault.encoded() {
            try? save(key: "llm_api_key", value: encoded)
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
        let canonical = LLMEndpointIdentity.key(fallback)
        let stored = canonical.isEmpty
            ? LLMConfigurationHistory.canonicalBaseURLKey(fallback)
            : canonical
        defaults.set(stored, forKey: legacyLLMBaseURLKey)
        return stored
    }

    private static func upsertProtectedItem(
        key: String,
        data: Data
    ) -> (status: OSStatus, usedFileBasedKeychain: Bool) {
        let dataProtectionStatus = upsertItem(
            key: key,
            data: data,
            useDataProtectionKeychain: true
        )
        if dataProtectionStatus == errSecSuccess
            || !KeychainWriteFallback.shouldUseFileBasedKeychain(after: dataProtectionStatus)
        {
            return (dataProtectionStatus, false)
        }
        return (
            upsertItem(
                key: key,
                data: data,
                useDataProtectionKeychain: false
            ),
            true
        )
    }

    private static func upsertItem(
        key: String,
        data: Data,
        useDataProtectionKeychain: Bool
    ) -> OSStatus {
        let lookup = KeychainItemQuery.searchQuery(
            key: key,
            service: service,
            useDataProtectionKeychain: useDataProtectionKeychain
        )
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return updateStatus
        }
        if updateStatus != errSecItemNotFound, updateStatus != errSecDuplicateItem {
            return updateStatus
        }

        let addStatus = SecItemAdd(
            KeychainItemQuery.addAttributes(
                key: key,
                service: service,
                data: data,
                useDataProtectionKeychain: useDataProtectionKeychain
            ) as CFDictionary,
            nil
        )
        if addStatus == errSecDuplicateItem {
            return SecItemUpdate(
                lookup as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
        }
        return addStatus
    }

    private static func loadItem(
        key: String,
        service: String,
        useDataProtectionKeychain: Bool
    ) -> String? {
        var query = KeychainItemQuery.searchQuery(
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

    private static let legacyItemLocations: [(service: String, useDataProtectionKeychain: Bool)] = [
        (legacyReinstallService, false),
        (service, false),
    ]

    private static func deleteLegacyItems(
        key: String,
        preservingFileBasedServiceItem: Bool
    ) {
        let locations = legacyItemLocations.filter { location in
            !(preservingFileBasedServiceItem && location.service == service)
        }
        for legacy in locations {
            let query = KeychainItemQuery.searchQuery(
                key: key,
                service: legacy.service,
                useDataProtectionKeychain: legacy.useDataProtectionKeychain
            )
            _ = SecItemDelete(query as CFDictionary)
        }
    }
}

enum KeychainItemQuery {
    static func searchQuery(
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

    static func addAttributes(
        key: String,
        service: String,
        data: Data,
        useDataProtectionKeychain: Bool
    ) -> [CFString: Any] {
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
        ]
        if useDataProtectionKeychain {
            attributes[kSecUseDataProtectionKeychain] = true
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        }
        return attributes
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
        for candidate in LLMEndpointIdentity.lookupKeys(baseURL) {
            let value = keysByBaseURL[candidate] ?? ""
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    mutating func setKey(_ apiKey: String, for baseURL: String) {
        let canonicalBaseURL = Self.canonicalBaseURL(baseURL)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        for alias in LLMEndpointIdentity.lookupKeys(baseURL) {
            keysByBaseURL.removeValue(forKey: alias)
        }
        if canonicalBaseURL.isEmpty {
            return
        }
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
        LLMEndpointIdentity.key(baseURL)
    }
}
