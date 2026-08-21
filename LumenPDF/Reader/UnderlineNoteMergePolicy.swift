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
        (existing + [new])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func mergeAnnotationRects(_ rects: [CGRect]) -> [CGRect] {
        TextLineMarkupMerge.merge(rects)
    }
}
