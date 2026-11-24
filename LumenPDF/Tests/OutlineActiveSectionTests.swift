import XCTest
@testable import LumenPDF

final class OutlineActiveSectionTests: XCTestCase {
    func testViewportOnTheNextPageKeepsTheLastHeadingOfThePreviousPage() {
        let items = [
            heading(page: 4, order: 0, y: 700),
            heading(page: 4, order: 1, y: 240)
        ]

        let order = OutlineActiveSection.activeOrder(
            in: items,
            position: OutlineReadingPosition(pageIndex: 5, topY: 760)
        )

        XCTAssertEqual(order, 1)
    }

    func testHeadingStillBelowTheViewportTopIsNotCurrent() {
        let items = [
            heading(page: 4, order: 0, y: 700),
            heading(page: 4, order: 1, y: 240)
        ]

        let order = OutlineActiveSection.activeOrder(
            in: items,
            position: OutlineReadingPosition(pageIndex: 4, topY: 500)
        )

        XCTAssertEqual(order, 0)
    }

    func testHeadingAtTheViewportTopIsCurrent() {
        let items = [
            heading(page: 4, order: 0, y: 700),
            heading(page: 4, order: 1, y: 240)
        ]

        let order = OutlineActiveSection.activeOrder(
            in: items,
            position: OutlineReadingPosition(pageIndex: 4, topY: 240)
        )

        XCTAssertEqual(order, 1)
    }

    func testPageOnlyPositionUsesTheLastBookmarkOnThatPage() {
        let items = [
            heading(page: 4, order: 0, y: 792),
            heading(page: 4, order: 1, y: 792),
            heading(page: 8, order: 2, y: 792)
        ]

        let order = OutlineActiveSection.activeOrder(
            in: items,
            position: OutlineReadingPosition(pageIndex: 4, topY: nil)
        )

        XCTAssertEqual(order, 1)
    }

    func testMissingDestinationPointStartsAtTheTopOfThePage() {
        XCTAssertEqual(
            OutlineDestinationPosition.startY(point: nil, pageMaxY: 792),
            792
        )
        XCTAssertEqual(
            OutlineDestinationPosition.startY(point: .zero, pageMaxY: 792),
            792
        )
        XCTAssertEqual(
            OutlineDestinationPosition.startY(point: CGPoint(x: 90, y: 240), pageMaxY: 792),
            240
        )
    }

    private func heading(page: Int, order: Int, y: Double) -> OutlineSectionCandidate {
        OutlineSectionCandidate(pageIndex: page, order: order, destinationY: y)
    }
}
