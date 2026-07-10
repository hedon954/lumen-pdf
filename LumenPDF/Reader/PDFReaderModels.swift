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
    let safeInset: CGFloat
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
        let gap = input.preferredGap
        let candidates: [(ReadingOverlayPlacement, CGPoint)] = [
            (.below, CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)),
            (.above, CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)),
            (.trailing, CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)),
            (.leading, CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2))
        ]

        let evaluated = candidates.map { placement, origin in
            let clamped = clamp(origin: origin, overlaySize: size, containerSize: input.containerSize, safeInset: input.safeInset)
            let rect = CGRect(origin: clamped, size: size)
            let overlap = rect.intersection(anchor)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            return (placement: placement, origin: clamped, overlapArea: area)
        }

        if let clear = evaluated.first(where: { $0.overlapArea <= 0.5 }) {
            return ReadingOverlayPlacementResult(origin: clear.origin, placement: clear.placement)
        }

        let best = evaluated.min { lhs, rhs in lhs.overlapArea < rhs.overlapArea } ?? evaluated[0]
        return ReadingOverlayPlacementResult(origin: best.origin, placement: .leastOverlap)
    }

    static func clamp(origin: CGPoint, overlaySize: CGSize, containerSize: CGSize, safeInset: CGFloat) -> CGPoint {
        let maxX = max(safeInset, containerSize.width - overlaySize.width - safeInset)
        let maxY = max(safeInset, containerSize.height - overlaySize.height - safeInset)
        return CGPoint(
            x: min(max(origin.x, safeInset), maxX),
            y: min(max(origin.y, safeInset), maxY)
        )
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
