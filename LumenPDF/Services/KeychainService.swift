import Foundation
import Security

enum KeychainService {
    private static let service = "com.LumenPDF.app"
    private static let legacyReinstallService = "com.LumenPDF.app.reinstall-stable"

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
