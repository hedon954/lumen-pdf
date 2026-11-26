import AppKit
import PDFKit
import XCTest
@testable import LumenPDF

final class PDFReadingSelectionTests: XCTestCase {
    func testCrossPageDragRebuildsTextPDFKitDroppedFromTheFirstPage() throws {
        let document = try makeDocument(pages: [
            "The first sentence ends on this page and the thought",
            "continues on the next page before a stop."
        ])
        let first = try XCTUnwrap(document.page(at: 0))
        let second = try XCTUnwrap(document.page(at: 1))
        let secondText = try XCTUnwrap(second.string)
        let kept = (secondText as NSString).range(of: "continues on the next page")
        let reported = try XCTUnwrap(second.selection(for: kept))
        XCTAssertEqual(reported.numberOfTextRanges(on: first), 0)
        let firstLine = try XCTUnwrap(first.selection(for: first.bounds(for: .cropBox))?.selectionsByLine().first)
        let secondLine = try XCTUnwrap(second.selection(for: second.bounds(for: .cropBox))?.selectionsByLine().first)
        let start = firstLine.bounds(for: first)
        let end = secondLine.bounds(for: second)

        let gesture = PDFSelectionGesture(
            startPage: 0,
            startPoint: CGPoint(x: start.minX + 1, y: start.midY),
            endPage: 1,
            endPoint: CGPoint(x: end.maxX - 1, y: end.midY)
        )
        let captured = PDFSelectionMarkupGeometry.capture(
            selection: reported,
            document: document,
            gesture: gesture
        )
        let text = captured.markups
            .sorted { $0.pageIndex < $1.pageIndex }
            .map(\.text)
            .joined(separator: " ")

        XCTAssertEqual(captured.markups.map(\.pageIndex), [0, 1])
        XCTAssertEqual(
            text.replacingOccurrences(of: "\n", with: " "),
            "The first sentence ends on this page and the thought continues on the next page before a stop."
        )
        let resolved = ReadingSentenceContext.resolve(lines: captured.lines)
        XCTAssertEqual(
            resolved?.sentence,
            "The first sentence ends on this page and the thought continues on the next page before a stop."
        )
    }

    private func makeDocument(pages: [String]) throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 420, height: 520)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        let font = NSFont.systemFont(ofSize: 12)
        for text in pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let drawing = NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: NSColor.black]
            )
            drawing.draw(in: CGRect(x: 36, y: 430, width: 350, height: 60))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }
}
