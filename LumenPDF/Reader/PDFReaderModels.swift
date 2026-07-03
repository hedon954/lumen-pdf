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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.page == rhs.page && lhs.bounds == rhs.bounds
    }
}

struct UnderlineNoteDraft: Equatable {
    let word: String
    let boundsStr: String
    let page: Int
    let anchor: CGPoint
    let appendingNoteId: String?
    let existingNoteText: String
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
