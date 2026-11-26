import CoreGraphics
import Foundation
import NaturalLanguage

/// One visual line, plus the characters on it the user actually selected.
///
/// A line with `selected == nil` is only there so a sentence can be completed
/// across a line wrap or a page break. It is not part of the selection.
struct ReadingLine: Equatable {
    var pageIndex: Int
    var rect: CGRect
    var text: String
    /// Character offsets into `text`. Nil when the line is context only.
    var selected: Range<Int>?
}

/// The sentence that covers a selection.
///
/// The selection is a span of characters in reading order. Soft line wraps,
/// including a page break that continues the same paragraph, are joined first.
/// Sentence boundaries then come from `NLTokenizer`. The result is every
/// sentence the span touches, extended to that sentence's own start and end.
/// A neighboring sentence the span does not touch is not added.
enum ReadingSentenceContext {
    struct Resolved: Equatable {
        let word: String
        let sentence: String
    }

    static func resolve(lines: [ReadingLine]) -> Resolved? {
        let paragraphs = group(lines)
        var sentences: [String] = []
        var words: [String] = []
        for paragraph in paragraphs where paragraph.contains(where: { $0.selected != nil }) {
            let joined = join(paragraph)
            guard let sentence = coveringSentences(in: joined) else { continue }
            let word = word(in: joined)
            guard !sentence.isEmpty else { continue }
            sentences.append(sentence)
            if !word.isEmpty { words.append(word) }
        }
        let sentence = sentences.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let word = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentence.count >= 2, !word.isEmpty else { return nil }
        return Resolved(word: word, sentence: sentence)
    }

    private struct Joined {
        var text: String
        var selected: [Range<String.Index>]
    }

    private static func group(_ lines: [ReadingLine]) -> [[ReadingLine]] {
        let ordered = lines.compactMap(trimmed).sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            if abs(lhs.rect.midY - rhs.rect.midY) > 1 { return lhs.rect.midY > rhs.rect.midY }
            return lhs.rect.minX < rhs.rect.minX
        }
        var groups: [[ReadingLine]] = []
        var current: [ReadingLine] = []
        for line in ordered {
            if let last = current.last, !sameParagraph(last, line) {
                groups.append(current)
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func trimmed(_ line: ReadingLine) -> ReadingLine? {
        let original = line.text
        let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let leading = original.prefix { $0.isWhitespace || $0.isNewline }.count
        let selected = line.selected.flatMap { range -> Range<Int>? in
            let lower = max(0, range.lowerBound - leading)
            let upper = min(text.count, range.upperBound - leading)
            guard lower < upper else { return nil }
            return lower..<upper
        }
        return ReadingLine(pageIndex: line.pageIndex, rect: line.rect, text: text, selected: selected)
    }

    private static func sameParagraph(_ earlier: ReadingLine, _ later: ReadingLine) -> Bool {
        ParagraphJoiner.continuesInReadingOrder(
            PDFTextLine(rect: earlier.rect, text: earlier.text),
            to: PDFTextLine(rect: later.rect, text: later.text),
            pageGap: later.pageIndex - earlier.pageIndex
        )
    }

    private static func join(_ lines: [ReadingLine]) -> Joined {
        var text = ""
        var selectedOffsets: [Range<Int>] = []
        for line in lines {
            if !text.isEmpty {
                if text.hasSuffix("-"), let next = line.text.first, next.isLowercase {
                    text.removeLast()
                    if let index = selectedOffsets.indices.last, selectedOffsets[index].upperBound > text.count {
                        let lower = min(selectedOffsets[index].lowerBound, text.count)
                        if lower < text.count {
                            selectedOffsets[index] = lower..<text.count
                        } else {
                            selectedOffsets.removeLast()
                        }
                    }
                } else {
                    text += " "
                }
            }
            let start = text.count
            text += line.text
            if let selected = line.selected {
                let lower = start + selected.lowerBound
                let upper = start + selected.upperBound
                if lower >= start, upper <= text.count, lower < upper {
                    selectedOffsets.append(lower..<upper)
                }
            }
        }
        return Joined(
            text: text,
            selected: selectedOffsets.compactMap { stringRange($0, in: text) }
        )
    }

    private static func coveringSentences(in joined: Joined) -> String? {
        let ranges = sentenceRanges(in: joined.text)
        let covering = ranges.filter { sentence in
            joined.selected.contains { overlaps(sentence, $0) }
        }
        guard let first = covering.first, let last = covering.last else { return nil }
        return String(joined.text[first.lowerBound..<last.upperBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One selected token is that word, even when the drag stopped mid-word.
    /// Several tokens stay the words the user selected, not the whole sentence.
    private static func word(in joined: Joined) -> String {
        let tokens = tokenRanges(in: joined.text).filter { token in
            joined.selected.contains { overlaps(token, $0) }
        }
        if tokens.count == 1 {
            return core(String(joined.text[tokens[0]]))
        }
        return joined.selected
            .map { String(joined.text[$0]) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringRange(_ offsets: Range<Int>, in text: String) -> Range<String.Index>? {
        guard offsets.lowerBound >= 0,
              offsets.upperBound <= text.count,
              offsets.lowerBound < offsets.upperBound else { return nil }
        let lower = text.index(text.startIndex, offsetBy: offsets.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: offsets.upperBound)
        return lower..<upper
    }

    private static func overlaps(_ lhs: Range<String.Index>, _ rhs: Range<String.Index>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private static func core(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        return trimmed.isEmpty ? word : trimmed
    }

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let trimmed = trim(range, in: text)
            if !trimmed.isEmpty { ranges.append(trimmed) }
            return true
        }
        if ranges.isEmpty, !text.isEmpty {
            return [text.startIndex..<text.endIndex]
        }
        return mergeContinuationRanges(ranges, in: text)
    }

    private static func trim(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace || text[lower].isNewline {
            lower = text.index(after: lower)
        }
        while upper > lower, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }
        return lower..<upper
    }

    /// `NLTokenizer` still breaks after `Mr.` and `3.`. Those fragments belong to the next sentence.
    private static func mergeContinuationRanges(
        _ ranges: [Range<String.Index>],
        in text: String
    ) -> [Range<String.Index>] {
        var merged: [Range<String.Index>] = []
        var index = 0
        while index < ranges.count {
            var current = ranges[index]
            while continues(String(text[current])), index + 1 < ranges.count {
                index += 1
                current = current.lowerBound..<ranges[index].upperBound
            }
            merged.append(current)
            index += 1
        }
        return merged
    }

    private static func continues(_ sentence: String) -> Bool {
        let parts = words(sentence)
        guard parts.count == 1, let token = parts.first else { return false }
        let core = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
        if core.isEmpty { return false }
        if core.allSatisfy(\.isNumber) { return true }
        return ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "eg", "ie"].contains(core)
    }

    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace || text[index].isNewline {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace, !text[index].isNewline {
                index = text.index(after: index)
            }
            ranges.append(start..<index)
        }
        return ranges
    }

    private static func words(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }
}
