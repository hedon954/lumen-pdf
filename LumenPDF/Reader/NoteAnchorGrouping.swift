import CoreGraphics

/// One continuous underline keeps a single note button.
///
/// Older saves stored each line of one underline as its own annotation, so a three-line
/// stroke showed three buttons. Lines that sit on the next text row belong to that same
/// stroke; a paragraph gap starts another one.
enum NoteAnchorGrouping {
    static func clustered(_ groups: [[CGRect]]) -> [[CGRect]] {
        let sorted = groups
            .map { $0.filter { !$0.isEmpty && $0 != .zero } }
            .filter { !$0.isEmpty }
            .sorted { top($0) > top($1) }
        var clusters: [[CGRect]] = []
        for group in sorted {
            if let index = clusters.indices.last, continues(clusters[index], group) {
                clusters[index].append(contentsOf: group)
            } else {
                clusters.append(group)
            }
        }
        return clusters
    }

    static func continues(_ existing: [CGRect], _ incoming: [CGRect]) -> Bool {
        existing.contains { lhs in
            incoming.contains { rhs in sameStroke(lhs, rhs) }
        }
    }

    static func sameStroke(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let upper = lhs.maxY >= rhs.maxY ? lhs : rhs
        let lower = lhs.maxY >= rhs.maxY ? rhs : lhs
        let gap = upper.minY - lower.maxY
        let lineHeight = max(upper.height, lower.height, 8)
        guard gap <= lineHeight * 0.85 else { return false }
        let overlap = min(upper.maxX, lower.maxX) - max(upper.minX, lower.minX)
        if overlap > 4 { return true }
        return abs(upper.minX - lower.minX) <= 28
    }

    private static func top(_ rects: [CGRect]) -> CGFloat {
        rects.map(\.maxY).max() ?? 0
    }
}
