import XCTest
@testable import LumenPDF

final class LLMAPIKeyVaultTests: XCTestCase {
    func testKeysAreScopedByCanonicalBaseURLAndRestoreWhenSwitchingBack() {
        var vault = LLMAPIKeyVault()
        vault.setKey("deepseek-key", for: "https://api.deepseek.com/v1/")
        vault.setKey("opencode-key", for: "https://opencode.ai/zen/v1")

        XCTAssertEqual(vault.key(for: "https://api.deepseek.com/v1"), "deepseek-key")
        XCTAssertEqual(vault.key(for: "https://opencode.ai/zen/v1/"), "opencode-key")
        XCTAssertNil(vault.key(for: "https://api.openai.com/v1"))
    }

    func testClearingOneProviderDoesNotRemoveOtherProviderKeys() {
        var vault = LLMAPIKeyVault()
        vault.setKey("deepseek-key", for: "https://api.deepseek.com/v1")
        vault.setKey("opencode-key", for: "https://opencode.ai/zen/v1")

        vault.setKey("  ", for: "https://opencode.ai/zen/v1")

        XCTAssertEqual(vault.key(for: "https://api.deepseek.com/v1"), "deepseek-key")
        XCTAssertNil(vault.key(for: "https://opencode.ai/zen/v1"))
    }

    func testLegacySingleKeyMigratesToCurrentProviderAndRoundTrips() throws {
        let migrated = LLMAPIKeyVault.decode(
            "legacy-key",
            legacyBaseURL: "https://api.deepseek.com/v1"
        )

        XCTAssertTrue(migrated.didMigrate)
        XCTAssertEqual(
            migrated.vault.key(for: "https://api.deepseek.com/v1"),
            "legacy-key"
        )
        XCTAssertNil(migrated.vault.key(for: "https://opencode.ai/zen/v1"))

        let encoded = try XCTUnwrap(migrated.vault.encoded())
        let decoded = LLMAPIKeyVault.decode(
            encoded,
            legacyBaseURL: "https://opencode.ai/zen/v1"
        )
        XCTAssertFalse(decoded.didMigrate)
        XCTAssertEqual(decoded.vault, migrated.vault)
    }

    func testIntermediateUnversionedVaultKeepsOnlyTheOriginalProviderBinding() {
        let decoded = LLMAPIKeyVault.decode(
            """
            {"keysByBaseURL":{"https://api.deepseek.com/v1":"legacy-key","https://opencode.ai/zen/v1":"legacy-key"}}
            """,
            legacyBaseURL: "https://api.deepseek.com/v1"
        )

        XCTAssertTrue(decoded.didMigrate)
        XCTAssertEqual(
            decoded.vault.key(for: "https://api.deepseek.com/v1"),
            "legacy-key"
        )
        XCTAssertNil(decoded.vault.key(for: "https://opencode.ai/zen/v1"))
    }
}
