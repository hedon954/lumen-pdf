import AppKit
import PDFKit
import XCTest
@testable import LumenPDF

final class PDFMarkupAppearanceTests: XCTestCase {
    func testUnderlineAppearanceAlwaysAppliesVisibleRedSRGBColor() throws {
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 10, y: 10, width: 120, height: 20),
            forType: .underline,
            withProperties: nil
        )
        annotation.color = .black

        PDFMarkupAppearance.applyUnderline(to: annotation)

        let color = try XCTUnwrap(annotation.color.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.redComponent, 0.85)
        XCTAssertLessThan(color.greenComponent, 0.2)
        XCTAssertLessThan(color.blueComponent, 0.2)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(annotation.markupType, .underline)
    }

    func testMakeUnderlineAppliesAppearanceAndIdentity() throws {
        let annotation = PDFMarkupAppearance.makeUnderline(
            bounds: CGRect(x: 1, y: 2, width: 30, height: 12),
            userName: "note-1",
            contents: "note:note-1"
        )

        let color = try XCTUnwrap(annotation.color.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.redComponent, 0.85)
        XCTAssertEqual(annotation.markupType, .underline)
        XCTAssertEqual(annotation.userName, "note-1")
        XCTAssertEqual(annotation.contents, "note:note-1")
    }

    func testMultiLineUnderlineIsOneAnnotation() throws {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 600, height: 800), for: .mediaBox)
        document.insert(page, at: 0)
        let rects = [
            CGRect(x: 48, y: 700, width: 400, height: 14),
            CGRect(x: 48, y: 682, width: 400, height: 14),
            CGRect(x: 48, y: 664, width: 300, height: 14)
        ]
        let annotation = try XCTUnwrap(
            PDFHighlightAnnotationFactory.makeUnderline(
                lineRects: rects,
                userName: "__fu",
                contents: "free:underline"
            )
        )
        page.addAnnotation(annotation)

        XCTAssertEqual(page.annotations.filter { $0.userName == "__fu" }.count, 1)
        XCTAssertEqual(PDFHighlightAnnotationFactory.lineRects(from: annotation).count, 3)
    }
}

final class AnnotationBoundsCodecTests: XCTestCase {
    func testParseDropsEmptyAndZeroRects() {
        let bounds = "{{0, 0}, {0, 0}}|{{10, 20}, {30, 12}}|{{0, 0}, {0, 0}}"
        XCTAssertEqual(
            AnnotationBoundsCodec.parse(bounds),
            [CGRect(x: 10, y: 20, width: 30, height: 12)]
        )
    }

    func testStringRoundTripKeepsNonEmptyRects() {
        let rects = [CGRect(x: 4, y: 8, width: 16, height: 6)]
        XCTAssertEqual(
            AnnotationBoundsCodec.parse(AnnotationBoundsCodec.string(from: rects)),
            rects
        )
    }
}
