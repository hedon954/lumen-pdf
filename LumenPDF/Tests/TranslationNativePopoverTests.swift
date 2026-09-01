import XCTest
@testable import LumenPDF

final class TranslationPopoverGeometryTests: XCTestCase {
    func testWordAndSentenceContentWidthStayWithinCaps() {
        let word = TranslationPopoverGeometry.contentWidth(
            isSentenceMode: false,
            textCount: 12,
            availableWidth: 1_200
        )
        let sentence = TranslationPopoverGeometry.contentWidth(
            isSentenceMode: true,
            textCount: 80,
            availableWidth: 1_200
        )
        let narrow = TranslationPopoverGeometry.contentWidth(
            isSentenceMode: true,
            textCount: 400,
            availableWidth: 420
        )

        XCTAssertEqual(word, 380)
        XCTAssertGreaterThan(sentence, word)
        XCTAssertLessThanOrEqual(sentence, 760)
        XCTAssertLessThanOrEqual(narrow, 760)
        XCTAssertGreaterThanOrEqual(narrow, 340)
    }

    func testInitialHeightsMatchMainBranchSizing() {
        XCTAssertEqual(
            TranslationPopoverGeometry.initialContentHeight(
                isSentenceMode: false,
                showsFailure: false
            ),
            120
        )
        XCTAssertEqual(
            TranslationPopoverGeometry.initialContentHeight(
                isSentenceMode: true,
                showsFailure: false
            ),
            160
        )
        XCTAssertEqual(
            TranslationPopoverGeometry.initialContentHeight(
                isSentenceMode: false,
                showsFailure: true
            ),
            248
        )
    }

    func testHeaderUsesFourEqualControlsWithCompactSpacing() {
        XCTAssertEqual(TranslationHeaderControlMetrics.count, 4)
        XCTAssertEqual(TranslationHeaderControlMetrics.size, 28)
        XCTAssertEqual(TranslationHeaderControlMetrics.spacing, 4)
        XCTAssertLessThan(TranslationHeaderControlMetrics.spacing, 8)
    }

    func testSelectionEmphasisExpandsAroundGlyphBounds() {
        XCTAssertEqual(
            TranslationSelectionEmphasisGeometry.highlightRect(
                for: CGRect(x: 40, y: 60, width: 80, height: 16)
            ),
            CGRect(x: 38.5, y: 59.25, width: 83, height: 17.5)
        )
    }
}
