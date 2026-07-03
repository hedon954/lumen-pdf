import Security
import Foundation
import LocalAuthentication

enum KeychainService {
    private static let service = "com.LumenPDF.app"
    // Ad-hoc debug builds get a fresh code signature after reinstall, so this
    // item avoids binding API-key access to the previous installed binary.
    private static let reinstallStableService = "com.LumenPDF.app.reinstall-stable"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let stableStatus = store(
            key: key,
            data: data,
            service: reinstallStableService,
            useDataProtectionKeychain: false,
            usesReinstallStableAccess: true
        )
        let protectedStatus = store(
            key: key,
            data: data,
            service: service,
            useDataProtectionKeychain: true,
            usesReinstallStableAccess: false
        )
        if protectedStatus == errSecSuccess || stableStatus == errSecSuccess {
            return
        }
        _ = store(
            key: key,
            data: data,
            service: service,
            useDataProtectionKeychain: false,
            usesReinstallStableAccess: true
        )
    }

    static func load(key: String) -> String? {
        if let value = load(
            key: key,
            service: reinstallStableService,
            useDataProtectionKeychain: false
        ) {
            return value
        }

        if let value = load(
            key: key,
            service: service,
            useDataProtectionKeychain: true
        ) {
            migrate(value: value, key: key)
            return value
        }

        guard let value = load(
            key: key,
            service: service,
            useDataProtectionKeychain: false
        ) else { return nil }
        migrate(value: value, key: key)
        return value
    }

    private static func migrate(value: String, key: String) {
        let data = Data(value.utf8)
        _ = store(
            key: key,
            data: data,
            service: reinstallStableService,
            useDataProtectionKeychain: false,
            usesReinstallStableAccess: true
        )
        _ = store(
            key: key,
            data: data,
            service: service,
            useDataProtectionKeychain: true,
            usesReinstallStableAccess: false
        )
    }

    private static func store(
        key: String,
        data: Data,
        service: String,
        useDataProtectionKeychain: Bool,
        usesReinstallStableAccess: Bool
    ) -> OSStatus {
        let updateQuery = query(
            key: key,
            service: service,
            useDataProtectionKeychain: useDataProtectionKeychain,
            allowAuthenticationUI: false
        )
        let updateAttrs: [CFString: Any] = [
            kSecValueData: data,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return updateStatus
        }
        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        var addAttrs = query(
            key: key,
            service: service,
            useDataProtectionKeychain: useDataProtectionKeychain,
            allowAuthenticationUI: Optional<Bool>.none
        )
        addAttrs[kSecValueData] = data
        if usesReinstallStableAccess,
           let access = reinstallStableAccess(name: service) {
            addAttrs[kSecAttrAccess] = access
        }
        return SecItemAdd(addAttrs as CFDictionary, nil)
    }

    private static func load(
        key: String,
        service: String,
        useDataProtectionKeychain: Bool
    ) -> String? {
        var query = query(
            key: key,
            service: service,
            useDataProtectionKeychain: useDataProtectionKeychain,
            allowAuthenticationUI: false
        )
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func query(
        key: String,
        service: String,
        useDataProtectionKeychain: Bool,
        allowAuthenticationUI: Bool?
    ) -> [CFString: Any] {
        var attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain,
        ]
        if let allowAuthenticationUI {
            let context = LAContext()
            context.interactionNotAllowed = !allowAuthenticationUI
            attrs[kSecUseAuthenticationContext] = context
        }
        return attrs
    }

    private static func reinstallStableAccess(name: String) -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate(name as CFString, nil, &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
}
