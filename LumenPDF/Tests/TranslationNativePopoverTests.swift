import XCTest
@testable import LumenPDF

final class TranslationNativePopoverTests: XCTestCase {
    func testPrefersLeadingWhenThereIsRoomOnTheLeft() {
        let edge = TranslationPopoverGeometry.preferredEdge(
            anchorRect: CGRect(x: 620, y: 300, width: 80, height: 18),
            contentSize: CGSize(width: 320, height: 240),
            containerSize: CGSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(edge, .leading)
        XCTAssertEqual(edge.nsRectEdge, .minX)
    }

    func testFlipsToTrailingNearTheLeadingEdge() {
        let edge = TranslationPopoverGeometry.preferredEdge(
            anchorRect: CGRect(x: 24, y: 300, width: 80, height: 18),
            contentSize: CGSize(width: 320, height: 240),
            containerSize: CGSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(edge, .trailing)
        XCTAssertEqual(edge.nsRectEdge, .maxX)
    }

    func testUsesAboveWhenHorizontalEdgesAreTooTight() {
        let edge = TranslationPopoverGeometry.preferredEdge(
            anchorRect: CGRect(x: 40, y: 520, width: 920, height: 20),
            contentSize: CGSize(width: 320, height: 240),
            containerSize: CGSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(edge, .above)
        XCTAssertEqual(edge.nsRectEdge, .maxY)
    }

    func testUsesBelowWhenOnlyTheBottomHasRoom() {
        let edge = TranslationPopoverGeometry.preferredEdge(
            anchorRect: CGRect(x: 40, y: 40, width: 920, height: 20),
            contentSize: CGSize(width: 320, height: 240),
            containerSize: CGSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(edge, .below)
        XCTAssertEqual(edge.nsRectEdge, .minY)
    }

    func testAppKitRectFlipsSwiftUIOrigin() {
        let rect = TranslationPopoverGeometry.appKitRect(
            fromSwiftUI: CGRect(x: 40, y: 80, width: 80, height: 16),
            viewHeight: 600
        )

        XCTAssertEqual(rect, CGRect(x: 40, y: 504, width: 80, height: 16))
    }

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

    func testClampContentSizeCapsHeightToTheAvailableWindow() {
        let clamped = TranslationPopoverGeometry.clampContentSize(
            CGSize(width: 900, height: 2_000),
            available: CGSize(width: 800, height: 600)
        )

        XCTAssertEqual(clamped.width, 760)
        XCTAssertEqual(clamped.height, 480)
    }
}
