import CoreGraphics
import Foundation

struct SelectionInfo: Equatable {
    let word: String
    let sentence: String
    /// Overall bounding box of the selection on the page (for menu anchor calculation only).
    let bounds: CGRect
    /// Pipe-separated per-line NSRect strings (e.g. "{x,y},{w,h}|{x,y},{w,h}").
    /// Using one rect per line avoids the large gap that spans between lines when a
    /// selection crosses a line break. Backward-compatible: single-line selections
    /// produce a string with no `|`.
    let boundsStr: String
    let page: Int
    /// Center of the action menu in SwiftUI coordinates (relative to PDFKitView's frame).
    let menuAnchor: CGPoint
    /// Selection bounds converted to SwiftUI coordinates (relative to PDFKitView's frame).
    let selectionAnchorRect: CGRect
    /// Body-text markups for every page covered by the selection.
    /// Running headers/footers are dropped when they repeat on neighboring pages.
    let pageMarkups: [PDFPageMarkup]

    var effectivePageMarkups: [PDFPageMarkup] {
        if pageMarkups.isEmpty {
            return [
                PDFPageMarkup(
                    pageIndex: page,
                    lineRects: AnnotationBoundsCodec.parse(boundsStr),
                    text: word
                )
            ]
        }
        return pageMarkups
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.page == rhs.page && lhs.bounds == rhs.bounds
    }
}

struct UnderlineNoteDraft: Equatable {
    let word: String
    let boundsStr: String
    let page: Int
    let pageMarkups: [PDFPageMarkup]
    let anchor: CGPoint
    let anchorRect: CGRect
    let appendingNoteId: String?
    let existingNoteText: String

    var effectivePageMarkups: [PDFPageMarkup] {
        if pageMarkups.isEmpty {
            return PDFPageMarkupCodec.decode(
                "",
                fallbackPage: page,
                fallbackBoundsStr: boundsStr,
                fallbackText: word
            )
        }
        return pageMarkups
    }
}

struct ReadingOverlayPlacementInput: Equatable {
    let anchorRect: CGRect
    let overlaySize: CGSize
    let containerSize: CGSize
    let preferredGap: CGFloat
    let horizontalSafeInset: CGFloat
    let verticalSafeInset: CGFloat
    let placementOrder: [ReadingOverlayPlacement]

    init(
        anchorRect: CGRect,
        overlaySize: CGSize,
        containerSize: CGSize,
        preferredGap: CGFloat,
        safeInset: CGFloat,
        placementOrder: [ReadingOverlayPlacement] = ReadingOverlayPlacement.defaultOrder
    ) {
        self.init(
            anchorRect: anchorRect,
            overlaySize: overlaySize,
            containerSize: containerSize,
            preferredGap: preferredGap,
            horizontalSafeInset: safeInset,
            verticalSafeInset: safeInset,
            placementOrder: placementOrder
        )
    }

    init(
        anchorRect: CGRect,
        overlaySize: CGSize,
        containerSize: CGSize,
        preferredGap: CGFloat,
        horizontalSafeInset: CGFloat,
        verticalSafeInset: CGFloat,
        placementOrder: [ReadingOverlayPlacement] = ReadingOverlayPlacement.defaultOrder
    ) {
        self.anchorRect = anchorRect
        self.overlaySize = overlaySize
        self.containerSize = containerSize
        self.preferredGap = preferredGap
        self.horizontalSafeInset = horizontalSafeInset
        self.verticalSafeInset = verticalSafeInset
        self.placementOrder = placementOrder
    }
}

struct ReadingOverlayPlacementResult: Equatable {
    let origin: CGPoint
    let placement: ReadingOverlayPlacement
}

enum ReadingOverlayPlacement: Equatable {
    case below
    case above
    case trailing
    case leading
    case leastOverlap

    static let defaultOrder: [ReadingOverlayPlacement] = [.below, .above, .trailing, .leading]
    static let lookUpOrder: [ReadingOverlayPlacement] = [.leading, .trailing, .above, .below]
}

enum ReadingOverlayPlacementPolicy {
    private static let overlapTolerance: CGFloat = 0.5

    static func place(_ input: ReadingOverlayPlacementInput) -> ReadingOverlayPlacementResult {
        guard input.containerSize.width > 0, input.containerSize.height > 0 else {
            return ReadingOverlayPlacementResult(origin: .zero, placement: .leastOverlap)
        }

        let candidates = input.placementOrder.map { evaluate($0, input: input) }

        if let clear = candidates.first(where: { $0.isClearAndOnExpectedSide }) {
            return ReadingOverlayPlacementResult(origin: clear.origin, placement: clear.placement)
        }

        let best = candidates.min(by: isBetterFallback) ?? candidates[0]
        return ReadingOverlayPlacementResult(origin: best.origin, placement: .leastOverlap)
    }

    static func place(
        _ input: ReadingOverlayPlacementInput,
        keeping placement: ReadingOverlayPlacement
    ) -> ReadingOverlayPlacementResult {
        guard input.containerSize.width > 0, input.containerSize.height > 0,
              placement != .leastOverlap else {
            return place(input)
        }
        // Keep the first chosen side even if later content growth overlaps the
        // selection. Recalculating a new side is what made translation windows jump.
        let candidate = evaluate(placement, input: input)
        return ReadingOverlayPlacementResult(origin: candidate.origin, placement: placement)
    }

    private struct EvaluatedCandidate {
        let placement: ReadingOverlayPlacement
        let origin: CGPoint
        let overlapArea: CGFloat
        let distanceFromAnchor: CGFloat
        let clampDistance: CGFloat
        let isOnExpectedSide: Bool

        var isClearAndOnExpectedSide: Bool {
            overlapArea <= ReadingOverlayPlacementPolicy.overlapTolerance && isOnExpectedSide
        }
    }

    private static func evaluate(
        _ placement: ReadingOverlayPlacement,
        input: ReadingOverlayPlacementInput
    ) -> EvaluatedCandidate {
        let proposed = candidateOrigin(for: placement, input: input)
        let origin = clamp(
            origin: proposed,
            overlaySize: input.overlaySize,
            containerSize: input.containerSize,
            horizontalSafeInset: input.horizontalSafeInset,
            verticalSafeInset: input.verticalSafeInset
        )
        let rect = CGRect(origin: origin, size: input.overlaySize)
        let overlap = rect.intersection(input.anchorRect)
        let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
        return EvaluatedCandidate(
            placement: placement,
            origin: origin,
            overlapArea: overlapArea,
            distanceFromAnchor: distance(between: rect, and: input.anchorRect),
            clampDistance: hypot(origin.x - proposed.x, origin.y - proposed.y),
            isOnExpectedSide: isOnExpectedSide(
                rect,
                of: input.anchorRect,
                placement: placement,
                gap: input.preferredGap
            )
        )
    }

    private static func isOnExpectedSide(
        _ rect: CGRect,
        of anchor: CGRect,
        placement: ReadingOverlayPlacement,
        gap: CGFloat
    ) -> Bool {
        switch placement {
        case .below:
            return rect.minY >= anchor.maxY + gap - overlapTolerance
        case .above:
            return rect.maxY <= anchor.minY - gap + overlapTolerance
        case .trailing:
            return rect.minX >= anchor.maxX + gap - overlapTolerance
        case .leading:
            return rect.maxX <= anchor.minX - gap + overlapTolerance
        case .leastOverlap:
            return false
        }
    }

    private static func distance(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
        let horizontal = max(max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX), 0)
        let vertical = max(max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY), 0)
        return hypot(horizontal, vertical)
    }

    private static func isBetterFallback(
        _ lhs: EvaluatedCandidate,
        _ rhs: EvaluatedCandidate
    ) -> Bool {
        if abs(lhs.overlapArea - rhs.overlapArea) > overlapTolerance {
            return lhs.overlapArea < rhs.overlapArea
        }
        if abs(lhs.distanceFromAnchor - rhs.distanceFromAnchor) > overlapTolerance {
            return lhs.distanceFromAnchor < rhs.distanceFromAnchor
        }
        if abs(lhs.clampDistance - rhs.clampDistance) > overlapTolerance {
            return lhs.clampDistance < rhs.clampDistance
        }
        return placementPriority(lhs.placement) < placementPriority(rhs.placement)
    }

    private static func placementPriority(_ placement: ReadingOverlayPlacement) -> Int {
        switch placement {
        case .below: 0
        case .above: 1
        case .trailing: 2
        case .leading: 3
        case .leastOverlap: 4
        }
    }

    private static func candidateOrigin(
        for placement: ReadingOverlayPlacement,
        input: ReadingOverlayPlacementInput
    ) -> CGPoint {
        let anchor = input.anchorRect
        let size = input.overlaySize
        let gap = input.preferredGap
        switch placement {
        case .below:
            return CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .above:
            return CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        case .trailing:
            return CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .leading:
            return CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        case .leastOverlap:
            return .zero
        }
    }

    static func clamp(origin: CGPoint, overlaySize: CGSize, containerSize: CGSize, safeInset: CGFloat) -> CGPoint {
        clamp(
            origin: origin,
            overlaySize: overlaySize,
            containerSize: containerSize,
            horizontalSafeInset: safeInset,
            verticalSafeInset: safeInset
        )
    }

    static func clamp(
        origin: CGPoint,
        overlaySize: CGSize,
        containerSize: CGSize,
        horizontalSafeInset: CGFloat,
        verticalSafeInset: CGFloat
    ) -> CGPoint {
        let maxX = max(horizontalSafeInset, containerSize.width - overlaySize.width - horizontalSafeInset)
        let maxY = max(verticalSafeInset, containerSize.height - overlaySize.height - verticalSafeInset)
        return CGPoint(
            x: min(max(origin.x, horizontalSafeInset), maxX),
            y: min(max(origin.y, verticalSafeInset), maxY)
        )
    }
}

struct ReadingOverlayEdgeInsets: Equatable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static let zero = ReadingOverlayEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

enum ReadingOverlayPointerGeometry {
    /// Matches the visual weight of macOS Preview / Look Up popover arrows.
    static let arrowBase: CGFloat = 28
    static let arrowDepth: CGFloat = 14
    static let cornerRadius: CGFloat = 16
    static let edgeInset: CGFloat = 20

    static func contentInsets(for placement: ReadingOverlayPlacement) -> ReadingOverlayEdgeInsets {
        switch placement {
        case .leading:
            return ReadingOverlayEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: arrowDepth)
        case .trailing:
            return ReadingOverlayEdgeInsets(top: 0, leading: arrowDepth, bottom: 0, trailing: 0)
        case .above:
            return ReadingOverlayEdgeInsets(top: 0, leading: 0, bottom: arrowDepth, trailing: 0)
        case .below, .leastOverlap:
            return ReadingOverlayEdgeInsets(top: arrowDepth, leading: 0, bottom: 0, trailing: 0)
        }
    }

    static func outerSize(body: CGSize, placement: ReadingOverlayPlacement) -> CGSize {
        switch placement {
        case .leading, .trailing:
            return CGSize(width: body.width + arrowDepth, height: body.height)
        case .above, .below, .leastOverlap:
            return CGSize(width: body.width, height: body.height + arrowDepth)
        }
    }

    static func bodySize(outer: CGSize, placement: ReadingOverlayPlacement) -> CGSize {
        switch placement {
        case .leading, .trailing:
            return CGSize(width: max(1, outer.width - arrowDepth), height: outer.height)
        case .above, .below, .leastOverlap:
            return CGSize(width: outer.width, height: max(1, outer.height - arrowDepth))
        }
    }

    static let arrowOverlap: CGFloat = 2

    /// Frame of the triangle in the outer overlay, including a small overlap
    /// onto the card so the arrow sits on the rounded rect instead of a gap.
    static func arrowFrame(
        overlaySize: CGSize,
        along: CGFloat,
        placement: ReadingOverlayPlacement
    ) -> CGRect {
        let depth = arrowDepth + arrowOverlap
        let base = arrowBase
        let center = along
        switch placement {
        case .leading:
            return CGRect(
                x: overlaySize.width - depth,
                y: center - base / 2,
                width: depth,
                height: base
            )
        case .trailing:
            return CGRect(
                x: 0,
                y: center - base / 2,
                width: depth,
                height: base
            )
        case .above:
            return CGRect(
                x: center - base / 2,
                y: overlaySize.height - depth,
                width: base,
                height: depth
            )
        case .below, .leastOverlap:
            return CGRect(
                x: center - base / 2,
                y: 0,
                width: base,
                height: depth
            )
        }
    }

    /// Distance along the facing edge from the overlay origin to the arrow center.
    static func alongEdge(
        anchorRect: CGRect,
        overlayOrigin: CGPoint,
        overlaySize: CGSize,
        placement: ReadingOverlayPlacement
    ) -> CGFloat {
        switch placement {
        case .leading, .trailing:
            let y = anchorRect.midY - overlayOrigin.y
            return min(max(y, edgeInset), max(edgeInset, overlaySize.height - edgeInset))
        case .above, .below, .leastOverlap:
            let x = anchorRect.midX - overlayOrigin.x
            return min(max(x, edgeInset), max(edgeInset, overlaySize.width - edgeInset))
        }
    }
}

/// Maps a saved reading position onto the PDFKit scroll view.
///
/// PDFKit re-lays out the document whenever the window frame, the split widths, or the
/// auto-scale factor change, so a position stored as a fraction of the document height lands
/// on a different page once the layout settles. Restoring from the document-space point that
/// was visible in the top-left corner keeps the same text on screen at any scale; the
/// normalized variant only exists for viewports saved before anchors were introduced.
enum ReaderViewportGeometry {
    static func maximumScrollOrigin(visibleSize: CGSize, documentSize: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, documentSize.width - visibleSize.width),
            y: max(0, documentSize.height - visibleSize.height)
        )
    }

    /// Document-space point currently shown in the top-left corner of the viewport.
    static func visibleTopLeft(of visibleRect: CGRect, isDocumentFlipped: Bool) -> CGPoint {
        CGPoint(
            x: visibleRect.minX,
            y: isDocumentFlipped ? visibleRect.minY : visibleRect.maxY
        )
    }

    /// Clip view origin that brings `topLeft` back to the top-left corner of the viewport.
    static func scrollOrigin(
        visibleTopLeft topLeft: CGPoint,
        visibleSize: CGSize,
        documentSize: CGSize,
        isDocumentFlipped: Bool
    ) -> CGPoint {
        let maximum = maximumScrollOrigin(visibleSize: visibleSize, documentSize: documentSize)
        let y = isDocumentFlipped ? topLeft.y : topLeft.y - visibleSize.height
        return CGPoint(
            x: min(max(topLeft.x, 0), maximum.x),
            y: min(max(y, 0), maximum.y)
        )
    }

    static func scrollOrigin(
        normalizedHorizontal: Double,
        normalizedVertical: Double,
        visibleSize: CGSize,
        documentSize: CGSize
    ) -> CGPoint {
        let maximum = maximumScrollOrigin(visibleSize: visibleSize, documentSize: documentSize)
        return CGPoint(
            x: CGFloat(unitFraction(normalizedHorizontal)) * maximum.x,
            y: CGFloat(unitFraction(normalizedVertical)) * maximum.y
        )
    }

    private static func unitFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct NoteAnchorRequest: Identifiable, Equatable {
    let id: String
    let noteId: String
    let pageIndex: Int
    let boundsStr: String
}

struct NoteAnchorPosition: Identifiable, Equatable {
    let id: String
    let noteId: String
    let pageIndex: Int
    let point: CGPoint
    let anchorRect: CGRect
}

enum NoteAnchorPlacement: Equatable {
    case trailing
    case above
    case below
    case leading
    case upperTrailingFallback
}

struct NoteAnchorPlacementResult: Equatable {
    let point: CGPoint
    let placement: NoteAnchorPlacement
}

/// Places the compact note button around marked text without covering readable content.
///
/// Normal candidates are accepted only when the complete button fits in the viewport and
/// does not intersect any text line on the page. When a selection sits in the middle of a
/// dense paragraph and every side is occupied, the explicit fallback keeps the button just
/// after the final glyph and lifts it into the gap between lines.
enum NoteAnchorPlacementPolicy {
    static func place(
        lineRects: [CGRect],
        textRects: [CGRect],
        containerRect: CGRect,
        buttonSize: CGFloat = 28,
        gap: CGFloat = 6
    ) -> NoteAnchorPlacementResult? {
        let orderedLineRects = lineRects
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if abs(lhs.midY - rhs.midY) > 1 {
                    return lhs.minY < rhs.minY
                }
                return lhs.minX < rhs.minX
            }
        guard let first = orderedLineRects.first,
              let last = orderedLineRects.last,
              !first.isEmpty,
              !last.isEmpty,
              !containerRect.isEmpty else { return nil }

        let union = orderedLineRects.dropFirst().reduce(first) { $0.union($1) }
        let radius = buttonSize / 2
        let candidates: [(NoteAnchorPlacement, CGPoint)] = [
            (.trailing, CGPoint(x: last.maxX + gap + radius, y: last.midY)),
            (.above, CGPoint(x: union.midX, y: union.minY - gap - radius)),
            (.below, CGPoint(x: union.midX, y: union.maxY + gap + radius)),
            (.leading, CGPoint(x: first.minX - gap - radius, y: first.midY))
        ]

        if let clear = candidates.first(where: { _, point in
            let buttonRect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: buttonSize,
                height: buttonSize
            )
            return containerRect.contains(buttonRect) && !textRects.contains(where: {
                $0.intersects(buttonRect.insetBy(dx: -1, dy: -1))
            })
        }) {
            return NoteAnchorPlacementResult(point: clear.1, placement: clear.0)
        }

        let fallback = CGPoint(
            x: last.maxX + gap + radius,
            y: last.minY - 2
        )
        return NoteAnchorPlacementResult(
            point: clamp(fallback, radius: radius, to: containerRect),
            placement: .upperTrailingFallback
        )
    }

    private static func clamp(_ point: CGPoint, radius: CGFloat, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX + radius), rect.maxX - radius),
            y: min(max(point.y, rect.minY + radius), rect.maxY - radius)
        )
    }
}

struct ActiveNoteReview: Identifiable {
    let id: String
    let anchor: NoteAnchorPosition
    let notes: [NoteEntry]
}

/// Ephemeral PDF selection styling while the translation popover is visible.
/// It is deliberately narrower than `TranslationBubbleRequest`: PDFKit only
/// receives the identity, document, and page geometry it needs to draw.
struct TranslationSelectionEmphasis: Equatable {
    let id: UUID
    let filePath: String
    let pageMarkups: [PDFPageMarkup]
}

struct TranslationBubbleRequest: Identifiable, Equatable {
    let id: UUID
    let pdfPath: String
    let pdfName: String
    let word: String
    let sentence: String
    let sentenceHash: String
    let bounds: CGRect
    let boundsStr: String
    let page: Int
    let pageMarkups: [PDFPageMarkup]
    /// Selection bounds in the reader-root coordinate space. The root overlay
    /// converts this to its local space before placing the pointer.
    let selectionAnchorRect: CGRect
    var result: TranslationResult?
    var translationError: String?
    /// Existing saved entry for the same word in the same context (word + sentence hash).
    /// When non-nil the bubble starts in a saved state and clicking the action removes it.
    var existingEntryId: String?
    /// True when the selection is a phrase/sentence and should be saved as a note
    /// instead of a vocabulary entry.
    let isSentenceMode: Bool

    var effectivePageMarkups: [PDFPageMarkup] {
        if pageMarkups.isEmpty {
            return PDFPageMarkupCodec.decode(
                "",
                fallbackPage: page,
                fallbackBoundsStr: boundsStr,
                fallbackText: word
            )
        }
        return pageMarkups
    }

    init(
        id: UUID = UUID(),
        pdfPath: String,
        pdfName: String,
        word: String,
        sentence: String,
        sentenceHash: String,
        bounds: CGRect,
        boundsStr: String,
        page: Int,
        pageMarkups: [PDFPageMarkup] = [],
        selectionAnchorRect: CGRect,
        result: TranslationResult? = nil,
        translationError: String? = nil,
        existingEntryId: String? = nil,
        isSentenceMode: Bool = false
    ) {
        self.id = id
        self.pdfPath = pdfPath
        self.pdfName = pdfName
        self.word = word
        self.sentence = sentence
        self.sentenceHash = sentenceHash
        self.bounds = bounds
        self.boundsStr = boundsStr
        self.page = page
        self.pageMarkups = pageMarkups
        self.selectionAnchorRect = selectionAnchorRect
        self.result = result
        self.translationError = translationError
        self.existingEntryId = existingEntryId
        self.isSentenceMode = isSentenceMode
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id &&
        lhs.pdfPath == rhs.pdfPath &&
        lhs.pdfName == rhs.pdfName &&
        lhs.word == rhs.word &&
        lhs.sentence == rhs.sentence &&
        lhs.sentenceHash == rhs.sentenceHash &&
        lhs.bounds == rhs.bounds &&
        lhs.boundsStr == rhs.boundsStr &&
        lhs.page == rhs.page &&
        lhs.pageMarkups == rhs.pageMarkups &&
        lhs.selectionAnchorRect == rhs.selectionAnchorRect &&
        lhs.result == rhs.result &&
        lhs.translationError == rhs.translationError &&
        lhs.existingEntryId == rhs.existingEntryId &&
        lhs.isSentenceMode == rhs.isSentenceMode
    }
}

struct NoteUndoInfo {
    let id: String
    let pdfPath: String
    let pdfName: String
    let pageIndex: UInt32
    let content: String
    let note: String
    let boundsStr: String
    let pageMarkups: [PDFPageMarkup]
    let createdAt: Int64

    init(_ entry: NoteEntry) {
        id = entry.id
        pdfPath = entry.pdfPath
        pdfName = entry.pdfName
        pageIndex = entry.pageIndex
        content = entry.content
        note = entry.note
        boundsStr = entry.boundsStr
        pageMarkups = PDFPageMarkupCodec.decode(
            entry.pageMarkups,
            fallbackPage: Int(entry.pageIndex),
            fallbackBoundsStr: entry.boundsStr,
            fallbackText: entry.content
        )
        createdAt = entry.createdAt
    }

    var entry: NoteEntry {
        NoteEntry(
            id: id,
            pdfPath: pdfPath,
            pdfName: pdfName,
            pageIndex: pageIndex,
            content: content,
            note: note,
            boundsStr: boundsStr,
            pageMarkups: PDFPageMarkupCodec.encode(pageMarkups),
            createdAt: createdAt
        )
    }
}
