import CryptoKit
import XCTest
@testable import LumenPDF

final class CredentialVaultCodecTests: XCTestCase {
    func testSealThenOpenReturnsOriginalPlaintext() throws {
        let key = CredentialVaultCodec.key(machineIdentifier: "mac-a")
        let sealed = try CredentialVaultCodec.seal("{\"k\":\"sk-test\"}", key: key)

        XCTAssertEqual(
            CredentialVaultCodec.open(sealed, key: key),
            "{\"k\":\"sk-test\"}"
        )
        XCTAssertTrue(sealed.starts(with: CredentialVaultCodec.magic))
        XCTAssertEqual(sealed[CredentialVaultCodec.magic.count], CredentialVaultCodec.version)
        XCTAssertFalse(String(data: sealed, encoding: .utf8)?.contains("sk-test") ?? false)
    }

    func testOpenRejectsWrongMachineKey() throws {
        let sealed = try CredentialVaultCodec.seal(
            "secret",
            key: CredentialVaultCodec.key(machineIdentifier: "mac-a")
        )

        XCTAssertNil(
            CredentialVaultCodec.open(
                sealed,
                key: CredentialVaultCodec.key(machineIdentifier: "mac-b")
            )
        )
    }

    func testOpenRejectsTamperedPayload() throws {
        let key = CredentialVaultCodec.key(machineIdentifier: "mac-a")
        var sealed = try CredentialVaultCodec.seal("secret", key: key)
        sealed[sealed.count - 1] ^= 0xFF

        XCTAssertNil(CredentialVaultCodec.open(sealed, key: key))
        XCTAssertNil(CredentialVaultCodec.open(Data("not-a-vault".utf8), key: key))
    }

    func testVaultWriteFailureMessageStaysGeneric() {
        XCTAssertEqual(
            KeychainServiceError.vaultWriteFailed.localizedDescription,
            "无法保存 API Key，请稍后重试。"
        )
        XCTAssertEqual(
            SettingsSaveFeedback.message(for: KeychainServiceError.vaultWriteFailed),
            "无法保存 API Key，请稍后重试。"
        )
    }
}
