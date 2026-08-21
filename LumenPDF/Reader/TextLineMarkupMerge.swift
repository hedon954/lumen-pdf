import CoreGraphics
import Foundation

/// Per-line interval algebra for free underline / highlight.
///
/// Markup overlap must not use the axis-aligned union of a multi-line selection.
/// Adjacent PDF line boxes often share a few points of vertical overlap, so that
/// union rectangle falsely intersects the previous line and deletes it.
///
/// Each text line is treated as a 1D interval `[minX, maxX]`. Overlap, merge, and
/// toggle-off are the standard interval union / difference used by text editors.
enum TextLineMarkupMerge {
    struct Plan: Equatable {
        /// Existing annotation groups that participate in this edit and should be removed.
        let interactingGroupIndices: [Int]
        /// Line rects to create after those groups are removed. Empty means toggle-off.
        let addRects: [CGRect]
    }

    /// Word-spacing gap that still counts as one run on the same line.
    static let adjacentGap: CGFloat = 8
    /// Ignore leftover slivers after a subtract.
    static let minimumWidth: CGFloat = 2

    static func plan(existingGroups: [[CGRect]], selection: [CGRect]) -> Plan {
        let selectionRects = normalized(selection)
        guard !selectionRects.isEmpty else {
            return Plan(interactingGroupIndices: [], addRects: [])
        }

        var interactingIndices: [Int] = []
        var interactingRects: [CGRect] = []
        for (index, group) in existingGroups.enumerated() {
            let rects = normalized(group)
            guard !rects.isEmpty, overlaps(rects, selectionRects) else { continue }
            interactingIndices.append(index)
            interactingRects.append(contentsOf: rects)
        }

        if interactingIndices.isEmpty {
            return Plan(interactingGroupIndices: [], addRects: selectionRects)
        }

        if isCovered(selectionRects, by: interactingRects) {
            return Plan(
                interactingGroupIndices: interactingIndices,
                addRects: subtracting(selectionRects, from: interactingRects)
            )
        }

        return Plan(
            interactingGroupIndices: interactingIndices,
            addRects: merge(interactingRects + selectionRects)
        )
    }

    static func merge(_ rects: [CGRect]) -> [CGRect] {
        lineClusters(from: normalized(rects)).flatMap { mergeIntervals(onLine: $0) }
    }

    static func overlaps(_ lhs: [CGRect], _ rhs: [CGRect]) -> Bool {
        lhs.contains { left in
            rhs.contains { right in
                left.isSameTextLine(as: right) && horizontallyTouches(left, right)
            }
        }
    }

    static func isCovered(_ selection: [CGRect], by existing: [CGRect]) -> Bool {
        !selection.isEmpty && selection.allSatisfy { candidate in
            existing.contains { piece in
                candidate.isSameTextLine(as: piece) && xRange(piece, expandedBy: 2).covers(xRange(candidate))
            }
        }
    }

    static func subtracting(_ selection: [CGRect], from existing: [CGRect]) -> [CGRect] {
        var remaining: [CGRect] = []
        for piece in normalized(existing) {
            var fragments = [piece]
            for cut in normalized(selection) where piece.isSameTextLine(as: cut) {
                fragments = fragments.flatMap { subtractX($0, cutting: cut) }
            }
            remaining.append(contentsOf: fragments)
        }
        return merge(remaining)
    }

    private static func normalized(_ rects: [CGRect]) -> [CGRect] {
        rects.filter { !$0.isEmpty && $0 != .zero && $0.width >= minimumWidth }
    }

    private static func lineClusters(from rects: [CGRect]) -> [[CGRect]] {
        let sorted = rects.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > max(lhs.height, rhs.height) * 0.6 {
                return lhs.midY > rhs.midY
            }
            return lhs.minX < rhs.minX
        }

        var clusters: [[CGRect]] = []
        for rect in sorted {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { $0.isSameTextLine(as: rect) }
            }) {
                clusters[index].append(rect)
            } else {
                clusters.append([rect])
            }
        }
        return clusters
    }

    private static func mergeIntervals(onLine rects: [CGRect]) -> [CGRect] {
        let sorted = rects.sorted { $0.minX < $1.minX }
        return sorted.reduce(into: [CGRect]()) { merged, rect in
            guard let last = merged.last, horizontallyTouches(last, rect) else {
                merged.append(rect)
                return
            }
            merged[merged.count - 1] = last.union(rect)
        }
    }

    private static func horizontallyTouches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let gap = max(lhs.minX, rhs.minX) - min(lhs.maxX, rhs.maxX)
        return gap <= adjacentGap
    }

    private static func subtractX(_ rect: CGRect, cutting cut: CGRect) -> [CGRect] {
        let overlapMin = max(rect.minX, cut.minX)
        let overlapMax = min(rect.maxX, cut.maxX)
        guard overlapMax - overlapMin > 0.5 else { return [rect] }

        var fragments: [CGRect] = []
        let leftWidth = overlapMin - rect.minX
        if leftWidth >= minimumWidth {
            fragments.append(CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height))
        }
        let rightWidth = rect.maxX - overlapMax
        if rightWidth >= minimumWidth {
            fragments.append(CGRect(x: overlapMax, y: rect.minY, width: rightWidth, height: rect.height))
        }
        return fragments
    }

    private static func xRange(_ rect: CGRect, expandedBy dx: CGFloat = 0) -> ClosedRange<CGFloat> {
        (rect.minX - dx)...(rect.maxX + dx)
    }
}

private extension ClosedRange where Bound == CGFloat {
    func covers(_ other: ClosedRange<CGFloat>) -> Bool {
        lowerBound <= other.lowerBound && upperBound >= other.upperBound
    }
}
