import CoreGraphics
import Foundation

struct PDFSelectionContext: Identifiable, Equatable {
    let id: UUID
    let pdfPath: String
    let pdfName: String
    let pageIndex: Int
    let selectedText: String
    let surroundingText: String
    let bounds: CGRect
    let boundsStr: String

    init(
        id: UUID = UUID(),
        pdfPath: String,
        pdfName: String,
        pageIndex: Int,
        selectedText: String,
        surroundingText: String,
        bounds: CGRect,
        boundsStr: String
    ) {
        self.id = id
        self.pdfPath = pdfPath
        self.pdfName = pdfName
        self.pageIndex = pageIndex
        self.selectedText = selectedText
        self.surroundingText = surroundingText
        self.bounds = bounds
        self.boundsStr = boundsStr
    }
}
