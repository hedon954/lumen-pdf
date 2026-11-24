import CryptoKit
import Foundation
import IOKit

enum CredentialVaultError: Error {
    case encodingFailed
    case writeFailed
}

/// AES-GCM sealed record written to Application Support. The wrapping key is
/// derived from this Mac's platform UUID, so ad-hoc re-signing does not change
/// access the way login-keychain ACLs do.
enum CredentialVaultCodec {
    static let magic = Data("LPD1".utf8)
    static let version: UInt8 = 1

    static func key(machineIdentifier: String) -> SymmetricKey {
        let material = Data("LumenPDF.credential-vault.v1|\(machineIdentifier)".utf8)
        return SymmetricKey(data: SHA256.hash(data: material))
    }

    static func seal(_ plaintext: String, key: SymmetricKey) throws -> Data {
        guard let plain = plaintext.data(using: .utf8) else {
            throw CredentialVaultError.encodingFailed
        }
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else {
            throw CredentialVaultError.encodingFailed
        }
        var data = Data()
        data.append(magic)
        data.append(version)
        data.append(combined)
        return data
    }

    static func open(_ data: Data, key: SymmetricKey) -> String? {
        let headerCount = magic.count + 1
        guard data.count > headerCount,
              data.prefix(magic.count) == magic,
              data[magic.count] == version
        else { return nil }
        let combined = data.dropFirst(headerCount)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }
}

enum CredentialVaultStore {
    static let fileName = "llm-api-key.vault"

    static var fileURL: URL {
        AppDataDirectory.current.appendingPathComponent(fileName)
    }

    static func save(_ plaintext: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try CredentialVaultCodec.seal(
            plaintext,
            key: CredentialVaultCodec.key(machineIdentifier: HardwareMachineIdentifier.platformUUID())
        )
        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw CredentialVaultError.writeFailed
        }
    }

    static func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return CredentialVaultCodec.open(
            data,
            key: CredentialVaultCodec.key(machineIdentifier: HardwareMachineIdentifier.platformUUID())
        )
    }
}

enum HardwareMachineIdentifier {
    static func platformUUID() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return "unknown-mac" }
        defer { IOObjectRelease(service) }
        guard let cfValue = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String,
            !cfValue.isEmpty
        else {
            return "unknown-mac"
        }
        return cfValue
    }
}
