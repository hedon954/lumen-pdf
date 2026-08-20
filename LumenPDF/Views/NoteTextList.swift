import Foundation

enum NoteTextList {
    static func decode(_ raw: String) -> [String] {
        decode(raw, depth: 0)
    }

    private static func decode(_ raw: String, depth: Int) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8) else { return [trimmed] }
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let cleaned = decoded
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard depth < 2 else { return cleaned }
            return cleaned.flatMap { decode($0, depth: depth + 1) }
        }
        if depth < 2,
           let decoded = try? JSONDecoder().decode(String.self, from: data),
           decoded != trimmed {
            return decode(decoded, depth: depth + 1)
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

    static func removingItem(at index: Int, from raw: String) -> String? {
        var notes = decode(raw)
        guard notes.indices.contains(index) else { return nil }
        notes.remove(at: index)
        return encode(notes)
    }

    static func replacingItem(at index: Int, with text: String, from raw: String) -> String? {
        var notes = decode(raw)
        guard notes.indices.contains(index) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        notes[index] = trimmed
        return encode(notes)
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
