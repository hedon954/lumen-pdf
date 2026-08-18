import XCTest
@testable import LumenPDF

final class PDFSelectionMarkupGeometryTests: XCTestCase {
    private let pageBounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    func testIncrementingFooterMatchesAcrossPagesAndIsExcluded() {
        let footer = PDFTextLine(
            rect: CGRect(x: 48, y: 22, width: 280, height: 12),
            text: "50 | Chapter 2: Defining Nonfunctional Requirements"
        )
        let body = uniqueBody(prefix: "p50", y0: 140, count: 8)
        let neighbor = PDFPageTextLayout(
            pageIndex: 51,
            bounds: pageBounds,
            lines: uniqueBody(prefix: "p51", y0: 140, count: 8) + [
                PDFTextLine(
                    rect: CGRect(x: 48, y: 24, width: 280, height: 12),
                    text: "51 | Chapter 2: Defining Nonfunctional Requirements"
                )
            ]
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: Array(body.suffix(2)) + [footer],
            pageBounds: pageBounds,
            neighbors: [neighbor]
        )

        XCTAssertEqual(
            PDFPageChromeFilter.runningSignature(footer.text),
            PDFPageChromeFilter.runningSignature("51 | Chapter 2: Defining Nonfunctional Requirements")
        )
        XCTAssertEqual(kept.map(\.text), Array(body.suffix(2)).map(\.text))
    }

    func testFacingPageHeadersMatchAtPlusMinusTwo() {
        let chapterHeader = PDFTextLine(
            rect: CGRect(x: 48, y: 772, width: 220, height: 12),
            text: "Chapter 2: Defining Nonfunctional Requirements"
        )
        let body = uniqueBody(prefix: "odd", y0: 140, count: 6)
        let left = PDFPageTextLayout(
            pageIndex: 4,
            bounds: pageBounds,
            lines: [
                PDFTextLine(
                    rect: CGRect(x: 48, y: 770, width: 200, height: 12),
                    text: "Designing Data-Intensive Applications"
                )
            ] + uniqueBody(prefix: "even-left", y0: 140, count: 6)
        )
        let right = PDFPageTextLayout(
            pageIndex: 7,
            bounds: pageBounds,
            lines: [
                PDFTextLine(
                    rect: CGRect(x: 40, y: 774, width: 220, height: 12),
                    text: "Chapter 2: Defining Nonfunctional Requirements"
                )
            ] + uniqueBody(prefix: "odd-right", y0: 140, count: 6)
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: [chapterHeader] + Array(body.prefix(2)),
            pageBounds: pageBounds,
            neighbors: [left, right]
        )

        XCTAssertEqual(kept.map(\.text), Array(body.prefix(2)).map(\.text))
    }

    func testUniqueBodyAtPageTopIsKeptEvenWhenNeighborHasAHeaderThere() {
        let continuation = PDFTextLine(
            rect: CGRect(x: 48, y: 730, width: 310, height: 16),
            text: "write request may involve more work than if you have a small amount of data, even if the size of the request is the same."
        )
        let previousPage = PDFPageTextLayout(
            pageIndex: 50,
            bounds: pageBounds,
            lines: [
                PDFTextLine(
                    rect: CGRect(x: 48, y: 778, width: 240, height: 10),
                    text: "Designing Data-Intensive Applications"
                )
            ] + uniqueBody(prefix: "p50-body", y0: 140, count: 10) + [
                PDFTextLine(
                    rect: CGRect(x: 48, y: 22, width: 280, height: 12),
                    text: "50 | Chapter 2: Defining Nonfunctional Requirements"
                )
            ]
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: [continuation],
            pageBounds: pageBounds,
            neighbors: [previousPage]
        )

        XCTAssertEqual(kept.map(\.text), [continuation.text])
    }

    func testRepeatingLineIsExcludedEvenWhenItIsNotAtTheMargin() {
        let watermark = PDFTextLine(
            rect: CGRect(x: 80, y: 400, width: 160, height: 14),
            text: "CONFIDENTIAL"
        )
        let body = uniqueBody(prefix: "mid", y0: 140, count: 6)
        let neighbor = PDFPageTextLayout(
            pageIndex: 2,
            bounds: pageBounds,
            lines: uniqueBody(prefix: "mid-next", y0: 140, count: 6) + [
                PDFTextLine(
                    rect: CGRect(x: 82, y: 396, width: 160, height: 14),
                    text: "CONFIDENTIAL"
                )
            ]
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: Array(body.prefix(2)) + [watermark],
            pageBounds: pageBounds,
            neighbors: [neighbor]
        )

        XCTAssertEqual(kept.map(\.text), Array(body.prefix(2)).map(\.text))
    }

    func testWithoutNeighborPagesSelectedLinesAreNotGuessedAsChrome() {
        let footer = PDFTextLine(
            rect: CGRect(x: 48, y: 22, width: 280, height: 12),
            text: "50 | Chapter 2: Defining Nonfunctional Requirements"
        )
        let top = PDFTextLine(
            rect: CGRect(x: 48, y: 730, width: 310, height: 16),
            text: "write request may involve more work than if you have a small amount of data."
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: [top, footer],
            pageBounds: pageBounds,
            neighbors: []
        )

        XCTAssertEqual(kept.map(\.text), [top.text, footer.text])
    }

    func testOrdinaryBodyLineIsKeptWhenNeighborsHaveDifferentTextAtTheSameY() {
        let body = uniqueBody(prefix: "here", y0: 180, count: 8)
        let neighbor = PDFPageTextLayout(
            pageIndex: 3,
            bounds: pageBounds,
            lines: uniqueBody(prefix: "there", y0: 180, count: 8)
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: [body.last!],
            pageBounds: pageBounds,
            neighbors: [neighbor]
        )

        XCTAssertEqual(kept.map(\.text), [body.last!.text])
    }

    func testNumberedCaptionsAtTheSameYAreNotTreatedAsChrome() {
        let caption = PDFTextLine(
            rect: CGRect(x: 48, y: 80, width: 200, height: 14),
            text: "Figure 3. Latency by region"
        )
        let neighbor = PDFPageTextLayout(
            pageIndex: 4,
            bounds: pageBounds,
            lines: [
                PDFTextLine(
                    rect: CGRect(x: 48, y: 82, width: 200, height: 14),
                    text: "Figure 4. Latency by region"
                )
            ]
        )

        let kept = PDFPageChromeFilter.bodyLines(
            selected: [caption],
            pageBounds: pageBounds,
            neighbors: [neighbor]
        )

        XCTAssertEqual(kept.map(\.text), [caption.text])
        XCTAssertNotEqual(
            PDFPageChromeFilter.runningSignature(caption.text),
            PDFPageChromeFilter.runningSignature("Figure 4. Latency by region")
        )
    }

    func testTextMatcherRecoversSecondPageContinuation() {
        let selected = """
        processing a single
        50 | Chapter 2: Defining Nonfunctional Requirements
        write request may involve more work than if you have a small amount of data, even if the size of the request is the same.
        """
        let header = PDFTextLine(
            rect: CGRect(x: 48, y: 778, width: 240, height: 10),
            text: "Designing Data-Intensive Applications"
        )
        let continuation = PDFTextLine(
            rect: CGRect(x: 48, y: 730, width: 310, height: 16),
            text: "write request may involve more work than if you have a small amount of data, even if the size of the request is the same."
        )
        let nextSection = PDFTextLine(
            rect: CGRect(x: 48, y: 680, width: 300, height: 16),
            text: "Shared-Memory, Shared-Disk, and Shared-Nothing Architectures"
        )
        let matched = PDFSelectionTextMatcher.matchingLines(
            selectedText: selected,
            pageLines: [header, continuation, nextSection]
        )
        let previousPage = PDFPageTextLayout(
            pageIndex: 50,
            bounds: pageBounds,
            lines: [
                PDFTextLine(
                    rect: CGRect(x: 48, y: 22, width: 280, height: 12),
                    text: "50 | Chapter 2: Defining Nonfunctional Requirements"
                )
            ]
        )
        let kept = PDFPageChromeFilter.bodyLines(
            selected: matched,
            pageBounds: pageBounds,
            neighbors: [previousPage]
        )

        XCTAssertEqual(matched.map(\.text), [continuation.text])
        XCTAssertEqual(kept.map(\.text), [continuation.text])
    }

    private func uniqueBody(prefix: String, y0: CGFloat, count: Int) -> [PDFTextLine] {
        (0..<count).map { index in
            PDFTextLine(
                rect: CGRect(x: 48, y: y0 + CGFloat(index) * 22, width: 300, height: 16),
                text: "\(prefix) body line \(index) with unique wording"
            )
        }
    }
}
