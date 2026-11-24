import Foundation

/// Whether a selection is already covered by a persisted free highlight.
enum FreeHighlightQuery {
    static func covers(markups: [PDFPageMarkup], filePath: String) -> Bool {
        let highlights = FreeMarkupStore.load(filePath).filter { $0.type == "highlight" }
        guard !markups.isEmpty else { return false }
        return markups.allSatisfy { markup in
            let existing = highlights
                .filter { $0.page == markup.pageIndex }
                .flatMap { AnnotationBoundsCodec.parse($0.boundsStr) }
            return TextLineMarkupMerge.isCovered(markup.lineRects, by: existing)
        }
    }
}
