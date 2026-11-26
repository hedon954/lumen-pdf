import CoreGraphics
import Foundation
import PDFKit

/// The pointer positions that created a drag selection.
/// PDFKit's `PDFSelection` drops the first page of a drag that crosses a page
/// boundary. The two points are the selection; the reported object is not.
struct PDFSelectionGesture: Equatable {
    var startPage: Int
    var startPoint: CGPoint
    var endPage: Int
    var endPoint: CGPoint

    var crossesPages: Bool { startPage != endPage }
}

enum PDFReadingSelection {
    /// Uses the reported selection when it already contains every page the
    /// drag touched. Rebuilds from the two points when a page is missing.
    static func materialize(
        reported: PDFSelection,
        document: PDFDocument,
        gesture: PDFSelectionGesture?
    ) -> PDFSelection {
        guard let gesture, gesture.crossesPages,
              let rebuilt = rebuild(gesture, in: document) else {
            return reported
        }
        let reportedPages = pageIndexes(in: reported, document: document)
        let first = min(gesture.startPage, gesture.endPage)
        let last = max(gesture.startPage, gesture.endPage)
        let touched = Set(first...last)
        if !touched.isSubset(of: reportedPages) {
            return rebuilt
        }
        if let page = document.page(at: first),
           reported.numberOfTextRanges(on: page) == 0,
           rebuilt.numberOfTextRanges(on: page) > 0 {
            return rebuilt
        }
        return reported
    }

    private static func pageIndexes(in selection: PDFSelection, document: PDFDocument) -> Set<Int> {
        var indexes = Set<Int>()
        for page in selection.pages {
            let index = document.index(for: page)
            if index != NSNotFound { indexes.insert(index) }
        }
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let index = document.index(for: page)
                if index != NSNotFound { indexes.insert(index) }
            }
        }
        return indexes
    }

    private static func rebuild(
        _ gesture: PDFSelectionGesture,
        in document: PDFDocument
    ) -> PDFSelection? {
        let firstIndex = min(gesture.startPage, gesture.endPage)
        let lastIndex = max(gesture.startPage, gesture.endPage)
        guard firstIndex != lastIndex,
              firstIndex >= 0,
              lastIndex < document.pageCount else { return nil }
        let firstPoint = gesture.startPage == firstIndex ? gesture.startPoint : gesture.endPoint
        let lastPoint = gesture.endPage == lastIndex ? gesture.endPoint : gesture.startPoint

        let combined = PDFSelection(document: document)
        var added = false
        if let page = document.page(at: firstIndex),
           let end = textEndpoint(on: page, atStart: false),
           let selection = page.selection(from: firstPoint, to: end) {
            combined.add(selection)
            added = true
        }
        if lastIndex - firstIndex > 1 {
            for index in (firstIndex + 1)..<lastIndex {
                guard let page = document.page(at: index),
                      let start = textEndpoint(on: page, atStart: true),
                      let end = textEndpoint(on: page, atStart: false),
                      let selection = page.selection(from: start, to: end) else { continue }
                combined.add(selection)
                added = true
            }
        }
        if let page = document.page(at: lastIndex),
           let start = textEndpoint(on: page, atStart: true),
           let selection = page.selection(from: start, to: lastPoint) {
            combined.add(selection)
            added = true
        }
        guard added, combined.string?.isEmpty == false else { return nil }
        return combined
    }

    /// A point on the first or last text line. `selection(from:to:)` needs a
    /// point that actually sits on a glyph, not the page corner.
    private static func textEndpoint(on page: PDFPage, atStart: Bool) -> CGPoint? {
        let bounds = page.bounds(for: .cropBox)
        guard let whole = page.selection(for: bounds) else { return nil }
        let lines = whole.selectionsByLine()
        let source = lines.isEmpty ? [whole] : lines
        let usable = source.compactMap { line -> CGRect? in
            let rect = line.bounds(for: page)
            guard !rect.isEmpty, !rect.isNull, rect.height < bounds.height * 0.45 else { return nil }
            return rect
        }
        guard !usable.isEmpty else { return nil }
        if atStart, let top = usable.max(by: { $0.midY < $1.midY }) {
            return CGPoint(x: top.minX + 1, y: top.midY)
        }
        if let bottom = usable.min(by: { $0.midY < $1.midY }) {
            return CGPoint(x: max(bottom.minX + 1, bottom.maxX - 1), y: bottom.midY)
        }
        return nil
    }
}
