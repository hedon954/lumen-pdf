import Security
import Foundation

enum KeychainService {
    private static let service = "com.LumenPDF.app"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        if store(key: key, data: data, useDataProtectionKeychain: true) == errSecSuccess {
            return
        }
        _ = store(key: key, data: data, useDataProtectionKeychain: false)
    }

    static func load(key: String) -> String? {
        if let value = load(key: key, useDataProtectionKeychain: true) {
            return value
        }
        guard let legacyValue = load(key: key, useDataProtectionKeychain: false) else {
            return nil
        }

        // Best-effort migration from macOS file-based keychain to the
        // data-protection keychain. Unsigned local builds may lack entitlement,
        // in which case this silently keeps using the legacy item.
        _ = store(
            key: key,
            data: Data(legacyValue.utf8),
            useDataProtectionKeychain: true
        )
        return legacyValue
    }

    private static func store(
        key: String,
        data: Data,
        useDataProtectionKeychain: Bool
    ) -> OSStatus {
        let query = query(key: key, useDataProtectionKeychain: useDataProtectionKeychain)
        let updateAttrs: [CFString: Any] = [
            kSecValueData: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return updateStatus
        }
        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        var addAttrs = query
        addAttrs[kSecValueData] = data
        return SecItemAdd(addAttrs as CFDictionary, nil)
    }

    private static func load(key: String, useDataProtectionKeychain: Bool) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func query(
        key: String,
        useDataProtectionKeychain: Bool
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain,
        ]
    }
}
