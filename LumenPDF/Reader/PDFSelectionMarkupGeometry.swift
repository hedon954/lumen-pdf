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

        return zip(pageLines, flags).compactMap { line, matched in
            matched ? line : nil
        }
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
            guard !bodyLines.isEmpty else { continue }

            let ordered = bodyLines.sorted { lhs, rhs in
                if abs(lhs.rect.midY - rhs.rect.midY) > 1 {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhs.rect.minX < rhs.rect.minX
            }
            markups.append(
                PDFPageMarkup(
                    pageIndex: pageIndex,
                    lineRects: ordered.map(\.rect),
                    text: ordered
                        .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
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
