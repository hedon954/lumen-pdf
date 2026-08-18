import XCTest
@testable import LumenPDF

final class PDFExtractedTextCollapserTests: XCTestCase {
    private let dstSentence =
        "In DST, deterministic scheduling keeps every randomized execution reproducible while preserving the exact order of operations."

    func testCollapsesNewlineRepeatedPDFSelection() {
        let duplicated = Array(repeating: dstSentence, count: 10).joined(separator: "\n")
        XCTAssertEqual(PDFExtractedTextCollapser.collapse(duplicated), dstSentence)
    }

    func testCollapsesSentenceBoundaryRepeatsOnOneLine() {
        let duplicated = Array(repeating: dstSentence, count: 4).joined(separator: " ")
        XCTAssertEqual(PDFExtractedTextCollapser.collapse(duplicated), dstSentence)
    }

    func testCollapsesExactConcatenatedTiles() {
        let unit = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        XCTAssertEqual(
            PDFExtractedTextCollapser.collapse(String(repeating: unit, count: 4)),
            unit
        )
    }

    func testLeavesOrdinaryParagraphsUnchanged() {
        let paragraph =
            "\(dstSentence)\nThe scheduler records the random choices so later reruns can replay them."
        XCTAssertEqual(PDFExtractedTextCollapser.collapse(paragraph), paragraph)
    }

    func testLeavesShortRepeatedTokensUnchanged() {
        XCTAssertEqual(
            PDFExtractedTextCollapser.collapse("yes\nyes\nyes\nyes"),
            "yes\nyes\nyes\nyes"
        )
    }

    func testLeavesTwoCopiesUnchangedToAvoidFalsePositives() {
        let twice = "\(dstSentence)\n\(dstSentence)"
        XCTAssertEqual(PDFExtractedTextCollapser.collapse(twice), twice)
    }
}
