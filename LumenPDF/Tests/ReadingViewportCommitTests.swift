import XCTest
@testable import LumenPDF

final class ReadingViewportCommitTests: XCTestCase {
    func testCloseSnapbackDoesNotReplaceANewerPage() {
        let chosen = ReadingViewportCommit.accepting(
            stable: viewport(page: 29, y: 420),
            live: viewport(page: 20, y: 80),
            userScrollEvent: false,
            recentUserScroll: true
        )

        XCTAssertEqual(chosen.anchor?.pageIndex, 29)
        XCTAssertEqual(chosen.pageIndex, 29)
    }

    func testUserScrollBackIsKept() {
        let chosen = ReadingViewportCommit.accepting(
            stable: viewport(page: 29, y: 420),
            live: viewport(page: 20, y: 80),
            userScrollEvent: true,
            recentUserScroll: true
        )

        XCTAssertEqual(ReadingViewportCommit.pageIndex(of: chosen), 20)
    }

    func testOnePageMomentumBackIsKept() {
        let chosen = ReadingViewportCommit.accepting(
            stable: viewport(page: 29, y: 420),
            live: viewport(page: 28, y: 80),
            userScrollEvent: false,
            recentUserScroll: true
        )

        XCTAssertEqual(ReadingViewportCommit.pageIndex(of: chosen), 28)
    }

    func testCloseSnapbackOnTheSamePageKeepsTheReadingLine() {
        let chosen = ReadingViewportCommit.accepting(
            stable: viewport(page: 22, y: 480),
            live: viewport(page: 22, y: 20),
            userScrollEvent: false,
            recentUserScroll: true
        )

        XCTAssertEqual(chosen.anchor?.y, 480)
    }

    func testRestorePagePrefersTheAnchorOverAStaleCurrentPage() {
        var saved = viewport(page: 22, y: 300)
        saved.pageIndex = 20

        XCTAssertEqual(
            ReadingViewportCommit.restorePageIndex(viewport: saved, savedPage: 20),
            22
        )
    }

    func testRejectedSnapbackNormalizesPageIndexToTheAnchor() {
        var stable = viewport(page: 22, y: 300)
        stable.pageIndex = 20

        let chosen = ReadingViewportCommit.accepting(
            stable: stable,
            live: viewport(page: 10, y: 40),
            userScrollEvent: false,
            recentUserScroll: true
        )

        XCTAssertEqual(chosen.pageIndex, 22)
        XCTAssertEqual(chosen.anchor?.pageIndex, 22)
    }

    private func viewport(page: Int, y: Double) -> ReadingRestorationState.PDFViewport {
        ReadingRestorationState.PDFViewport(
            pageIndex: page,
            autoScales: true,
            scaleFactor: 1,
            horizontalOffset: 0,
            verticalOffset: 0.2,
            anchor: .init(pageIndex: page, x: 12, y: y)
        )
    }
}
