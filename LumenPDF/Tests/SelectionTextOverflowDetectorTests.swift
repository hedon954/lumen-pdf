import XCTest
@testable import LumenPDF

final class SelectionTextOverflowDetectorTests: XCTestCase {
    func testShortTextDoesNotNeedExpansion() {
        XCTAssertFalse(
            SelectionTextOverflowDetector.needsExpansion(
                text: "By contrast",
                width: 280,
                maximumLines: 6
            )
        )
    }

    func testLongWrappedTextNeedsExpansion() {
        XCTAssertTrue(
            SelectionTextOverflowDetector.needsExpansion(
                text: Array(repeating: "distributed systems", count: 40).joined(separator: " "),
                width: 280,
                maximumLines: 6
            )
        )
    }

    func testExplicitLineBreaksCountTowardTheLimit() {
        XCTAssertTrue(
            SelectionTextOverflowDetector.needsExpansion(
                text: Array(repeating: "line", count: 7).joined(separator: "\n"),
                width: 280,
                maximumLines: 6
            )
        )
    }
}
