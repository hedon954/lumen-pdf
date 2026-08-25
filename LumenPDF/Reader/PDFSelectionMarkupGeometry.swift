import CoreGraphics
import Foundation
import PDFKit

struct PDFPageMarkup: Equatable {
    let pageIndex: Int
    let lineRects: [CGRect]
    let text: String

    var bounds: CGRect {
        lineRects.dropFirst().reduce(lineRects.first ?? .zero) { $0.union($1) }
    }

    var boundsStr: String {
        AnnotationBoundsCodec.string(from: lineRects)
    }
}

/// Stable persistence boundary for the same page-by-page geometry used by free markups.
/// Legacy notes have no payload and fall back to their original `page_index` + `bounds_str`.
enum PDFPageMarkupCodec {
    private struct Record: Codable {
        let pageIndex: Int
        let boundsStr: String
    }

    static func encode(_ markups: [PDFPageMarkup]) -> String {
        let records = normalized(markups).map {
            Record(pageIndex: $0.pageIndex, boundsStr: $0.boundsStr)
        }
        guard !records.isEmpty,
              let data = try? JSONEncoder().encode(records),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    static func decode(
        _ encoded: String,
        fallbackPage: Int,
        fallbackBoundsStr: String,
        fallbackText: String = ""
    ) -> [PDFPageMarkup] {
        if let data = encoded.data(using: .utf8),
           let records = try? JSONDecoder().decode([Record].self, from: data) {
            let decoded = normalized(records.map {
                PDFPageMarkup(
                    pageIndex: $0.pageIndex,
                    lineRects: AnnotationBoundsCodec.parse($0.boundsStr),
                    text: ""
                )
            })
            if !decoded.isEmpty {
                return decoded
            }
        }

        let fallbackRects = AnnotationBoundsCodec.parse(fallbackBoundsStr)
        guard !fallbackRects.isEmpty else { return [] }
        return [
            PDFPageMarkup(
                pageIndex: fallbackPage,
                lineRects: fallbackRects,
                text: fallbackText
            )
        ]
    }

    static func normalized(_ markups: [PDFPageMarkup]) -> [PDFPageMarkup] {
        let grouped = Dictionary(grouping: markups.filter { !$0.lineRects.isEmpty }, by: \.pageIndex)
        return grouped.keys.sorted().compactMap { pageIndex in
            guard let pageMarkups = grouped[pageIndex] else { return nil }
            let lineRects = TextLineMarkupMerge.merge(pageMarkups.flatMap(\.lineRects))
            guard !lineRects.isEmpty else { return nil }
            let text = pageMarkups
                .map(\.text)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            return PDFPageMarkup(pageIndex: pageIndex, lineRects: lineRects, text: text)
        }
    }
}

struct PDFTextLine: Equatable {
    let rect: CGRect
    let text: String
}

struct PDFPageTextLayout: Equatable {
    let pageIndex: Int
    let bounds: CGRect
    let lines: [PDFTextLine]

    func relativeY(_ rect: CGRect) -> CGFloat {
        guard bounds.height > 0 else { return 0 }
        return (rect.midY - bounds.minY) / bounds.height
    }
}

enum PDFPageChromeFilter {
    /// How close two relative Y values must be to count as the same slot on another page.
    /// This is a cross-page alignment tolerance, not a "top of page is a header" rule.
    static let relativeYTolerance: CGFloat = 0.03

    static func bodyLines(
        selected: [PDFTextLine],
        pageBounds: CGRect,
        neighbors: [PDFPageTextLayout]
    ) -> [PDFTextLine] {
        selected.filter { line in
            !line.rect.isEmpty && !isRunningChrome(line, pageBounds: pageBounds, neighbors: neighbors)
        }
    }

    static func isRunningChrome(
        _ line: PDFTextLine,
        pageBounds: CGRect,
        neighbors: [PDFPageTextLayout]
    ) -> Bool {
        guard !line.rect.isEmpty, pageBounds.height > 0 else { return false }
        let signature = runningSignature(line.text)
        guard !signature.isEmpty else { return false }
        let pageY = (line.rect.midY - pageBounds.minY) / pageBounds.height

        return neighbors.contains { neighbor in
            neighbor.lines.contains { other in
                guard abs(neighbor.relativeY(other.rect) - pageY) <= relativeYTolerance else {
                    return false
                }
                return runningSignature(other.text) == signature
            }
        }
    }

    /// Normalize running header/footer text so incrementing page numbers still match.
    /// Only strips page-number tokens at the edges (`50 | …`, `… | 50`, or a bare `50`),
    /// not every digit in the line — otherwise "Figure 3" would collide with "Figure 4".
    static func runningSignature(_ text: String) -> String {
        var normalized = text.lowercased()
            .replacingOccurrences(of: "\u{00ad}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil {
            return "#"
        }
        normalized = normalized.replacingOccurrences(
            of: "^[0-9]{1,4}\\s*[|·•]\\s*",
            with: "",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: "\\s*[|·•]\\s*[0-9]{1,4}$",
            with: "",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// PDFKit 常把附近的小节标题收进 `selection.string`，即使高亮并未盖住标题。
/// 若标题词组又出现在正文里（例如段落以 “concurrency control” 收尾），按子串匹配会把标题行也当成选区。
enum PDFSelectionHeadingLeakFilter {
    static let minimumEchoLength = 8

    static func stripEchoedHeadings(_ lines: [PDFTextLine]) -> [PDFTextLine] {
        guard lines.count >= 2 else { return lines }
        let normalized = lines.map { PDFSelectionTextMatcher.normalize($0.text) }
        return lines.enumerated().compactMap { index, line in
            let needle = normalized[index]
            guard needle.count >= minimumEchoLength, isHeadingLike(line.text) else {
                return line
            }
            let others = normalized.enumerated()
                .compactMap { offset, text in offset == index ? nil : text }
            let joinedOthers = others.joined(separator: " ")
            let echoed = others.contains { other in
                other.count > needle.count && other.contains(needle)
            } || (joinedOthers.count > needle.count && joinedOthers.contains(needle))
            return echoed ? nil : line
        }
    }

    static func stripEchoedHeadings(from text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return text }

        if lines.count == 1 {
            return stripEchoedPrefix(from: lines[0])
        }

        let dummy = lines.map { PDFTextLine(rect: .zero, text: $0) }
        let stripped = stripEchoedHeadings(dummy).map(\.text)
        if stripped.count == 1 {
            return stripEchoedPrefix(from: stripped[0])
        }
        return stripped.joined(separator: "\n")
    }

    static func stripEchoedPrefix(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard words.count >= 10 else { return trimmed }

        let maxPrefix = min(8, words.count / 3)
        guard maxPrefix >= 1 else { return trimmed }
        for count in 1...maxPrefix {
            let prefix = words[0..<count].joined(separator: " ")
            let remainder = words[count...].joined(separator: " ")
            let normalizedPrefix = PDFSelectionTextMatcher.normalize(prefix)
            guard normalizedPrefix.count >= minimumEchoLength, isHeadingLike(prefix) else {
                continue
            }
            let normalizedRemainder = PDFSelectionTextMatcher.normalize(remainder)
            if normalizedRemainder.contains(normalizedPrefix) {
                return remainder
            }
        }
        return trimmed
    }

    static func isHeadingLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return false }
        let terminators = CharacterSet(charactersIn: ".!?。！？")
        if trimmed.unicodeScalars.contains(where: { terminators.contains($0) }) {
            return false
        }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard (1...8).contains(words.count), let first = trimmed.first, first.isLetter else {
            return false
        }
        return true
    }
}

enum PDFSelectionTextMatcher {
    static func matchingLines(selectedText: String, pageLines: [PDFTextLine]) -> [PDFTextLine] {
        let haystack = normalize(selectedText)
        guard haystack.count >= 8 else { return [] }

        var flags = Array(repeating: false, count: pageLines.count)
        for (index, line) in pageLines.enumerated() {
            let needle = normalize(line.text)
            guard needle.count >= 8, haystack.contains(needle) else { continue }
            flags[index] = true
        }

        if flags.contains(true) {
            for index in 0..<pageLines.count where !flags[index] {
                let needle = normalize(pageLines[index].text)
                guard !needle.isEmpty, needle.count < 8 else { continue }
                let previousMatched = index > 0 && flags[index - 1]
                let nextMatched = index + 1 < flags.count && flags[index + 1]
                if previousMatched && nextMatched {
                    flags[index] = true
                }
            }
        }

        let matched = zip(pageLines, flags).compactMap { line, matched in
            matched ? line : nil
        }
        return PDFSelectionHeadingLeakFilter.stripEchoedHeadings(matched)
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{00ad}", with: "")
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PDFSelectionMarkupGeometry {
    static func make(
        selection: PDFSelection,
        document: PDFDocument
    ) -> [PDFPageMarkup] {
        let pages = pagesCovered(by: selection, in: document)
        let layouts = textLayouts(around: pages, in: document)

        var markups: [PDFPageMarkup] = []
        for page in pages {
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            let pageBounds = page.bounds(for: .cropBox)
            let cachedLines = layouts[pageIndex]?.lines
            let selectedLines = selectedLines(
                from: selection,
                on: page,
                pageBounds: pageBounds,
                cachedPageLines: cachedLines
            )
            guard !selectedLines.isEmpty else { continue }

            let neighbors = (-2...2).compactMap { delta -> PDFPageTextLayout? in
                guard delta != 0 else { return nil }
                return layouts[pageIndex + delta]
            }
            let bodyLines = PDFPageChromeFilter.bodyLines(
                selected: selectedLines,
                pageBounds: pageBounds,
                neighbors: neighbors
            )
            let contentLines = PDFSelectionHeadingLeakFilter.stripEchoedHeadings(bodyLines)
            guard !contentLines.isEmpty else { continue }

            let ordered = contentLines.sorted { lhs, rhs in
                if abs(lhs.rect.midY - rhs.rect.midY) > 1 {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhs.rect.minX < rhs.rect.minX
            }
            markups.append(
                PDFPageMarkup(
                    pageIndex: pageIndex,
                    lineRects: ordered.map(\.rect),
                    text: PDFSelectionHeadingLeakFilter.stripEchoedHeadings(
                        from: ordered
                            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    )
                )
            )
        }

        return markups
    }

    private static func textLayouts(
        around pages: [PDFPage],
        in document: PDFDocument
    ) -> [Int: PDFPageTextLayout] {
        var indexes = Set<Int>()
        for page in pages {
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            for delta in -2...2 {
                let neighbor = pageIndex + delta
                if neighbor >= 0, neighbor < document.pageCount {
                    indexes.insert(neighbor)
                }
            }
        }

        var layouts: [Int: PDFPageTextLayout] = [:]
        for index in indexes {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .cropBox)
            layouts[index] = PDFPageTextLayout(
                pageIndex: index,
                bounds: bounds,
                lines: allTextLines(on: page, bounds: bounds)
            )
        }
        return layouts
    }

    private static func pagesCovered(by selection: PDFSelection, in document: PDFDocument) -> [PDFPage] {
        var indexes = Set<Int>()

        func insert(_ page: PDFPage) {
            let index = document.index(for: page)
            guard index != NSNotFound else { return }
            indexes.insert(index)
        }

        selection.pages.forEach(insert)
        for line in selection.selectionsByLine() {
            line.pages.forEach(insert)
        }

        func pageLooksSelected(_ index: Int) -> Bool {
            guard let page = document.page(at: index) else { return false }
            let pageBounds = page.bounds(for: .cropBox)
            if !selectedLines(from: selection, on: page, pageBounds: pageBounds).isEmpty {
                return true
            }
            return hasVisibleSelectionBounds(selection, page: page, pageBounds: pageBounds)
        }

        if indexes.isEmpty {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let pageBounds = page.bounds(for: .cropBox)
                if hasVisibleSelectionBounds(selection, page: page, pageBounds: pageBounds) {
                    indexes.insert(index)
                }
            }
        } else {
            let seedMin = indexes.min() ?? 0
            let seedMax = indexes.max() ?? 0
            if seedMin > 0, pageLooksSelected(seedMin - 1) {
                indexes.insert(seedMin - 1)
            }
            if seedMax + 1 < document.pageCount, pageLooksSelected(seedMax + 1) {
                indexes.insert(seedMax + 1)
            }

            var grew = true
            var hops = 0
            while grew, hops < 32 {
                grew = false
                hops += 1
                if let maxIndex = indexes.max(),
                   maxIndex + 1 < document.pageCount,
                   pageLooksSelected(maxIndex + 1) {
                    indexes.insert(maxIndex + 1)
                    grew = true
                }
                if let minIndex = indexes.min(),
                   minIndex > 0,
                   pageLooksSelected(minIndex - 1) {
                    indexes.insert(minIndex - 1)
                    grew = true
                }
            }
        }

        return indexes.sorted().compactMap { document.page(at: $0) }
    }

    private static func hasVisibleSelectionBounds(
        _ selection: PDFSelection,
        page: PDFPage,
        pageBounds: CGRect
    ) -> Bool {
        let bounds = selection.bounds(for: page)
        guard !bounds.isEmpty, pageBounds.insetBy(dx: -2, dy: -2).intersects(bounds) else {
            return false
        }
        if selection.pages.contains(where: { $0 === page }) {
            return true
        }
        let covered = bounds.intersection(pageBounds)
        let coverage = (covered.width * covered.height) / max(pageBounds.width * pageBounds.height, 1)
        return coverage > 0 && coverage < 0.85
    }

    private static func selectedLines(
        from selection: PDFSelection,
        on page: PDFPage,
        pageBounds: CGRect,
        cachedPageLines: [PDFTextLine]? = nil
    ) -> [PDFTextLine] {
        let rawLines = selection.selectionsByLine()
        let lineSelections = rawLines.isEmpty ? [selection] : rawLines
        let belonging = lineSelections.compactMap { line -> PDFTextLine? in
            guard line.pages.contains(where: { $0 === page }) else { return nil }
            return textLine(from: line, on: page, pageBounds: pageBounds)
        }
        if !belonging.isEmpty {
            return belonging
        }

        let pageLines = cachedPageLines ?? allTextLines(on: page, bounds: pageBounds)
        let matched = PDFSelectionTextMatcher.matchingLines(
            selectedText: selection.string ?? "",
            pageLines: pageLines
        )
        if !matched.isEmpty {
            return matched
        }

        let bounds = selection.bounds(for: page).intersection(pageBounds)
        guard hasVisibleSelectionBounds(selection, page: page, pageBounds: pageBounds),
              !bounds.isEmpty,
              let local = page.selection(for: bounds) else { return [] }
        let localLines = local.selectionsByLine()
        let source = localLines.isEmpty ? [local] : localLines
        return source.compactMap { textLine(from: $0, on: page, pageBounds: pageBounds) }
    }

    private static func textLine(
        from selection: PDFSelection,
        on page: PDFPage,
        pageBounds: CGRect
    ) -> PDFTextLine? {
        let rect = selection.bounds(for: page)
        guard isUsableLineRect(rect, pageBounds: pageBounds) else { return nil }
        return PDFTextLine(rect: rect, text: selection.string ?? "")
    }

    private static func isUsableLineRect(_ rect: CGRect, pageBounds: CGRect) -> Bool {
        guard !rect.isEmpty, pageBounds.insetBy(dx: -2, dy: -2).intersects(rect) else {
            return false
        }
        return rect.height <= pageBounds.height * 0.45
    }

    private static func allTextLines(on page: PDFPage, bounds: CGRect) -> [PDFTextLine] {
        guard let pageSelection = page.selection(for: bounds) else { return [] }
        let lines = pageSelection.selectionsByLine()
        let source = lines.isEmpty ? [pageSelection] : lines
        return source.compactMap { line in
            textLine(from: line, on: page, pageBounds: bounds)
        }
    }
}
