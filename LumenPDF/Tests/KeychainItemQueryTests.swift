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
}
