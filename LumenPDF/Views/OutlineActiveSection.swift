import Foundation

struct OutlineSectionCandidate: Equatable {
    var pageIndex: Int
    /// Outline order, parents before children and earlier siblings first.
    var order: Int
    /// Where the bookmark starts, in PDF page space. Larger values are higher on the page.
    /// A destination with no vertical target uses the top of that page.
    var destinationY: Double
}

struct OutlineReadingPosition: Equatable {
    var pageIndex: Int
    /// Top edge of the viewport in PDF page space.
    /// Nil before that edge has been measured; comparison then uses the page only.
    var topY: Double?
}

/// The current outline row is the last bookmark the viewport top has reached.
///
/// Bookmarks are ordered by destination, not by title. An earlier page comes first.
/// On the same page, a higher PDF y comes first. The viewport top is the same kind of
/// point: the page under the top edge, and that edge's y. A bookmark on an earlier
/// page is already reached. A bookmark on the current page is reached when its
/// destination is at or above that edge. Exact ties keep the later outline entry.
enum OutlineActiveSection {
    static func activeOrder(
        in items: [OutlineSectionCandidate],
        position: OutlineReadingPosition
    ) -> Int? {
        var best: OutlineSectionCandidate?
        for item in items where hasReached(item, position: position) {
            if let current = best {
                if isLater(item, than: current) { best = item }
            } else {
                best = item
            }
        }
        return best?.order
    }

    private static func hasReached(
        _ item: OutlineSectionCandidate,
        position: OutlineReadingPosition
    ) -> Bool {
        guard item.pageIndex >= 0 else { return false }
        if item.pageIndex < position.pageIndex { return true }
        guard item.pageIndex == position.pageIndex else { return false }
        guard let topY = position.topY else { return true }
        return item.destinationY >= topY
    }

    private static func isLater(
        _ item: OutlineSectionCandidate,
        than other: OutlineSectionCandidate
    ) -> Bool {
        if item.pageIndex != other.pageIndex {
            return item.pageIndex > other.pageIndex
        }
        if abs(item.destinationY - other.destinationY) > 0.5 {
            return item.destinationY < other.destinationY
        }
        return item.order > other.order
    }
}

enum OutlineDestinationPosition {
    /// PDF page space y where a bookmark starts.
    ///
    /// `/XYZ` destinations carry the point. A fit-page destination has no vertical
    /// target; PDFKit reports that as the zero point, and the bookmark then starts
    /// at the top of the page.
    static func startY(point: CGPoint?, pageMaxY: CGFloat) -> Double {
        guard let point, point != .zero else { return Double(pageMaxY) }
        return Double(point.y)
    }
}
