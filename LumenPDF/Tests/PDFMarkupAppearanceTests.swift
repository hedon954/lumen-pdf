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
}
