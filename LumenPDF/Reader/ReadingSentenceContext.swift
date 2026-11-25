import CoreGraphics
import Foundation
import NaturalLanguage

/// Builds the sentence context shown for a selected word from the lines actually on the page.
///
/// `PDFPage.string` and `PDFSelection.range(at:on:)` often miss the sentence that is visible
/// around the caret, so the translation request used to contain only the word. Line geometry
/// follows the paragraph the reader can see.
enum ReadingSentenceContext {
    struct Resolved {
        let word: String
        let sentence: String
        let lines: [PDFTextLine]
    }

    static func extract(
        lines: [PDFTextLine],
        selectionRect: CGRect,
        selectedText: String
    ) -> String? {
        resolve(lines: lines, selectionRect: selectionRect, selectedText: selectedText)?.sentence
    }

    static func resolve(
        lines: [PDFTextLine],
        selectionRect: CGRect,
        selectedText: String
    ) -> Resolved? {
        guard let hit = ParagraphJoiner.paragraph(around: lines, selectionRect: selectionRect) else {
            return nil
        }
        let joined = JoinedLines.make(hit.lines)
        let anchorLine = hit.lines[hit.anchorIndex]
        let localIndex = characterIndex(in: anchorLine, selectionRect: selectionRect)
        let lineSpan = joined.lineRanges[hit.anchorIndex]
        let anchored = joined.text.index(
            lineSpan.lowerBound,
            offsetBy: min(localIndex, joined.text.distance(from: lineSpan.lowerBound, to: lineSpan.upperBound)),
            limitedBy: lineSpan.upperBound
        ) ?? lineSpan.lowerBound
        guard let sentenceRange = sentenceRange(containing: anchored, in: joined.text) else { return nil }
        let sentence = widenedRange(around: sentenceRange, anchor: anchored, in: joined.text, selectedText: selectedText)
        let word = token(on: anchorLine, at: localIndex, selectedText: selectedText)
        guard sentence.count >= 2 else { return nil }
        return Resolved(word: word, sentence: sentence, lines: [anchorLine])
    }

    /// The token under the selection on this line. A cut-off drag (`exer`) becomes the token
    /// it sits inside. A finished word is never replaced by a different word on another line.
    static func token(on line: PDFTextLine, at characterIndex: Int, selectedText: String) -> String {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selected.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return selected
        }
        guard !text.isEmpty else { return selected }
        let clamped = min(max(characterIndex, 0), text.count - 1)
        let index = text.index(text.startIndex, offsetBy: clamped)
        let tokens = tokenRanges(in: text)
        guard let token = tokens.first(where: { $0.contains(index) }) else {
            return selected
        }
        let value = String(text[token])
        let selectedCore = core(selected)
        let tokenCore = core(value)
        if selectedCore.isEmpty { return tokenCore }
        if tokenCore.compare(selectedCore, options: .caseInsensitive) == .orderedSame {
            return tokenCore
        }
        if tokenCore.lowercased().hasPrefix(selectedCore.lowercased()), tokenCore.count > selectedCore.count {
            return tokenCore
        }
        return selected.isEmpty ? tokenCore : selected
    }

    /// Same widening rules for a page string that has already been extracted.
    static func widen(text: String, selectedText: String) -> String? {
        let rawLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let lines = rawLines.enumerated().map { index, line in
            PDFTextLine(
                rect: CGRect(x: 0, y: CGFloat(20_000 - index * 18), width: 460, height: 14),
                text: line
            )
        }
        return extract(lines: lines, selectionRect: .zero, selectedText: selectedText)
    }

    /// Keeps a context that still contains surrounding words. A heading strip or a bad
    /// character range sometimes reduces that context to the selected word alone.
    static func prefer(_ first: String?, _ second: String?, selectedText: String) -> String? {
        let options = [first, second].compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return nil }
            return trimmed
        }
        guard var best = options.first else { return nil }
        for candidate in options.dropFirst() where isThin(best, selectedText: selectedText) {
            let candidateThin = isThin(candidate, selectedText: selectedText)
            if !candidateThin || candidate.count > best.count {
                best = candidate
            }
        }
        return best
    }

    static func isThin(_ sentence: String, selectedText: String) -> Bool {
        let sentenceWords = words(sentence)
        guard !sentenceWords.isEmpty else { return true }
        let selectedWords = words(selectedText)
        if selectedWords.isEmpty {
            return sentenceWords.count <= 3
        }
        return sentenceWords.count <= selectedWords.count + 2
    }

    private static func core(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    private struct JoinedLines {
        let text: String
        let lineRanges: [Range<String.Index>]

        static func make(_ lines: [PDFTextLine]) -> JoinedLines {
            var text = ""
            var ranges: [Range<String.Index>] = []
            for line in lines {
                let piece = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else {
                    let empty = text.endIndex..<text.endIndex
                    ranges.append(empty)
                    continue
                }
                if text.isEmpty {
                    text = piece
                    ranges.append(text.startIndex..<text.endIndex)
                    continue
                }
                let start: String.Index
                if text.hasSuffix("-"), let next = piece.first, next.isLowercase {
                    text.removeLast()
                    start = text.endIndex
                    text += piece
                } else {
                    text += " "
                    start = text.endIndex
                    text += piece
                }
                ranges.append(start..<text.endIndex)
            }
            return JoinedLines(text: text, lineRanges: ranges)
        }
    }

    private static func characterIndex(in line: PDFTextLine, selectionRect: CGRect) -> Int {
        let piece = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard piece.count > 1, line.rect.width > 1 else { return 0 }
        let fraction = (selectionRect.midX - line.rect.minX) / line.rect.width
        let clamped = min(max(fraction, 0), 0.999)
        return min(piece.count - 1, Int((CGFloat(piece.count) * clamped).rounded(.down)))
    }

    private static func sentenceRange(containing index: String.Index, in text: String) -> Range<String.Index>? {
        sentenceRanges(in: text).first { $0.contains(index) || $0.upperBound == index }
    }

    private static func widenedRange(
        around sentence: Range<String.Index>,
        anchor: String.Index,
        in text: String,
        selectedText: String
    ) -> String {
        let ranges = sentenceRanges(in: text)
        guard let index = ranges.firstIndex(where: { $0 == sentence || $0.contains(anchor) }) else {
            return String(text[sentence])
        }
        let current = String(text[ranges[index]])
        let thin = isThin(current, selectedText: selectedText)
        let opensOnSelection = startsWithSelection(current, selectedText: selectedText)
        if !thin && !opensOnSelection {
            return current.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lower = ranges[index].lowerBound
        var upper = ranges[index].upperBound
        if index > 0 { lower = ranges[index - 1].lowerBound }
        if thin, index + 1 < ranges.count { upper = ranges[index + 1].upperBound }
        return String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func startsWithSelection(_ sentence: String, selectedText: String) -> Bool {
        guard let first = words(sentence).first,
              let selected = words(selectedText).first else { return false }
        let punctuation = CharacterSet.punctuationCharacters
        let opening = first.trimmingCharacters(in: punctuation)
        let needle = selected.trimmingCharacters(in: punctuation)
        guard !opening.isEmpty, !needle.isEmpty else { return false }
        return opening.compare(needle, options: .caseInsensitive) == .orderedSame
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
        while lower < upper, text[lower].isWhitespace || text[lower].isNewline { lower = text.index(after: lower) }
        while upper > lower, text[text.index(before: upper)].isWhitespace { upper = text.index(before: upper) }
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

    private static func cap(_ text: String, around selectedText: String) -> String {
        guard text.count > 800 else { return text }
        guard let range = text.range(of: selectedText, options: .caseInsensitive) else {
            return String(text.prefix(800))
        }
        let startDistance = text.distance(from: text.startIndex, to: range.lowerBound)
        let lower = max(0, startDistance - 400)
        let upper = min(text.count, lower + 800)
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        return String(text[start..<end])
    }

    private static func words(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }
}
