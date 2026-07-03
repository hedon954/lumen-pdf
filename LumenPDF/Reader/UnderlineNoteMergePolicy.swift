import CoreGraphics
import Foundation

enum UnderlineNoteMergePolicy {
    static func rects(_ candidates: [CGRect], areCoveredBy existing: [CGRect]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { candidate in
            existing.contains { $0.expandedForComparison.contains(candidate) }
        }
    }

    static func rects(_ lhs: [CGRect], overlap rhs: [CGRect]) -> Bool {
        lhs.contains { left in
            rhs.contains { right in
                left.intersection(right).area > 1.0
            }
        }
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
        let sortedRects = rects
            .filter { !$0.isEmpty && $0 != .zero }
            .sorted { lhs, rhs in
                if abs(lhs.midY - rhs.midY) > max(lhs.height, rhs.height) * 0.6 {
                    return lhs.midY > rhs.midY
                }
                return lhs.minX < rhs.minX
            }

        return sortedRects.reduce(into: [CGRect]()) { merged, rect in
            guard let index = merged.firstIndex(where: { $0.isSameTextLine(as: rect) && $0.expandedForComparison.intersects(rect.expandedForComparison) }) else {
                merged.append(rect)
                return
            }
            merged[index] = merged[index].union(rect)
        }
    }
}
