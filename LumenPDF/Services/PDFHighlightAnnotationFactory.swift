import AppKit
import PDFKit

/// Builds PDFKit highlight annotations that match macOS Preview markup style.
enum PDFHighlightAnnotationFactory {
    /// Default yellow used by Preview / PDFKit native highlights.
    static let nativeHighlightColor = NSColor(srgbRed: 1, green: 0.97, blue: 0, alpha: 1)

    /// Create one native-style highlight annotation covering all line rects.
    static func makeHighlight(
        lineRects: [CGRect],
        color: NSColor = nativeHighlightColor,
        userName: String?,
        contents: String?
    ) -> PDFAnnotation? {
        let rects = lineRects.filter { !$0.isEmpty && $0 != .zero }
        guard !rects.isEmpty else { return nil }

        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let annotation = PDFAnnotation(bounds: union, forType: .highlight, withProperties: nil)
        annotation.color = color
        annotation.markupType = .highlight
        annotation.quadrilateralPoints = quadrilateralPoints(for: rects, relativeTo: union)
        if let userName { annotation.userName = userName }
        if let contents { annotation.contents = contents }
        return annotation
    }

    /// Reconstruct per-line rects from a highlight annotation (for toggle / undo).
    static func lineRects(from annotation: PDFAnnotation) -> [CGRect] {
        guard let quads = annotation.quadrilateralPoints, !quads.isEmpty else {
            let bounds = annotation.bounds
            return bounds.isEmpty ? [] : [bounds]
        }

        let origin = annotation.bounds.origin
        var rects: [CGRect] = []
        let points = quads.map(\.pointValue)

        for index in stride(from: 0, to: points.count, by: 4) {
            guard index + 3 < points.count else { break }
            let xs = [
                points[index].x + origin.x,
                points[index + 1].x + origin.x,
                points[index + 2].x + origin.x,
                points[index + 3].x + origin.x,
            ]
            let ys = [
                points[index].y + origin.y,
                points[index + 1].y + origin.y,
                points[index + 2].y + origin.y,
                points[index + 3].y + origin.y,
            ]
            let rect = CGRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0)
            )
            if !rect.isEmpty { rects.append(rect) }
        }

        return rects.isEmpty ? [annotation.bounds] : rects
    }

    static func quadrilateralPoints(for lineRects: [CGRect], relativeTo union: CGRect) -> [NSValue] {
        lineRects.flatMap { rect -> [NSValue] in
            let rel = rect.offsetBy(dx: -union.origin.x, dy: -union.origin.y)
            // Z-pattern: upper-left, upper-right, lower-left, lower-right (page space).
            let upperLeft = NSValue(point: CGPoint(x: rel.minX, y: rel.maxY))
            let upperRight = NSValue(point: CGPoint(x: rel.maxX, y: rel.maxY))
            let lowerLeft = NSValue(point: CGPoint(x: rel.minX, y: rel.minY))
            let lowerRight = NSValue(point: CGPoint(x: rel.maxX, y: rel.minY))
            return [upperLeft, upperRight, lowerLeft, lowerRight]
        }
    }
}
