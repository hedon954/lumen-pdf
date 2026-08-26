import CoreGraphics
import Foundation

enum UnderlineNoteMergePolicy {
    static func rects(_ candidates: [CGRect], areCoveredBy existing: [CGRect]) -> Bool {
        TextLineMarkupMerge.isCovered(candidates, by: existing)
    }

    static func rects(_ lhs: [CGRect], overlap rhs: [CGRect]) -> Bool {
        TextLineMarkupMerge.overlaps(lhs, rhs)
    }

    static func mergedNoteContent(existing: [String], new: String) -> String {
        let normalizedNew = ContextSentenceFormatting.displayParagraph(new)
        let existingParagraphs = existing.map(ContextSentenceFormatting.displayParagraph)
        if existingParagraphs.contains(where: { normalizedNew.contains($0) }) {
            return normalizedNew
        }
        if let containingExisting = existingParagraphs.first(where: { $0.contains(normalizedNew) }) {
            return containingExisting
        }
        return (existingParagraphs + [normalizedNew])
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }

    static func mergedNoteText(existing: [String], new: String) -> String {
        NoteTextList.encode(
            existing.flatMap(NoteTextList.decode) + NoteTextList.decode(new)
        )
    }

    static func mergeAnnotationRects(_ rects: [CGRect]) -> [CGRect] {
        TextLineMarkupMerge.merge(rects)
    }

    static func markups(_ candidates: [PDFPageMarkup], areCoveredBy existing: [PDFPageMarkup]) -> Bool {
        let existingByPage = Dictionary(grouping: existing, by: \.pageIndex)
        return !candidates.isEmpty && candidates.allSatisfy { candidate in
            let pageRects = existingByPage[candidate.pageIndex]?.flatMap(\.lineRects) ?? []
            return rects(candidate.lineRects, areCoveredBy: pageRects)
        }
    }

    static func markups(_ lhs: [PDFPageMarkup], overlap rhs: [PDFPageMarkup]) -> Bool {
        let rhsByPage = Dictionary(grouping: rhs, by: \.pageIndex)
        return lhs.contains { candidate in
            let pageRects = rhsByPage[candidate.pageIndex]?.flatMap(\.lineRects) ?? []
            return rects(candidate.lineRects, overlap: pageRects)
        }
    }

    static func sameGeometry(_ lhs: [PDFPageMarkup], _ rhs: [PDFPageMarkup]) -> Bool {
        geometrySignature(lhs) == geometrySignature(rhs)
    }

    static func mergePageMarkups(_ groups: [[PDFPageMarkup]]) -> [PDFPageMarkup] {
        PDFPageMarkupCodec.normalized(groups.flatMap { $0 })
    }

    private static func geometrySignature(_ markups: [PDFPageMarkup]) -> [String] {
        PDFPageMarkupCodec.normalized(markups).map {
            "\($0.pageIndex):\($0.boundsStr)"
        }
    }
}
