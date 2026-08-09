import XCTest
@testable import LumenPDF

final class ReadingOverlayPlacementTests: XCTestCase {
    private let containerSize = CGSize(width: 1_000, height: 800)

    func testConvertsRootAnchorToOverlayLocalCoordinates() {
        let anchor = CGRect(x: 480, y: 520, width: 80, height: 24)
        let overlayFrame = CGRect(x: 0, y: 40, width: 1_000, height: 760)

        let local = SelectionActionBarPlacement.localAnchorRect(
            anchor,
            overlayFrameInRoot: overlayFrame
        )

        XCTAssertEqual(local, CGRect(x: 480, y: 480, width: 80, height: 24))
    }

    func testPlacesOverlayBelowSelectionByDefault() {
        let result = ReadingOverlayPlacementPolicy.place(
            input(
                anchorRect: CGRect(x: 450, y: 180, width: 100, height: 24),
                overlaySize: CGSize(width: 380, height: 240)
            )
        )

        XCTAssertEqual(result.placement, .below)
        XCTAssertEqual(result.origin, CGPoint(x: 310, y: 216))
    }

    func testUsesAboveWhenBelowWouldBeClampedAcrossSelection() {
        let anchor = CGRect(x: 450, y: 620, width: 100, height: 24)
        let overlaySize = CGSize(width: 380, height: 300)

        let result = ReadingOverlayPlacementPolicy.place(
            input(anchorRect: anchor, overlaySize: overlaySize)
        )
        let frame = CGRect(origin: result.origin, size: overlaySize)

        XCTAssertEqual(result.placement, .above)
        XCTAssertLessThanOrEqual(frame.maxY, anchor.minY - 12 + 0.5)
        XCTAssertFalse(frame.intersects(anchor))
    }

    func testKeepingPlacementReevaluatesWhenContentGrowthWouldCoverSelection() {
        let anchor = CGRect(x: 450, y: 450, width: 100, height: 24)
        let initial = ReadingOverlayPlacementPolicy.place(
            input(anchorRect: anchor, overlaySize: CGSize(width: 380, height: 200))
        )

        let grown = ReadingOverlayPlacementPolicy.place(
            input(anchorRect: anchor, overlaySize: CGSize(width: 380, height: 330)),
            keeping: initial.placement
        )
        let grownFrame = CGRect(origin: grown.origin, size: CGSize(width: 380, height: 330))

        XCTAssertEqual(initial.placement, .below)
        XCTAssertEqual(grown.placement, .above)
        XCTAssertFalse(grownFrame.intersects(anchor))
    }

    func testFallsBackToLeastOverlapForSelectionThatFillsViewport() {
        let anchor = CGRect(x: 40, y: 40, width: 920, height: 720)
        let overlaySize = CGSize(width: 380, height: 300)

        let result = ReadingOverlayPlacementPolicy.place(
            input(anchorRect: anchor, overlaySize: overlaySize)
        )
        let frame = CGRect(origin: result.origin, size: overlaySize)

        XCTAssertEqual(result.placement, .leastOverlap)
        XCTAssertGreaterThan(frame.intersection(anchor).width * frame.intersection(anchor).height, 0)
        XCTAssertGreaterThanOrEqual(frame.minX, 12)
        XCTAssertGreaterThanOrEqual(frame.minY, 12)
        XCTAssertLessThanOrEqual(frame.maxX, containerSize.width - 12)
        XCTAssertLessThanOrEqual(frame.maxY, containerSize.height - 12)
    }

    private func input(
        anchorRect: CGRect,
        overlaySize: CGSize
    ) -> ReadingOverlayPlacementInput {
        ReadingOverlayPlacementInput(
            anchorRect: anchorRect,
            overlaySize: overlaySize,
            containerSize: containerSize,
            preferredGap: 12,
            safeInset: 12
        )
    }
}
