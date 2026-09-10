import PDFKit

/// Builds note entry points from saved notes and visible free underlines.
/// A free underline remains actionable before the first note has been written.
enum NoteAnchorCatalog {
    static func savedNotes(_ notes: [NoteEntry]) -> [NoteAnchorRequest] {
        var seen = Set<String>()
        return notes.sorted { $0.createdAt < $1.createdAt }.flatMap { note in
            PDFPageMarkupCodec.decode(
                note.pageMarkups, fallbackPage: Int(note.pageIndex),
                fallbackBoundsStr: note.boundsStr, fallbackText: note.content
            ).compactMap { markup in
                let key = "note-anchor|\(markup.pageIndex)|\(markup.boundsStr)"
                guard seen.insert(key).inserted else { return nil }
                return NoteAnchorRequest(id: key, noteId: note.id,
                                         pageIndex: markup.pageIndex, boundsStr: markup.boundsStr)
            }
        }
    }

    static func includingUnderlines(
        saved: [NoteAnchorRequest], visiblePages: [PDFPage], document: PDFDocument
    ) -> [NoteAnchorRequest] {
        var requests = saved
        for page in visiblePages {
            let pageIndex = document.index(for: page)
            for annotation in page.annotations where annotation.userName == "__fu" {
                let rects = PDFHighlightAnnotationFactory.lineRects(from: annotation)
                let markup = PDFPageMarkup(pageIndex: pageIndex, lineRects: rects, text: "")
                guard !rects.isEmpty else { continue }
                let overlapsSaved = saved.contains { request in
                    guard request.pageIndex == pageIndex else { return false }
                    let existing = PDFPageMarkup(
                        pageIndex: pageIndex,
                        lineRects: AnnotationBoundsCodec.parse(request.boundsStr), text: ""
                    )
                    return UnderlineNoteMergePolicy.markups([markup], overlap: [existing])
                }
                guard !overlapsSaved else { continue }
                requests.append(NoteAnchorRequest(
                    id: "underline-note|\(pageIndex)|\(markup.boundsStr)", noteId: "",
                    pageIndex: pageIndex, boundsStr: markup.boundsStr
                ))
            }
        }
        return requests
    }
}
