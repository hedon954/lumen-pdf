import Foundation

enum NoteTextList {
    static func decode(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return [trimmed]
    }

    static func encode(_ notes: [String]) -> String {
        let cleaned = notes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        guard let data = try? JSONEncoder().encode(cleaned),
              let json = String(data: data, encoding: .utf8) else {
            return cleaned.joined(separator: "\n\n")
        }
        return json
    }

    static func storageString(from text: String) -> String {
        encode(decode(text))
    }

    static func appending(_ text: String, to raw: String) -> String {
        encode(decode(raw) + decode(text))
    }

    static func markdown(_ raw: String) -> String {
        let notes = decode(raw)
        guard !notes.isEmpty else { return "" }
        if notes.count == 1 { return notes[0] }
        return notes.map { "- \($0)" }.joined(separator: "\n")
    }

    static func plainSummary(_ raw: String) -> String {
        decode(raw).joined(separator: "\n")
    }

    static func editText(_ raw: String) -> String {
        decode(raw).joined(separator: "\n\n")
    }
}
