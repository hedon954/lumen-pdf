import CoreGraphics
import Foundation

extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }

    var expandedForComparison: CGRect {
        insetBy(dx: -1, dy: -1)
    }

    func isSameTextLine(as other: CGRect) -> Bool {
        let verticalOverlap = min(maxY, other.maxY) - max(minY, other.minY)
        return verticalOverlap > min(height, other.height) * 0.4
            || abs(midY - other.midY) <= max(height, other.height) * 0.5
    }
}

enum AnnotationBoundsCodec {
    static func parse(_ boundsStr: String) -> [CGRect] {
        boundsStr
            .split(separator: "|")
            .map(String.init)
            .map(NSRectFromString)
            .filter { !$0.isEmpty && $0 != .zero }
    }

    static func string(from rects: [CGRect]) -> String {
        rects.map { NSStringFromRect($0) }.joined(separator: "|")
    }
}
