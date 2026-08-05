import XCTest
@testable import LumenPDF

final class ReaderViewportGeometryTests: XCTestCase {
    private let visibleSize = CGSize(width: 800, height: 600)

    func testVisibleTopLeftUsesTheLeadingEdgeOfAFlippedDocument() {
        let topLeft = ReaderViewportGeometry.visibleTopLeft(
            of: CGRect(x: 40, y: 4_000, width: 800, height: 600),
            isDocumentFlipped: true
        )

        XCTAssertEqual(topLeft, CGPoint(x: 40, y: 4_000))
    }

    func testVisibleTopLeftUsesTheUpperEdgeOfAnUnflippedDocument() {
        let topLeft = ReaderViewportGeometry.visibleTopLeft(
            of: CGRect(x: 40, y: 4_000, width: 800, height: 600),
            isDocumentFlipped: false
        )

        XCTAssertEqual(topLeft, CGPoint(x: 40, y: 4_600))
    }

    func testScrollOriginRoundTripsTheVisibleTopLeftOfAFlippedDocument() {
        let visibleRect = CGRect(x: 40, y: 4_000, width: 800, height: 600)
        let documentSize = CGSize(width: 1_000, height: 10_000)
        let topLeft = ReaderViewportGeometry.visibleTopLeft(
            of: visibleRect,
            isDocumentFlipped: true
        )

        let origin = ReaderViewportGeometry.scrollOrigin(
            visibleTopLeft: topLeft,
            visibleSize: visibleRect.size,
            documentSize: documentSize,
            isDocumentFlipped: true
        )

        XCTAssertEqual(origin, visibleRect.origin)
    }

    func testScrollOriginRoundTripsTheVisibleTopLeftOfAnUnflippedDocument() {
        let visibleRect = CGRect(x: 40, y: 4_000, width: 800, height: 600)
        let documentSize = CGSize(width: 1_000, height: 10_000)
        let topLeft = ReaderViewportGeometry.visibleTopLeft(
            of: visibleRect,
            isDocumentFlipped: false
        )

        let origin = ReaderViewportGeometry.scrollOrigin(
            visibleTopLeft: topLeft,
            visibleSize: visibleRect.size,
            documentSize: documentSize,
            isDocumentFlipped: false
        )

        XCTAssertEqual(origin, visibleRect.origin)
    }

    /// The regression this whole anchor exists for: PDFKit re-fits the document while the window
    /// frame and split widths are restored, and an anchored position must survive that.
    func testAnchoredPositionIsUnaffectedByADocumentThatGrewWhileRestoring() {
        let capturedTopLeft = CGPoint(x: 0, y: 4_000)

        let origin = ReaderViewportGeometry.scrollOrigin(
            visibleTopLeft: capturedTopLeft,
            visibleSize: visibleSize,
            documentSize: CGSize(width: 800, height: 12_000),
            isDocumentFlipped: true
        )

        XCTAssertEqual(origin.y, 4_000)
    }

    func testNormalizedPositionDriftsWhenTheDocumentGrewWhileRestoring() {
        // 4 000 pt into a 10 000 pt tall layout, stored as a fraction of the scrollable range.
        let capturedFraction = 4_000.0 / (10_000.0 - Double(visibleSize.height))

        let origin = ReaderViewportGeometry.scrollOrigin(
            normalizedHorizontal: 0,
            normalizedVertical: capturedFraction,
            visibleSize: visibleSize,
            documentSize: CGSize(width: 800, height: 12_000)
        )

        XCTAssertGreaterThan(origin.y - 4_000, visibleSize.height)
    }

    func testScrollOriginClampsToTheScrollableRange() {
        let documentSize = CGSize(width: 900, height: 5_000)

        let beyondEnd = ReaderViewportGeometry.scrollOrigin(
            visibleTopLeft: CGPoint(x: 10_000, y: 20_000),
            visibleSize: visibleSize,
            documentSize: documentSize,
            isDocumentFlipped: true
        )
        let beforeStart = ReaderViewportGeometry.scrollOrigin(
            visibleTopLeft: CGPoint(x: -400, y: -900),
            visibleSize: visibleSize,
            documentSize: documentSize,
            isDocumentFlipped: true
        )

        XCTAssertEqual(beyondEnd, CGPoint(x: 100, y: 4_400))
        XCTAssertEqual(beforeStart, .zero)
    }

    func testScrollOriginIsZeroWhenTheDocumentFitsInTheViewport() {
        let origin = ReaderViewportGeometry.scrollOrigin(
            normalizedHorizontal: 1,
            normalizedVertical: 1,
            visibleSize: visibleSize,
            documentSize: CGSize(width: 400, height: 300)
        )

        XCTAssertEqual(origin, .zero)
    }

    func testNormalizedScrollOriginIgnoresNonFiniteFractions() {
        let origin = ReaderViewportGeometry.scrollOrigin(
            normalizedHorizontal: .nan,
            normalizedVertical: .infinity,
            visibleSize: visibleSize,
            documentSize: CGSize(width: 1_000, height: 10_000)
        )

        XCTAssertEqual(origin, .zero)
    }
}

final class ReadingRestorationViewportCodingTests: XCTestCase {
    func testViewportSavedBeforeAnchorsStillDecodes() throws {
        let legacy = Data(
            """
            {
              "pageIndex": 12,
              "autoScales": false,
              "scaleFactor": 1.4,
              "horizontalOffset": 0.25,
              "verticalOffset": 0.5
            }
            """.utf8
        )

        let viewport = try JSONDecoder().decode(
            ReadingRestorationState.PDFViewport.self,
            from: legacy
        )

        XCTAssertNil(viewport.anchor)
        XCTAssertEqual(viewport.pageIndex, 12)
        XCTAssertEqual(viewport.verticalOffset, 0.5)
    }

    func testViewportRoundTripsItsAnchor() throws {
        let viewport = ReadingRestorationState.PDFViewport(
            pageIndex: 12,
            autoScales: true,
            scaleFactor: 1,
            horizontalOffset: 0,
            verticalOffset: 0.5,
            anchor: .init(pageIndex: 11, x: 36, y: 512)
        )

        let decoded = try JSONDecoder().decode(
            ReadingRestorationState.PDFViewport.self,
            from: JSONEncoder().encode(viewport)
        )

        XCTAssertEqual(decoded, viewport)
    }

    func testAnchorIsInvalidWhenItsPageOrPointIsUnusable() {
        XCTAssertFalse(
            ReadingRestorationState.PDFViewport.PageAnchor(pageIndex: -1, x: 0, y: 0).isValid
        )
        XCTAssertFalse(
            ReadingRestorationState.PDFViewport.PageAnchor(pageIndex: 3, x: .nan, y: 0).isValid
        )
        XCTAssertTrue(
            ReadingRestorationState.PDFViewport.PageAnchor(pageIndex: 3, x: 12, y: 40).isValid
        )
    }
}
