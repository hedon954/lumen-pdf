import PDFKit
import XCTest
@testable import LumenPDF

final class NoteAnchorCatalogTests: XCTestCase {
    func testFreeUnderlineWithoutNoteHasNoEntryPoint() {
        let (document, page) = fixture()
        let requests = NoteAnchorCatalog.includingUnderlines(saved: [], visiblePages: [page], document: document)
        XCTAssertTrue(requests.isEmpty)
    }

    func testEmptyNoteHasNoEntryPoint() {
        let note = makeNote(id: "empty", note: "   ", pageMarkups: [singleMarkup(page: 0)])
        XCTAssertTrue(NoteAnchorCatalog.savedNotes([note]).isEmpty)
        XCTAssertFalse(NoteAnchorCatalog.hasVisibleNoteText(note))
    }

    func testJSONEmptyNoteHasNoEntryPoint() {
        let note = makeNote(id: "empty-json", note: "[]", pageMarkups: [singleMarkup(page: 0)])
        XCTAssertTrue(NoteAnchorCatalog.savedNotes([note]).isEmpty)
    }

    func testSavedNoteKeepsOneEntryPoint() {
        let (document, page) = fixture()
        let markup = singleMarkup(page: 0)
        let note = makeNote(id: "note", note: "remember this", pageMarkups: [markup])
        let saved = NoteAnchorCatalog.savedNotes([note])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.noteId, "note")
        let visible = NoteAnchorCatalog.includingUnderlines(
            saved: saved, visiblePages: [page], document: document
        )
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.pageIndex, 0)
    }

    func testOverlappingNotesShareOneEntryPoint() {
        let markup = singleMarkup(page: 0)
        let first = makeNote(id: "a", note: "first", pageMarkups: [markup], createdAt: 1)
        let second = makeNote(id: "b", note: "second", pageMarkups: [markup], createdAt: 2)
        let requests = NoteAnchorCatalog.savedNotes([first, second])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.noteId, "a")
    }

    func testStackedUnderlineLinesShareOneGroup() {
        let lines = [
            [CGRect(x: 48, y: 700, width: 400, height: 14)],
            [CGRect(x: 48, y: 682, width: 400, height: 14)],
            [CGRect(x: 48, y: 664, width: 360, height: 14)]
        ]

        XCTAssertEqual(NoteAnchorGrouping.clustered(lines).count, 1)
    }

    func testParagraphGapKeepsSeparateUnderlineGroups() {
        let lines = [
            [CGRect(x: 48, y: 700, width: 400, height: 14)],
            [CGRect(x: 48, y: 640, width: 400, height: 14)]
        ]

        XCTAssertEqual(NoteAnchorGrouping.clustered(lines).count, 2)
    }

    func testCrossPageNoteHasOneEntryPointOnTheLastVisiblePage() {
        let markups = [0, 1].map {
            PDFPageMarkup(pageIndex: $0, lineRects: [CGRect(x: 40, y: 70, width: 100, height: 18)], text: "page \($0)")
        }
        let note = makeNote(id: "note", note: "note", pageMarkups: markups)
        let requests = NoteAnchorCatalog.savedNotes([note])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.pageIndex, 1)
        XCTAssertEqual(requests.first?.pageMarkups.count, 2)

        let firstPageOnly = NoteAnchorCatalog.placing(requests[0], onVisiblePages: [0])
        XCTAssertEqual(firstPageOnly?.pageIndex, 0)

        let bothPages = NoteAnchorCatalog.placing(requests[0], onVisiblePages: [0, 1])
        XCTAssertEqual(bothPages?.pageIndex, 1)

        XCTAssertNil(NoteAnchorCatalog.placing(requests[0], onVisiblePages: [9]))
    }

    func testSeparateNotesKeepSeparateButtons() {
        let first = makeNote(
            id: "a",
            note: "one",
            pageMarkups: [PDFPageMarkup(pageIndex: 0, lineRects: [CGRect(x: 40, y: 400, width: 80, height: 14)], text: "a")]
        )
        let second = makeNote(
            id: "b",
            note: "two",
            pageMarkups: [PDFPageMarkup(pageIndex: 0, lineRects: [CGRect(x: 40, y: 100, width: 80, height: 14)], text: "b")]
        )
        XCTAssertEqual(NoteAnchorCatalog.savedNotes([first, second]).count, 2)
    }

    private func fixture() -> (PDFDocument, PDFPage) {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 600, height: 800), for: .mediaBox)
        document.insert(page, at: 0)
        let annotation = PDFAnnotation(bounds: CGRect(x: 40, y: 70, width: 100, height: 18), forType: .underline, withProperties: nil)
        annotation.userName = "__fu"
        page.addAnnotation(annotation)
        return (document, page)
    }

    private func singleMarkup(page: Int) -> PDFPageMarkup {
        PDFPageMarkup(pageIndex: page, lineRects: [CGRect(x: 40, y: 70, width: 100, height: 18)], text: "text")
    }

    private func makeNote(
        id: String,
        note: String,
        pageMarkups: [PDFPageMarkup],
        createdAt: Int64 = 0
    ) -> NoteEntry {
        NoteEntry(
            id: id,
            pdfPath: "/tmp/test.pdf",
            pdfName: "test.pdf",
            pageIndex: UInt32(pageMarkups.first?.pageIndex ?? 0),
            content: pageMarkups.first?.text ?? "",
            note: note,
            boundsStr: pageMarkups.first?.boundsStr ?? "",
            pageMarkups: PDFPageMarkupCodec.encode(pageMarkups),
            createdAt: createdAt
        )
    }
}
