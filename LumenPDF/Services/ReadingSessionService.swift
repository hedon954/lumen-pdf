import CryptoKit
import Foundation

/// Reading-session helpers that stay on the Swift side (no Rust calls).
enum ReadingSessionService {
    /// SHA-256 of the lowercased sentence; must match Rust `sentence_hash`.
    static func sentenceHash(_ sentence: String) -> String {
        let data = Data(sentence.lowercased().utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
