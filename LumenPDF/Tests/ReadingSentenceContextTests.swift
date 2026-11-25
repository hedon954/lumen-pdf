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

    func testWithoutASelectionRectTheWordIsNotSearchedFor() {
        let lines = [
            line("These developments did not eliminate engineering.", y: 718),
            line("elaborates", y: 700)
        ]
        XCTAssertNil(ReadingSentenceContext.extract(
            lines: lines,
            selectionRect: .zero,
            selectedText: "elaborates"
        ))
    }

    func testEngineeringSentenceKeepsTheOpeningWord() {
        let sentence = "Engineering management is responsible not only for what the organization produces, but for the engineering capability the organization becomes."
        let result = ReadingSentenceContext.extract(
            lines: [line(sentence, y: 700, width: 460)],
            selectionRect: CGRect(x: 180, y: 700, width: 80, height: 14),
            selectedText: "responsible"
        )
        XCTAssertTrue(result?.hasPrefix("Engineering ") == true)
    }

    func testOpeningWordOnItsOwnLineStaysInTheSentence() {
        let result = ReadingSentenceContext.extract(
            lines: [
                line("Engineering", y: 700, width: 90),
                line("management is responsible not only for what the organization produces, but for the engineering capability the organization becomes.", y: 682, width: 460)
            ],
            selectionRect: CGRect(x: 120, y: 682, width: 80, height: 14),
            selectedText: "responsible"
        )
        XCTAssertTrue(result?.hasPrefix("Engineering ") == true)
    }

    func testAbbreviationPeriodDoesNotEndTheSentence() {
        let result = ReadingSentenceContext.extract(
            lines: [line("Mr. Smith left the room.", y: 700)],
            selectionRect: CGRect(x: 80, y: 700, width: 40, height: 14),
            selectedText: "left"
        )
        XCTAssertEqual(result, "Mr. Smith left the room.")
    }

    func testHyphenatedLineBreakRejoinsTheWord() {
        let result = ReadingSentenceContext.extract(
            lines: [
                line("The informa-", y: 700, width: 420),
                line("tion arrived before noon.", y: 682, width: 420)
            ],
            selectionRect: CGRect(x: 80, y: 682, width: 40, height: 14),
            selectedText: "arrived"
        )
        XCTAssertEqual(result, "The information arrived before noon.")
    }

    func testSameWordUsesTheLineUnderTheSelection() {
        let lines = [
            line("The observation ends here.", y: 720, width: 280),
            line("The observation begins here.", y: 700, width: 280)
        ]
        let lower = ReadingSentenceContext.resolve(
            lines: lines,
            selectionRect: CGRect(x: 70, y: 700, width: 80, height: 14),
            selectedText: "observation"
        )
        let upper = ReadingSentenceContext.resolve(
            lines: lines,
            selectionRect: CGRect(x: 70, y: 720, width: 80, height: 14),
            selectedText: "observation"
        )
        XCTAssertEqual(lower?.word, "observation")
        XCTAssertEqual(lower?.sentence, "The observation begins here.")
        XCTAssertEqual(upper?.sentence, "The observation ends here.")
    }

    func testObservationIsNotReplacedByObservations() {
        let lines = [
            line("These observations should not be converted into universal targets.", y: 718, width: 460),
            line("The observation becomes meaningful only through the process model.", y: 700, width: 460)
        ]
        let result = ReadingSentenceContext.resolve(
            lines: lines,
            selectionRect: CGRect(x: 80, y: 700, width: 90, height: 14),
            selectedText: "observation"
        )
        XCTAssertEqual(result?.word, "observation")
        XCTAssertEqual(
            result?.sentence,
            "The observation becomes meaningful only through the process model."
        )
    }

    func testPartialWordCompletesToTheSentence() {
        let sentence = "Organizations must distinguish managerial activities from those that exercise judgment."
        let result = ReadingSentenceContext.resolve(
            lines: [line(sentence, y: 700, width: 480)],
            selectionRect: CGRect(x: 420, y: 700, width: 50, height: 14),
            selectedText: "exer"
        )
        XCTAssertEqual(result?.word, "exercise")
        XCTAssertEqual(result?.sentence, sentence)
    }

    func testDistantColumnsAreNotJoined() {
        let result = ReadingSentenceContext.extract(
            lines: [
                line("Left column stays here.", y: 700, x: 40, width: 180),
                line("Right column is separate.", y: 700, x: 320, width: 180)
            ],
            selectionRect: CGRect(x: 50, y: 700, width: 40, height: 14),
            selectedText: "column"
        )
        XCTAssertEqual(result, "Left column stays here.")
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
