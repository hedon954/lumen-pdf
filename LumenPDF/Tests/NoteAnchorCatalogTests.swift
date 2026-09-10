import PDFKit
import XCTest
@testable import LumenPDF

final class NoteAnchorCatalogTests: XCTestCase {
    func testFreeUnderlineHasAnEntryPointBeforeANoteIsSaved() {
        let (document, page) = fixture()
        let requests = NoteAnchorCatalog.includingUnderlines(saved: [], visiblePages: [page], document: document)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.noteId, "")
        XCTAssertEqual(requests.first?.pageIndex, 0)
        XCTAssertFalse(requests.first!.boundsStr.isEmpty)
    }

    func testSavedNoteReplacesFreeUnderlineEntryAtSameGeometry() {
        let (document, page) = fixture()
        let free = NoteAnchorCatalog.includingUnderlines(saved: [], visiblePages: [page], document: document)[0]
        let saved = NoteAnchorRequest(id: "saved", noteId: "note", pageIndex: 0, boundsStr: free.boundsStr)
        let requests = NoteAnchorCatalog.includingUnderlines(saved: [saved], visiblePages: [page], document: document)
        XCTAssertEqual(requests, [saved])
    }

    func testCrossPageNoteHasAnEntryPointOnBothPages() {
        let markups = [0, 1].map {
            PDFPageMarkup(pageIndex: $0, lineRects: [CGRect(x: 40, y: 70, width: 100, height: 18)], text: "page \($0)")
        }
        let note = NoteEntry(id: "note", pdfPath: "/tmp/test.pdf", pdfName: "test.pdf",
                             pageIndex: 0, content: "text", note: "note",
                             boundsStr: markups[0].boundsStr, pageMarkups: PDFPageMarkupCodec.encode(markups), createdAt: 0)
        let requests = NoteAnchorCatalog.savedNotes([note])
        XCTAssertEqual(requests.map(\.pageIndex), [0, 1])
        XCTAssertEqual(requests.map(\.noteId), ["note", "note"])
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
}
