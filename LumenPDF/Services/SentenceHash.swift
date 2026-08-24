import CryptoKit
import Foundation

/// SHA-256 of the lowercased sentence; must match Rust `sentence_hash`.
enum SentenceHash {
    static func hash(_ sentence: String) -> String {
        let data = Data(sentence.lowercased().utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
