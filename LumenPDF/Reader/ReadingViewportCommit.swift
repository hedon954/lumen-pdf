import Foundation

/// Decides which captured reading position is allowed to replace the last stable one.
///
/// PDFKit can move `currentPage` back to an earlier page while a window is closing or
/// while a restore pass is still settling. That jump is not the user leaving the page
/// they were just reading, and writing it would make the next launch reopen too early.
enum ReadingViewportCommit {
    static func pageIndex(of viewport: ReadingRestorationState.PDFViewport) -> Int? {
        if let anchor = viewport.anchor, anchor.isValid {
            return anchor.pageIndex
        }
        return viewport.pageIndex
    }

    static func restorePageIndex(
        viewport: ReadingRestorationState.PDFViewport?,
        savedPage: Int
    ) -> Int {
        if let viewport, let page = pageIndex(of: viewport) {
            return page
        }
        return savedPage
    }

    static func accepting(
        stable: ReadingRestorationState.PDFViewport?,
        live: ReadingRestorationState.PDFViewport,
        userScrollEvent: Bool,
        recentUserScroll: Bool
    ) -> ReadingRestorationState.PDFViewport {
        guard let stable else { return normalized(live) }
        guard let stablePage = pageIndex(of: stable),
              let livePage = pageIndex(of: live) else {
            return normalized(userScrollEvent ? live : stable)
        }
        if userScrollEvent {
            return normalized(live)
        }
        if livePage + 1 < stablePage {
            return normalized(stable)
        }
        if samePageAnchorJumped(from: stable, to: live) {
            return normalized(stable)
        }
        if recentUserScroll || livePage >= stablePage {
            return normalized(live)
        }
        return normalized(stable)
    }

    private static func samePageAnchorJumped(
        from stable: ReadingRestorationState.PDFViewport,
        to live: ReadingRestorationState.PDFViewport
    ) -> Bool {
        guard let stableAnchor = stable.anchor, stableAnchor.isValid,
              let liveAnchor = live.anchor, liveAnchor.isValid,
              stableAnchor.pageIndex == liveAnchor.pageIndex else { return false }
        return abs(liveAnchor.y - stableAnchor.y) > 240
    }

    private static func normalized(
        _ viewport: ReadingRestorationState.PDFViewport
    ) -> ReadingRestorationState.PDFViewport {
        var copy = viewport
        if let page = pageIndex(of: viewport) {
            copy.pageIndex = page
        }
        return copy
    }
}
