import XCTest
import Security
@testable import LumenPDF

final class KeychainItemQueryTests: XCTestCase {
    func testAddAttributesDoNotIncludeSearchOnlyKeys() {
        let data = Data("vault-json".utf8)
        let attributes = KeychainItemQuery.addAttributes(
            key: "llm_api_key",
            service: "com.LumenPDF.app",
            data: data,
            useDataProtectionKeychain: true
        )

        XCTAssertNil(attributes[kSecUseAuthenticationUI])
        XCTAssertNil(attributes[kSecReturnData])
        XCTAssertNil(attributes[kSecMatchLimit])
        XCTAssertEqual(
            attributes[kSecAttrAccessible] as? String,
            kSecAttrAccessibleWhenUnlocked as String
        )
        XCTAssertEqual(attributes[kSecValueData] as? Data, data)
        XCTAssertEqual(attributes[kSecUseDataProtectionKeychain] as? Bool, true)
    }

    func testSearchQuerySuppressesAuthenticationUI() {
        let query = KeychainItemQuery.searchQuery(
            key: "llm_api_key",
            service: "com.LumenPDF.app",
            useDataProtectionKeychain: true
        )

        XCTAssertEqual(
            query[kSecUseAuthenticationUI] as? String,
            kSecUseAuthenticationUIFail as String
        )
        XCTAssertNil(query[kSecValueData])
        XCTAssertNil(query[kSecAttrAccessible])
    }

    func testFileBasedAddAttributesOmitDataProtectionKeys() {
        let data = Data("vault-json".utf8)
        let attributes = KeychainItemQuery.addAttributes(
            key: "llm_api_key",
            service: "com.LumenPDF.app",
            data: data,
            useDataProtectionKeychain: false
        )

        XCTAssertNil(attributes[kSecUseDataProtectionKeychain])
        XCTAssertNil(attributes[kSecAttrAccessible])
        XCTAssertNil(attributes[kSecUseAuthenticationUI])
        XCTAssertEqual(attributes[kSecValueData] as? Data, data)
    }

    func testMissingEntitlementFallsBackToFileBasedKeychain() {
        XCTAssertTrue(
            KeychainWriteFallback.shouldUseFileBasedKeychain(after: errSecMissingEntitlement)
        )
        XCTAssertFalse(
            KeychainWriteFallback.shouldUseFileBasedKeychain(after: errSecItemNotFound)
        )
        XCTAssertFalse(
            KeychainWriteFallback.shouldUseFileBasedKeychain(after: errSecSuccess)
        )
    }

    func testMissingEntitlementMessageDoesNotExposeStatusCode() {
        let message = KeychainSaveFailureMessage.userFacing(errSecMissingEntitlement)
        XCTAssertEqual(message, "无法保存 API Key。当前安装无法写入钥匙串。")
        XCTAssertFalse(message.contains("34018"))
        XCTAssertFalse(message.contains("重新安装"))
        XCTAssertEqual(
            KeychainServiceError.saveFailed(errSecMissingEntitlement).localizedDescription,
            message
        )
    }

    func testGenericKeychainFailureMessageStaysActionable() {
        XCTAssertEqual(
            KeychainSaveFailureMessage.userFacing(-1),
            "无法保存 API Key，请稍后重试。"
        )
        XCTAssertEqual(
            KeychainServiceError.encodingFailed.localizedDescription,
            "无法保存 API Key，请重新输入后再试。"
        )
    }

    func testSettingsSaveFeedbackUsesKeychainMessageInsteadOfGenericFailure() {
        XCTAssertEqual(
            SettingsSaveFeedback.message(
                for: KeychainServiceError.saveFailed(errSecMissingEntitlement)
            ),
            "无法保存 API Key。当前安装无法写入钥匙串。"
        )
        XCTAssertEqual(
            SettingsSaveFeedback.message(
                for: SettingsPromptValidationError(messages: ["单词：缺少 {word}"])
            ),
            "提示词验证失败：单词：缺少 {word}"
        )
    }
}
