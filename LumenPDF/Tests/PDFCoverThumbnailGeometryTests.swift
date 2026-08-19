import XCTest
@testable import LumenPDF

final class PDFCoverThumbnailGeometryTests: XCTestCase {
    func testAspectFitKeepsPortraitPageInsideTheDisplayBox() {
        let fitted = PDFCoverThumbnailGeometry.aspectFit(
            CGSize(width: 612, height: 792),
            in: CGSize(width: 36, height: 48)
        )

        XCTAssertEqual(fitted.width, 36, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 46.59, accuracy: 0.05)
    }

    func testAspectFitLetterboxesLandscapePages() {
        let fitted = PDFCoverThumbnailGeometry.aspectFit(
            CGSize(width: 792, height: 612),
            in: CGSize(width: 36, height: 48)
        )

        XCTAssertEqual(fitted.width, 36, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 27.82, accuracy: 0.05)
    }

    func testPixelSizeUsesRetinaScale() {
        let pixels = PDFCoverThumbnailGeometry.pixelSize(
            pageSize: CGSize(width: 100, height: 100),
            fitting: CGSize(width: 36, height: 48),
            scale: 2
        )

        XCTAssertEqual(pixels, CGSize(width: 72, height: 72))
    }

    func testCacheKeyChangesWhenTheFileIsReplaced() {
        let path = "/tmp/book.pdf"
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = Date(timeIntervalSince1970: 1_700_000_100)

        XCTAssertNotEqual(
            PDFCoverThumbnailGeometry.cacheKey(filePath: path, modificationDate: first),
            PDFCoverThumbnailGeometry.cacheKey(filePath: path, modificationDate: second)
        )
    }
}
