import XCTest
import Security
@testable import LumenPDF

final class KeychainItemQueryTests: XCTestCase {
    func testAddAttributesDoNotIncludeSearchOnlyKeys() {
        let data = Data("vault-json".utf8)
        let attributes = KeychainItemQuery.addAttributes(
            key: "llm_api_key",
            service: "com.LumenPDF.app",
            data: data
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

    func testMissingEntitlementMessageDoesNotExposeStatusCode() {
        let message = KeychainSaveFailureMessage.userFacing(errSecMissingEntitlement)
        XCTAssertEqual(
            message,
            "无法保存 API Key。当前应用无法访问钥匙串，请重新安装后再试。"
        )
        XCTAssertFalse(message.contains("34018"))
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
            "无法保存 API Key。当前应用无法访问钥匙串，请重新安装后再试。"
        )
        XCTAssertEqual(
            SettingsSaveFeedback.message(
                for: SettingsPromptValidationError(messages: ["单词：缺少 {word}"])
            ),
            "提示词验证失败：单词：缺少 {word}"
        )
    }
}
