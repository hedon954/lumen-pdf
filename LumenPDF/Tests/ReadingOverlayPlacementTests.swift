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

    func testLookUpOrderPrefersLeadingWhenThereIsRoom() {
        let result = ReadingOverlayPlacementPolicy.place(
            input(
                anchorRect: CGRect(x: 620, y: 300, width: 80, height: 18),
                overlaySize: CGSize(width: 320, height: 240),
                placementOrder: ReadingOverlayPlacement.lookUpOrder
            )
        )

        XCTAssertEqual(result.placement, .leading)
        XCTAssertEqual(result.origin, CGPoint(x: 288, y: 189))
        XCTAssertEqual(result.origin.x + 320 + 12, 620, accuracy: 0.5)
    }

    func testPointerAlongEdgeTracksTheAnchorOnTheCard() {
        let along = ReadingOverlayPointerGeometry.alongEdge(
            anchorRect: CGRect(x: 430, y: 280, width: 80, height: 16),
            overlayOrigin: CGPoint(x: 100, y: 100),
            overlaySize: CGSize(width: 320, height: 400),
            placement: .leading
        )

        XCTAssertEqual(along, 188)
        let origin = ReadingOverlayPointerGeometry.origin(
            overlaySize: CGSize(width: 320, height: 400),
            alongEdge: along,
            placement: .leading
        )
        XCTAssertEqual(origin.x, 319)
        XCTAssertEqual(origin.y, 180)

        let trailing = ReadingOverlayPointerGeometry.origin(
            overlaySize: CGSize(width: 320, height: 400),
            alongEdge: along,
            placement: .trailing
        )
        XCTAssertEqual(trailing.x, -10)
        XCTAssertEqual(trailing.y, 180)
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

    func testKeepingPlacementStaysPutWhenContentGrowsOverSelection() {
        let anchor = CGRect(x: 450, y: 450, width: 100, height: 24)
        let initial = ReadingOverlayPlacementPolicy.place(
            input(anchorRect: anchor, overlaySize: CGSize(width: 380, height: 200))
        )

        let grown = ReadingOverlayPlacementPolicy.place(
            input(anchorRect: anchor, overlaySize: CGSize(width: 380, height: 330)),
            keeping: initial.placement
        )

        XCTAssertEqual(initial.placement, .below)
        XCTAssertEqual(grown.placement, .below)
        XCTAssertEqual(grown.origin, initial.origin)
    }

    func testLockedOriginKeepsTopLeftUntilItMustClamp() {
        let origin = CGPoint(x: 310, y: 216)
        let stillFits = ReadingOverlayPlacementPolicy.clamp(
            origin: origin,
            overlaySize: CGSize(width: 380, height: 400),
            containerSize: containerSize,
            horizontalSafeInset: 12,
            verticalSafeInset: 80
        )
        let tooTall = ReadingOverlayPlacementPolicy.clamp(
            origin: origin,
            overlaySize: CGSize(width: 380, height: 700),
            containerSize: containerSize,
            horizontalSafeInset: 12,
            verticalSafeInset: 80
        )

        XCTAssertEqual(stillFits, origin)
        XCTAssertEqual(tooTall, CGPoint(x: 310, y: 80))
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

    func testManualMovementCanReachEveryContainerEdge() {
        let overlaySize = CGSize(width: 380, height: 300)

        let topLeading = ReadingOverlayPlacementPolicy.clamp(
            origin: CGPoint(x: -500, y: -500),
            overlaySize: overlaySize,
            containerSize: containerSize,
            horizontalSafeInset: 12,
            verticalSafeInset: 12
        )
        let bottomTrailing = ReadingOverlayPlacementPolicy.clamp(
            origin: CGPoint(x: 2_000, y: 2_000),
            overlaySize: overlaySize,
            containerSize: containerSize,
            horizontalSafeInset: 12,
            verticalSafeInset: 12
        )

        XCTAssertEqual(topLeading, CGPoint(x: 12, y: 12))
        XCTAssertEqual(bottomTrailing, CGPoint(x: 608, y: 488))
    }

    func testNoteAnchorUsesVisualLastLineWhenStoredRectsAreReversed() {
        let visualTop = CGRect(x: 100, y: 100, width: 760, height: 24)
        let visualMiddle = CGRect(x: 100, y: 132, width: 700, height: 24)
        let visualBottom = CGRect(x: 100, y: 164, width: 200, height: 24)

        let result = NoteAnchorPlacementPolicy.place(
            lineRects: [visualBottom, visualMiddle, visualTop],
            textRects: [],
            containerRect: CGRect(origin: .zero, size: containerSize)
        )

        XCTAssertEqual(result?.placement, .trailing)
        XCTAssertEqual(result?.point, CGPoint(x: 320, y: 176))
    }

    private func input(
        anchorRect: CGRect,
        overlaySize: CGSize,
        placementOrder: [ReadingOverlayPlacement] = ReadingOverlayPlacement.defaultOrder
    ) -> ReadingOverlayPlacementInput {
        ReadingOverlayPlacementInput(
            anchorRect: anchorRect,
            overlaySize: overlaySize,
            containerSize: containerSize,
            preferredGap: 12,
            safeInset: 12,
            placementOrder: placementOrder
        )
    }
}
