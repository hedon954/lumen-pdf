import CoreGraphics
import Foundation

/// Joins visual PDF lines into a paragraph before any sentence boundary is chosen.
enum ParagraphJoiner {
    struct Hit {
        let lines: [PDFTextLine]
        /// Index of the line the selection rectangle actually lands on.
        let anchorIndex: Int
    }

    static func paragraph(
        around lines: [PDFTextLine],
        selectionRect: CGRect
    ) -> Hit? {
        let ordered = orderedLines(lines)
        guard let anchor = anchorIndex(in: ordered, selectionRect: selectionRect) else {
            return nil
        }
        var start = anchor
        while start > 0, joinsDownward(ordered[start - 1], to: ordered[start], allowingShortUpper: true) {
            start -= 1
        }
        var end = anchor
        while end + 1 < ordered.count, joinsDownward(ordered[end], to: ordered[end + 1], allowingShortUpper: false) {
            end += 1
        }
        return Hit(lines: Array(ordered[start...end]), anchorIndex: anchor - start)
    }

    static func join(_ lines: [PDFTextLine]) -> String {
        var result = ""
        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if result.isEmpty {
                result = text
                continue
            }
            if result.hasSuffix("-"), let next = text.first, next.isLowercase {
                result.removeLast()
                result += text
            } else if index > 0 {
                result += " " + text
            }
        }
        return result
    }

    private static func orderedLines(_ lines: [PDFTextLine]) -> [PDFTextLine] {
        lines
            .map { PDFTextLine(rect: $0.rect, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
            .sorted { lhs, rhs in
                if abs(lhs.rect.midY - rhs.rect.midY) > 1 {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhs.rect.minX < rhs.rect.minX
            }
    }

    private static func anchorIndex(
        in lines: [PDFTextLine],
        selectionRect: CGRect
    ) -> Int? {
        guard !selectionRect.isNull, !selectionRect.isEmpty, selectionRect.width > 0, selectionRect.height > 0 else {
            return nil
        }
        let hits = lines.enumerated().filter {
            selectionRect.intersects($0.element.rect.insetBy(dx: -1, dy: -1))
        }
        return hits.max(by: { lhs, rhs in
            intersectionArea(lhs.element.rect, selectionRect)
                < intersectionArea(rhs.element.rect, selectionRect)
        })?.offset
    }

    private static func intersectionArea(_ line: CGRect, _ selection: CGRect) -> CGFloat {
        let hit = line.intersection(selection)
        guard !hit.isNull else { return 0 }
        return hit.width * hit.height
    }

    /// `upper` is the line above `lower` in PDF coordinates.
    /// A short upper line may start a paragraph, but a short upper line must not swallow the next paragraph.
    private static func joinsDownward(
        _ upper: PDFTextLine,
        to lower: PDFTextLine,
        allowingShortUpper: Bool
    ) -> Bool {
        let height = max(upper.rect.height, lower.rect.height, 8)
        let pitch = upper.rect.midY - lower.rect.midY
        guard pitch >= height * 0.5, pitch <= height * 1.8 else { return false }
        guard abs(upper.rect.height - lower.rect.height) <= height * 0.35 else { return false }
        let overlap = min(upper.rect.maxX, lower.rect.maxX) - max(upper.rect.minX, lower.rect.minX)
        guard overlap > 0 else { return false }
        if upper.text.hasSuffix("-"), let next = lower.text.first, next.isLowercase {
            return true
        }
        if allowingShortUpper {
            return abs(upper.rect.minX - lower.rect.minX) < height * 4
        }
        return upper.rect.width >= lower.rect.width * 0.9 || upper.rect.width >= height * 12
    }
}
