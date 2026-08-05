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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.page == rhs.page && lhs.bounds == rhs.bounds
    }
}

struct UnderlineNoteDraft: Equatable {
    let word: String
    let boundsStr: String
    let page: Int
    let anchor: CGPoint
    let anchorRect: CGRect
    let appendingNoteId: String?
    let existingNoteText: String
}

struct ReadingOverlayPlacementInput: Equatable {
    let anchorRect: CGRect
    let overlaySize: CGSize
    let containerSize: CGSize
    let preferredGap: CGFloat
    let horizontalSafeInset: CGFloat
    let verticalSafeInset: CGFloat

    init(
        anchorRect: CGRect,
        overlaySize: CGSize,
        containerSize: CGSize,
        preferredGap: CGFloat,
        safeInset: CGFloat
    ) {
        self.init(
            anchorRect: anchorRect,
            overlaySize: overlaySize,
            containerSize: containerSize,
            preferredGap: preferredGap,
            horizontalSafeInset: safeInset,
            verticalSafeInset: safeInset
        )
    }

    init(
        anchorRect: CGRect,
        overlaySize: CGSize,
        containerSize: CGSize,
        preferredGap: CGFloat,
        horizontalSafeInset: CGFloat,
        verticalSafeInset: CGFloat
    ) {
        self.anchorRect = anchorRect
        self.overlaySize = overlaySize
        self.containerSize = containerSize
        self.preferredGap = preferredGap
        self.horizontalSafeInset = horizontalSafeInset
        self.verticalSafeInset = verticalSafeInset
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
}

enum ReadingOverlayPlacementPolicy {
    static func place(_ input: ReadingOverlayPlacementInput) -> ReadingOverlayPlacementResult {
        guard input.containerSize.width > 0, input.containerSize.height > 0 else {
            return ReadingOverlayPlacementResult(origin: .zero, placement: .leastOverlap)
        }

        let anchor = input.anchorRect
        let size = input.overlaySize
        let candidates = [
            ReadingOverlayPlacement.below,
            .above,
            .trailing,
            .leading
        ].map { placement in
            (placement, candidateOrigin(for: placement, input: input))
        }

        let evaluated = candidates.map { placement, origin in
            let clamped = clamp(
                origin: origin,
                overlaySize: size,
                containerSize: input.containerSize,
                horizontalSafeInset: input.horizontalSafeInset,
                verticalSafeInset: input.verticalSafeInset
            )
            let rect = CGRect(origin: clamped, size: size)
            let overlap = rect.intersection(anchor)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            return (placement: placement, origin: clamped, overlapArea: area)
        }

        if let clear = evaluated.first(where: { $0.overlapArea <= 0.5 }) {
            return ReadingOverlayPlacementResult(origin: clear.origin, placement: clear.placement)
        }

        let best = evaluated.min { lhs, rhs in lhs.overlapArea < rhs.overlapArea } ?? evaluated[0]
        return ReadingOverlayPlacementResult(origin: best.origin, placement: best.placement)
    }

    static func place(
        _ input: ReadingOverlayPlacementInput,
        keeping placement: ReadingOverlayPlacement
    ) -> ReadingOverlayPlacementResult {
        guard input.containerSize.width > 0, input.containerSize.height > 0,
              placement != .leastOverlap else {
            return place(input)
        }
        return ReadingOverlayPlacementResult(
            origin: clamp(
                origin: candidateOrigin(for: placement, input: input),
                overlaySize: input.overlaySize,
                containerSize: input.containerSize,
                horizontalSafeInset: input.horizontalSafeInset,
                verticalSafeInset: input.verticalSafeInset
            ),
            placement: placement
        )
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
        guard let first = lineRects.first,
              let last = lineRects.last,
              !first.isEmpty,
              !last.isEmpty,
              !containerRect.isEmpty else { return nil }

        let union = lineRects.dropFirst().reduce(first) { $0.union($1) }
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

struct TranslationBubbleRequest: Identifiable, Equatable {
    let id: UUID
    let word: String
    let sentence: String
    let bounds: CGRect
    let boundsStr: String
    let page: Int
    /// Selection bounds in the reader's SwiftUI coordinate space, used to keep
    /// the translation card from covering the selected text by default.
    let selectionAnchorRect: CGRect
    var result: TranslationResult?
    var translationError: String?
    /// Existing saved entry for the same word in the same context (word + sentence hash).
    /// When non-nil the bubble starts in a saved state and clicking the action removes it.
    var existingEntryId: String?
    /// True when the selection is a phrase/sentence and should be saved as a note
    /// instead of a vocabulary entry.
    let isSentenceMode: Bool

    init(
        id: UUID = UUID(),
        word: String,
        sentence: String,
        bounds: CGRect,
        boundsStr: String,
        page: Int,
        selectionAnchorRect: CGRect,
        result: TranslationResult? = nil,
        translationError: String? = nil,
        existingEntryId: String? = nil,
        isSentenceMode: Bool = false
    ) {
        self.id = id
        self.word = word
        self.sentence = sentence
        self.bounds = bounds
        self.boundsStr = boundsStr
        self.page = page
        self.selectionAnchorRect = selectionAnchorRect
        self.result = result
        self.translationError = translationError
        self.existingEntryId = existingEntryId
        self.isSentenceMode = isSentenceMode
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id &&
        lhs.word == rhs.word &&
        lhs.sentence == rhs.sentence &&
        lhs.bounds == rhs.bounds &&
        lhs.boundsStr == rhs.boundsStr &&
        lhs.page == rhs.page &&
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
}
