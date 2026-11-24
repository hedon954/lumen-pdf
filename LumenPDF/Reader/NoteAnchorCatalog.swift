import PDFKit

/// Builds note entry points from saved notes that actually have text.
/// Empty notes and free underlines without notes do not get a button.
/// One underline — including a selection that crosses pages — gets one button.
enum NoteAnchorCatalog {
    static func hasVisibleNoteText(_ note: NoteEntry) -> Bool {
        !NoteTextList.decode(note.note).isEmpty
    }

    static func savedNotes(_ notes: [NoteEntry]) -> [NoteAnchorRequest] {
        let withText = notes.filter(hasVisibleNoteText).sorted { $0.createdAt < $1.createdAt }
        var groups: [[NoteEntry]] = []
        for note in withText {
            let decoded = decodedMarkups(for: note)
            if let index = groups.firstIndex(where: { group in
                group.contains { member in
                    UnderlineNoteMergePolicy.markups(decoded, overlap: decodedMarkups(for: member))
                }
            }) {
                groups[index].append(note)
            } else {
                groups.append([note])
            }
        }
        return groups.compactMap { group in
            let combined = UnderlineNoteMergePolicy.mergePageMarkups(group.map(decodedMarkups(for:)))
            guard let placement = placementMarkup(in: combined, visiblePageIndices: nil) else {
                return nil
            }
            let noteId = group[0].id
            let id = "note-anchor|\(group.map(\.id).sorted().joined(separator: "+"))"
            return NoteAnchorRequest(
                id: id,
                noteId: noteId,
                pageIndex: placement.pageIndex,
                boundsStr: placement.boundsStr,
                pageMarkups: combined
            )
        }
    }

    /// Relocate each grouped note onto the last visible page of its underline.
    /// Free underlines without notes are not entry points.
    static func includingUnderlines(
        saved: [NoteAnchorRequest], visiblePages: [PDFPage], document: PDFDocument
    ) -> [NoteAnchorRequest] {
        let visible = Set(visiblePages.map { document.index(for: $0) })
        return saved.compactMap { placing($0, onVisiblePages: visible) }
    }

    static func placing(
        _ request: NoteAnchorRequest,
        onVisiblePages visible: Set<Int>
    ) -> NoteAnchorRequest? {
        let combined = request.pageMarkups.isEmpty
            ? [PDFPageMarkup(
                pageIndex: request.pageIndex,
                lineRects: AnnotationBoundsCodec.parse(request.boundsStr),
                text: ""
            )]
            : request.pageMarkups
        guard let placement = placementMarkup(in: combined, visiblePageIndices: visible) else {
            return nil
        }
        return NoteAnchorRequest(
            id: request.id,
            noteId: request.noteId,
            pageIndex: placement.pageIndex,
            boundsStr: placement.boundsStr,
            pageMarkups: combined
        )
    }

    static func decodedMarkups(for note: NoteEntry) -> [PDFPageMarkup] {
        PDFPageMarkupCodec.decode(
            note.pageMarkups,
            fallbackPage: Int(note.pageIndex),
            fallbackBoundsStr: note.boundsStr,
            fallbackText: note.content
        )
    }

    /// Last page of the underline that is currently visible; if visibility is
    /// unknown, the last page of the underline.
    static func placementMarkup(
        in markups: [PDFPageMarkup],
        visiblePageIndices: Set<Int>?
    ) -> PDFPageMarkup? {
        let candidates: [PDFPageMarkup]
        if let visiblePageIndices {
            candidates = markups.filter { visiblePageIndices.contains($0.pageIndex) }
        } else {
            candidates = markups
        }
        guard let lastPageIndex = candidates.map(\.pageIndex).max() else { return nil }
        let pageMarkups = candidates.filter { $0.pageIndex == lastPageIndex }
        let lineRects = pageMarkups.flatMap(\.lineRects)
        guard !lineRects.isEmpty else { return pageMarkups.first }
        return PDFPageMarkup(
            pageIndex: lastPageIndex,
            lineRects: lineRects,
            text: pageMarkups.first?.text ?? ""
        )
    }
}
