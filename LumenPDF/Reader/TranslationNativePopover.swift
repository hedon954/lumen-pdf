import CoreGraphics
import Foundation

/// Layout helpers shared by the translation overlay. Pure geometry; no I/O.
enum TranslationPopoverGeometry {
    static let minWidth: CGFloat = 280
    static let maxWidth: CGFloat = 760

    static func contentWidth(
        isSentenceMode: Bool,
        textCount: Int,
        availableWidth: CGFloat
    ) -> CGFloat {
        let usable = max(availableWidth, 420)
        let cap = min(max(minWidth, usable - 96), maxWidth)
        let base: CGFloat = isSentenceMode ? 560 : 320
        return min(max(base, CGFloat(textCount) * 4.2), cap)
    }
}
