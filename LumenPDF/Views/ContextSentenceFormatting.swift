import Foundation

/// PDF 文本流里常带有按排版插入的换行，展示时合并为一段连贯句子。
enum ContextSentenceFormatting {
    static func displayParagraph(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"([A-Za-z])-\s*\n\s*([A-Za-z])"#,
                with: "$1$2",
                options: .regularExpression
            )
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// PDF 文本层偶尔会把同一句话画多遍（描边加粗、重叠 glyph、OCR 叠加）。
/// PDFKit 的 `selection.string` 会把这些副本全部拼进选区，进而污染翻译和解释请求。
enum PDFExtractedTextCollapser {
    static let minimumUnitLength = 24
    static let minimumRepeatCount = 3

    static func collapse(_ text: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        if let collapsed = collapseIdenticalSegments(trimmed.components(separatedBy: "\n")) {
            return collapsed
        }
        if let collapsed = collapseIdenticalSegments(sentenceBlocks(in: trimmed)) {
            return collapsed
        }
        if let collapsed = collapseExactTile(trimmed) {
            return collapsed
        }
        return trimmed
    }

    private static func collapseIdenticalSegments(_ segments: [String]) -> String? {
        let cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard cleaned.count >= minimumRepeatCount,
              let first = cleaned.first,
              first.count >= minimumUnitLength,
              cleaned.allSatisfy({ $0 == first })
        else { return nil }
        return first
    }

    private static func sentenceBlocks(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<=[.!?。！？])(?:[ \t]*\n+|\s+)"#
        ) else { return [text] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var blocks: [String] = []
        var cursor = 0
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let part = nsText
                .substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty {
                blocks.append(part)
            }
            cursor = match.range.location + match.range.length
        }
        let tail = nsText.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            blocks.append(tail)
        }
        return blocks
    }

    private static func collapseExactTile(_ text: String) -> String? {
        let chars = Array(text)
        let count = chars.count
        guard count >= minimumUnitLength * minimumRepeatCount else { return nil }

        var longestPrefixSuffix = Array(repeating: 0, count: count)
        var prefixLength = 0
        var index = 1
        while index < count {
            if chars[index] == chars[prefixLength] {
                prefixLength += 1
                longestPrefixSuffix[index] = prefixLength
                index += 1
            } else if prefixLength > 0 {
                prefixLength = longestPrefixSuffix[prefixLength - 1]
            } else {
                longestPrefixSuffix[index] = 0
                index += 1
            }
        }

        let period = count - longestPrefixSuffix[count - 1]
        guard period >= minimumUnitLength,
              count % period == 0,
              count / period >= minimumRepeatCount
        else { return nil }
        return String(chars[0..<period]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
