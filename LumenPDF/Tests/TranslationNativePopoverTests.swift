import XCTest
@testable import LumenPDF

final class TranslationNativePopoverTests: XCTestCase {
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

        XCTAssertEqual(word, 320)
        XCTAssertGreaterThan(sentence, word)
        XCTAssertLessThanOrEqual(sentence, 760)
        XCTAssertLessThanOrEqual(narrow, 760)
        XCTAssertGreaterThanOrEqual(narrow, 280)
    }
}
