import CoreGraphics
import Foundation

/// Translation popover sizing inherited from the main branch implementation.
enum TranslationPopoverGeometry {
    static let minWidth: CGFloat = 340
    static let maxWidth: CGFloat = 760

    static func contentWidth(
        isSentenceMode: Bool,
        textCount: Int,
        availableWidth: CGFloat
    ) -> CGFloat {
        let usable = max(availableWidth, 420)
        let cap = min(max(minWidth, usable - 96), maxWidth)
        let base: CGFloat = isSentenceMode ? 560 : 380
        return min(max(base, CGFloat(textCount) * 4.2), cap)
    }

    static func initialContentHeight(
        isSentenceMode: Bool,
        showsFailure: Bool
    ) -> CGFloat {
        if showsFailure { return 248 }
        return isSentenceMode ? 160 : 120
    }

    static func selectionFrame(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width, 1),
            height: max(rect.height, 1)
        )
    }
}

/// One source of truth for the four compact header controls.
enum TranslationHeaderControlMetrics {
    static let count = 4
    static let size: CGFloat = 28
    static let spacing: CGFloat = 4
}
