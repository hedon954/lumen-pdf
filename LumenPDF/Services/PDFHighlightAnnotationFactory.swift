import AppKit
import PDFKit

enum PDFMarkupAppearance {
    /// Fixed sRGB keeps app-managed underlines visibly red on a white PDF page and avoids
    /// PDFKit falling back to its near-black default when annotations are rebuilt or undone.
    static let underlineColor = NSColor(
        srgbRed: 0.92,
        green: 0.10,
        blue: 0.12,
        alpha: 1
    )

    static func applyUnderline(to annotation: PDFAnnotation) {
        annotation.color = underlineColor
        annotation.markupType = .underline
    }
}

/// Builds PDFKit highlight annotations that match macOS Preview markup style.
enum PDFHighlightAnnotationFactory {
    /// Matches macOS Preview's highlighter, which uses the system "yellow" (a saturated goldenrod)
    /// at full strength. PDFKit renders the Highlight markup subtype with a multiply-style blend, so
    /// the underlying text stays readable even though the color is opaque.
    static let nativeHighlightColor = NSColor.systemYellow

    // MARK: - Creation

    /// Preferred path: build from a live or reconstructed PDFSelection.
    static func makeHighlight(
        from selection: PDFSelection,
        on page: PDFPage,
        color: NSColor = nativeHighlightColor,
        userName: String?,
        contents: String?
    ) -> PDFAnnotation? {
        makeHighlight(lineRects: lineRects(from: selection, on: page), color: color, userName: userName, contents: contents)
    }

    /// Fallback when only serialized bounds are available (vocabulary restore, stale menu action).
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
        // QuadPoints must be expressed relative to the annotation bounds origin. PDFKit then paints a
        // tight per-line highlight (matching macOS Preview) instead of filling the whole bounds rect.
        annotation.quadrilateralPoints = quadrilateralPoints(for: rects, relativeTo: union.origin)
        if let userName { annotation.userName = userName }
        if let contents { annotation.contents = contents }
        return annotation
    }

    // MARK: - Selection helpers

    static func lineRects(from selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        let lineSelections = selection.selectionsByLine()
        let lines = lineSelections.isEmpty ? [selection] : lineSelections
        return lines.compactMap { line in
            let rect = line.bounds(for: page)
            return rect.isEmpty ? nil : rect
        }
    }

    /// Reconstruct a PDFSelection from per-line rects (tight to glyphs, not axis-aligned guesswork).
    static func selection(from lineRects: [CGRect], on page: PDFPage) -> PDFSelection? {
        let pieces = lineRects.compactMap { rect -> PDFSelection? in
            guard !rect.isEmpty, rect != .zero else { return nil }
            return page.selection(for: rect)
        }
        guard !pieces.isEmpty else { return nil }
        if pieces.count == 1 { return pieces[0] }
        guard let document = page.document else { return pieces[0] }
        let combined = PDFSelection(document: document)
        combined.add(pieces)
        return combined
    }

    // MARK: - Matching / introspection

    static func lineRects(from annotation: PDFAnnotation) -> [CGRect] {
        if let quads = annotation.quadrilateralPoints, !quads.isEmpty {
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
            if !rects.isEmpty { return rects }
        }

        if let quadValues = annotation.value(forAnnotationKey: PDFAnnotationKey.quadPoints) as? [CGFloat],
           !quadValues.isEmpty {
            var rects: [CGRect] = []
            for index in stride(from: 0, to: quadValues.count, by: 8) {
                guard index + 7 < quadValues.count else { break }
                let xs = [quadValues[index], quadValues[index + 2], quadValues[index + 4], quadValues[index + 6]]
                let ys = [quadValues[index + 1], quadValues[index + 3], quadValues[index + 5], quadValues[index + 7]]
                let rect = CGRect(
                    x: xs.min() ?? 0,
                    y: ys.min() ?? 0,
                    width: (xs.max() ?? 0) - (xs.min() ?? 0),
                    height: (ys.max() ?? 0) - (ys.min() ?? 0)
                )
                if !rect.isEmpty { rects.append(rect) }
            }
            if !rects.isEmpty { return rects }
        }

        let bounds = annotation.bounds
        return bounds.isEmpty ? [] : [bounds]
    }

    /// `PDFAnnotation.type` reports a subtype name *without* the leading "/" that
    /// `PDFAnnotationSubtype.rawValue` includes (e.g. "Highlight" vs "/Highlight"). Comparing them
    /// directly silently matches nothing, so always go through this slash-insensitive check.
    static func matchesSubtype(_ annotation: PDFAnnotation, _ subtype: PDFAnnotationSubtype) -> Bool {
        func stripSlash(_ value: String) -> String { value.hasPrefix("/") ? String(value.dropFirst()) : value }
        return stripSlash(annotation.type ?? "") == stripSlash(subtype.rawValue)
    }

    static func isHighlightAnnotation(_ annotation: PDFAnnotation) -> Bool {
        matchesSubtype(annotation, .highlight) || annotation.markupType == .highlight
    }

    // MARK: - Quad geometry

    /// QuadPoints in annotation space (relative to bounds origin), four corners per line:
    /// top-left, top-right, bottom-left, bottom-right. Mirrors how `lineRects(from:)` reads them back.
    private static func quadrilateralPoints(for lineRects: [CGRect], relativeTo origin: CGPoint) -> [NSValue] {
        lineRects.flatMap { rect -> [NSValue] in
            [
                NSValue(point: CGPoint(x: rect.minX - origin.x, y: rect.maxY - origin.y)),
                NSValue(point: CGPoint(x: rect.maxX - origin.x, y: rect.maxY - origin.y)),
                NSValue(point: CGPoint(x: rect.minX - origin.x, y: rect.minY - origin.y)),
                NSValue(point: CGPoint(x: rect.maxX - origin.x, y: rect.minY - origin.y)),
            ]
        }
    }
}
