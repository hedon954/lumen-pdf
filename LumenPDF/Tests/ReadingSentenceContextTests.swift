import CoreGraphics
import XCTest
@testable import LumenPDF

final class ReadingSentenceContextTests: XCTestCase {
    func testWordInsideAVisibleSentenceKeepsThatSentence() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("It first develops a conceptual model for a system.", y: 720),
            line("The handbook elaborates that model by identifying the decisions", y: 700, selected: "elaborates"),
            line("available, and what consequences distinguish them.", y: 682)
        ])

        XCTAssertEqual(result?.word, "elaborates")
        XCTAssertEqual(
            result?.sentence,
            "The handbook elaborates that model by identifying the decisions available, and what consequences distinguish them."
        )
    }

    func testSelectingOneSentenceDoesNotPullThePreviousSentence() {
        let sentence = "The handbook elaborates that model by identifying the decisions available."
        let result = ReadingSentenceContext.resolve(lines: [
            line("These developments did not eliminate engineering.", y: 720),
            line(sentence, y: 700, width: 460, selected: sentence)
        ])

        XCTAssertEqual(result?.sentence, sentence)
    }

    func testLaterSentenceIsNotReplacedByTheEarlierOne() {
        let later = "The later sentence is the one under the caret."
        let result = ReadingSentenceContext.resolve(lines: [
            line("The earlier sentence stays on the page above.", y: 720, width: 460),
            line(later, y: 700, width: 460, selected: later)
        ])

        XCTAssertEqual(result?.sentence, later)
    }

    func testASentenceThatStartsWithTheSelectionDoesNotIncludeItsNeighbor() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("Models often fail.", y: 720),
            line("Models often succeed when the context is the sentence itself.", y: 700, width: 480, selected: "Models often succeed when the context is the sentence itself.")
        ])

        XCTAssertEqual(
            result?.sentence,
            "Models often succeed when the context is the sentence itself."
        )
    }

    func testPartialSentenceCompletesWithoutTakingTheNextSentence() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("Alpha ends here. Beta continues with more words after the break.", y: 700, width: 480, selected: "Beta cont")
        ])

        XCTAssertEqual(result?.sentence, "Beta continues with more words after the break.")
        XCTAssertEqual(result?.word, "Beta cont")
    }

    func testUnterminatedFragmentStaysInTheSentenceReturnedByTheTokenizer() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("These developments did not eliminate engineering.", y: 700),
            line("elaborates", y: 682, selected: "elaborates")
        ])

        XCTAssertEqual(result?.word, "elaborates")
        XCTAssertEqual(
            result?.sentence,
            "These developments did not eliminate engineering. elaborates"
        )
    }

    func testDistantHeadingIsLeftOutOfTheContext() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("How to read this book", y: 780, height: 22),
            line("The handbook elaborates that model by identifying the decisions available.", y: 680, selected: "elaborates")
        ])

        XCTAssertEqual(
            result?.sentence,
            "The handbook elaborates that model by identifying the decisions available."
        )
    }

    func testWithoutASelectionTheWordIsNotSearchedFor() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("These developments did not eliminate engineering.", y: 718),
            line("elaborates", y: 700)
        ])
        XCTAssertNil(result)
    }

    func testEngineeringSentenceKeepsTheOpeningWord() {
        let sentence = "Engineering management is responsible not only for what the organization produces, but for the engineering capability the organization becomes."
        let result = ReadingSentenceContext.resolve(lines: [
            line(sentence, y: 700, width: 460, selected: "responsible")
        ])
        XCTAssertEqual(result?.word, "responsible")
        XCTAssertTrue(result?.sentence.hasPrefix("Engineering ") == true)
    }

    func testOpeningWordOnItsOwnLineStaysInTheSentence() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("Engineering", y: 700, width: 90),
            line("management is responsible not only for what the organization produces, but for the engineering capability the organization becomes.", y: 682, width: 460, selected: "responsible")
        ])
        XCTAssertTrue(result?.sentence.hasPrefix("Engineering ") == true)
    }

    func testAbbreviationPeriodDoesNotEndTheSentence() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("Mr. Smith left the room.", y: 700, selected: "left")
        ])
        XCTAssertEqual(result?.sentence, "Mr. Smith left the room.")
    }

    func testHyphenatedLineBreakRejoinsTheWord() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("The informa-", y: 700, width: 420),
            line("tion arrived before noon.", y: 682, width: 420, selected: "arrived")
        ])
        XCTAssertEqual(result?.sentence, "The information arrived before noon.")
    }

    func testSameWordUsesTheLineUnderTheSelection() {
        let lower = ReadingSentenceContext.resolve(lines: [
            line("The observation ends here.", y: 720, width: 280),
            line("The observation begins here.", y: 700, width: 280, selected: "observation")
        ])
        let upper = ReadingSentenceContext.resolve(lines: [
            line("The observation ends here.", y: 720, width: 280, selected: "observation"),
            line("The observation begins here.", y: 700, width: 280)
        ])
        XCTAssertEqual(lower?.word, "observation")
        XCTAssertEqual(lower?.sentence, "The observation begins here.")
        XCTAssertEqual(upper?.sentence, "The observation ends here.")
    }

    func testObservationIsNotReplacedByObservations() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("These observations should not be converted into universal targets.", y: 718, width: 460),
            line("The observation becomes meaningful only through the process model.", y: 700, width: 460, selected: "observation")
        ])
        XCTAssertEqual(result?.word, "observation")
        XCTAssertEqual(
            result?.sentence,
            "The observation becomes meaningful only through the process model."
        )
    }

    func testPartialWordCompletesToTheSentence() {
        let sentence = "Organizations must distinguish managerial activities from those that exercise judgment."
        let result = ReadingSentenceContext.resolve(lines: [
            line(sentence, y: 700, width: 480, selected: "exer")
        ])
        XCTAssertEqual(result?.word, "exercise")
        XCTAssertEqual(result?.sentence, sentence)
    }

    func testDistantColumnsAreNotJoined() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("Left column stays here.", y: 700, x: 40, width: 180, selected: "column"),
            line("Right column is separate.", y: 700, x: 320, width: 180)
        ])
        XCTAssertEqual(result?.sentence, "Left column stays here.")
    }

    func testCrossPageSelectionKeepsTheEarlierPageFirst() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("The thought", y: 80, width: 400, page: 0, selected: "The thought"),
            line("continues here.", y: 700, width: 400, page: 1, selected: "continues here.")
        ])

        XCTAssertEqual(result?.sentence, "The thought continues here.")
    }

    func testPageBreakCompletesTheSentenceWithoutThePreviousOne() {
        let result = ReadingSentenceContext.resolve(lines: [
            line("Previous sentence ends here.", y: 100, width: 400, page: 0),
            line("The thought", y: 82, width: 400, page: 0, selected: "The thought"),
            line("continues here.", y: 700, width: 400, page: 1, selected: "continues here.")
        ])

        XCTAssertEqual(result?.sentence, "The thought continues here.")
    }

    private func line(
        _ text: String,
        y: CGFloat,
        x: CGFloat = 48,
        width: CGFloat = 420,
        height: CGFloat = 14,
        page: Int = 0,
        selected: String? = nil
    ) -> ReadingLine {
        ReadingLine(
            pageIndex: page,
            rect: CGRect(x: x, y: y, width: width, height: height),
            text: text,
            selected: selected.flatMap { needle in
                guard let range = text.range(of: needle) else { return 0..<text.count }
                let lower = text.distance(from: text.startIndex, to: range.lowerBound)
                let upper = text.distance(from: text.startIndex, to: range.upperBound)
                return lower..<upper
            }
        )
    }
}
