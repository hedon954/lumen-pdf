import CoreGraphics
import XCTest
@testable import LumenPDF

final class ReadingSentenceContextTests: XCTestCase {
    func testWordInsideAVisibleSentenceKeepsThatSentence() {
        let lines = [
            line("It first develops a conceptual model for a system.", y: 720),
            line("The handbook elaborates that model by identifying the decisions", y: 700),
            line("available, and what consequences distinguish them.", y: 682)
        ]

        let result = ReadingSentenceContext.extract(
            lines: lines,
            selectionRect: CGRect(x: 150, y: 700, width: 80, height: 14),
            selectedText: "elaborates"
        )

        XCTAssertEqual(
            result,
            "The handbook elaborates that model by identifying the decisions available, and what consequences distinguish them."
        )
    }

    func testIsolatedWordIncludesTheNeighboringSentence() {
        let lines = [
            line("These developments did not eliminate engineering.", y: 700),
            line("elaborates", y: 682)
        ]

        let result = ReadingSentenceContext.extract(
            lines: lines,
            selectionRect: CGRect(x: 48, y: 682, width: 70, height: 14),
            selectedText: "elaborates"
        )

        XCTAssertEqual(
            result,
            "These developments did not eliminate engineering. elaborates"
        )
    }

    func testDistantHeadingIsLeftOutOfTheContext() {
        let lines = [
            line("How to read this book", y: 780, height: 18),
            line("The handbook elaborates that model by identifying the decisions available.", y: 680)
        ]

        let result = ReadingSentenceContext.extract(
            lines: lines,
            selectionRect: CGRect(x: 140, y: 680, width: 80, height: 14),
            selectedText: "elaborates"
        )

        XCTAssertEqual(
            result,
            "The handbook elaborates that model by identifying the decisions available."
        )
    }

    func testThinCharacterRangeFallsBackToTheWiderPageText() {
        let page = """
        These developments did not eliminate engineering.
        elaborates
        They changed its economics.
        """

        let chosen = ReadingSentenceContext.prefer(
            "elaborates",
            ReadingSentenceContext.widen(text: page, selectedText: "elaborates"),
            selectedText: "elaborates"
        )

        XCTAssertEqual(
            chosen,
            "These developments did not eliminate engineering. elaborates They changed its economics."
        )
    }

    private func line(
        _ text: String,
        y: CGFloat,
        x: CGFloat = 48,
        width: CGFloat = 420,
        height: CGFloat = 14
    ) -> PDFTextLine {
        PDFTextLine(rect: CGRect(x: x, y: y, width: width, height: height), text: text)
    }
}
