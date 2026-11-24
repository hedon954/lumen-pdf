import CoreGraphics
import Foundation

/// Builds the sentence context shown for a selected word from the lines actually on the page.
///
/// `PDFPage.string` and `PDFSelection.range(at:on:)` often miss the sentence that is visible
/// around the caret, so the translation request used to contain only the word. Line geometry
/// follows the paragraph the reader can see.
enum ReadingSentenceContext {
    static func extract(
        lines: [PDFTextLine],
        selectionRect: CGRect,
        selectedText: String
    ) -> String? {
        let ordered = lines
            .map { PDFTextLine(rect: $0.rect, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
            .sorted { lhs, rhs in
                if abs(lhs.rect.midY - rhs.rect.midY) > 1 {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhs.rect.minX < rhs.rect.minX
            }
        guard let anchor = anchorIndex(in: ordered, selectionRect: selectionRect, selectedText: selectedText) else {
            return nil
        }

        let range = paragraphRange(around: anchor, in: ordered)
        let joined = ContextSentenceFormatting.displayParagraph(
            ordered[range].map(\.text).joined(separator: "\n")
        )
        let sentence = widenedSentence(in: joined, selectedText: selectedText) ?? joined
        let capped = cap(sentence, around: selectedText)
        guard capped.count >= 2 else { return nil }
        return capped
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

    private static func anchorIndex(
        in lines: [PDFTextLine],
        selectionRect: CGRect,
        selectedText: String
    ) -> Int? {
        if !selectionRect.isNull, !selectionRect.isEmpty {
            let hits = lines.enumerated().filter {
                selectionRect.intersects($0.element.rect.insetBy(dx: -1, dy: -1))
            }
            if let best = hits.max(by: { lhs, rhs in
                intersectionArea(lhs.element.rect, selectionRect)
                    < intersectionArea(rhs.element.rect, selectionRect)
            }) {
                return best.offset
            }
        }
        let needle = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return lines.firstIndex { $0.text.range(of: needle, options: .caseInsensitive) != nil }
    }

    private static func paragraphRange(around anchor: Int, in lines: [PDFTextLine]) -> Range<Int> {
        var start = anchor
        while start > 0, isSameParagraph(lines[start - 1], lines[start]) {
            start -= 1
        }
        var end = anchor
        while end + 1 < lines.count, isSameParagraph(lines[end], lines[end + 1]) {
            end += 1
        }
        return start..<(end + 1)
    }

    private static func isSameParagraph(_ upper: PDFTextLine, _ lower: PDFTextLine) -> Bool {
        let gap = upper.rect.minY - lower.rect.maxY
        let lineHeight = max(upper.rect.height, lower.rect.height, 8)
        if gap > lineHeight * 0.95 { return false }
        if abs(upper.rect.minX - lower.rect.minX) > 96, gap > lineHeight * 0.35 { return false }
        return true
    }

    private static func widenedSentence(in paragraph: String, selectedText: String) -> String? {
        let sentences = splitSentences(paragraph)
        guard let index = sentences.firstIndex(where: { containsSelection($0, selectedText: selectedText) }) else {
            return nil
        }
        let sentence = sentences[index]
        let thin = isThin(sentence, selectedText: selectedText)
        // A sentence that opens on the selected word still hides its subject in the previous one.
        let opensOnSelection = startsWithSelection(sentence, selectedText: selectedText)
        if !thin && !opensOnSelection {
            return sentence
        }
        var parts: [String] = []
        if index > 0 { parts.append(sentences[index - 1]) }
        parts.append(sentence)
        if thin, index + 1 < sentences.count { parts.append(sentences[index + 1]) }
        return parts.joined(separator: " ")
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

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?。！？".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private static func containsSelection(_ sentence: String, selectedText: String) -> Bool {
        let needle = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return sentence.range(of: needle, options: .caseInsensitive) != nil
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

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        lhs.intersection(rhs).area
    }
}
