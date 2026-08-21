import XCTest
@testable import LumenPDF

final class TextLineMarkupMergeTests: XCTestCase {
    /// Tight PDFKit line boxes: 18pt tall on 16pt leading, so neighbors overlap by 2pt.
    private func line(_ index: Int, x: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: x, y: 600 - CGFloat(index) * 16, width: width, height: 18)
    }

    func testNewRegionBelowDoesNotDeletePreviousLineEvenIfUnionBoxesOverlap() {
        let existing = [
            [line(0, x: 50, width: 300)],
            [line(1, x: 50, width: 300)],
            [line(2, x: 50, width: 300)],
            [line(3, x: 50, width: 220)],
        ]
        let selection = [
            line(3, x: 278, width: 70),
            line(4, x: 50, width: 300),
            line(5, x: 50, width: 300),
        ]

        let unionBox = selection.dropFirst().reduce(selection[0]) { $0.union($1) }
        XCTAssertTrue(
            existing[2][0].intersects(unionBox),
            "The old union-box test would have treated the previous line as overlapping."
        )

        let plan = TextLineMarkupMerge.plan(existingGroups: existing, selection: selection)
        XCTAssertEqual(plan.interactingGroupIndices, [3])
        XCTAssertFalse(plan.interactingGroupIndices.contains(2))
        XCTAssertTrue(plan.addRects.contains { $0.isSameTextLine(as: selection[1]) })
        XCTAssertTrue(
            plan.addRects.contains { rect in
                rect.isSameTextLine(as: existing[3][0]) && rect.minX <= 50 && rect.maxX >= 340
            }
        )
    }

    func testNonOverlappingSelectionOnlyAdds() {
        let existing = [[line(0, x: 50, width: 300)], [line(1, x: 50, width: 300)]]
        let selection = [line(4, x: 50, width: 280), line(5, x: 50, width: 280)]
        let plan = TextLineMarkupMerge.plan(existingGroups: existing, selection: selection)
        XCTAssertTrue(plan.interactingGroupIndices.isEmpty)
        XCTAssertEqual(plan.addRects.count, 2)
    }

    func testFullyCoveredSelectionTogglesOffOnlyThatCoverage() {
        let existing = [
            [line(0, x: 50, width: 300)],
            [line(1, x: 50, width: 300)],
            [line(2, x: 50, width: 300)],
        ]
        let selection = [line(1, x: 50, width: 300)]
        let plan = TextLineMarkupMerge.plan(existingGroups: existing, selection: selection)
        XCTAssertEqual(plan.interactingGroupIndices, [1])
        XCTAssertTrue(plan.addRects.isEmpty)
    }

    func testPartialOverlapOnOneLineMergesAndKeepsTheRest() {
        let existing = [[line(0, x: 50, width: 200)], [line(1, x: 50, width: 120)]]
        let selection = [line(1, x: 140, width: 160)]
        let plan = TextLineMarkupMerge.plan(existingGroups: existing, selection: selection)
        XCTAssertEqual(plan.interactingGroupIndices, [1])
        XCTAssertEqual(plan.addRects.count, 1)
        XCTAssertEqual(plan.addRects[0].minX, 50, accuracy: 0.1)
        XCTAssertEqual(plan.addRects[0].maxX, 300, accuracy: 0.1)
        XCTAssertTrue(plan.addRects[0].isSameTextLine(as: existing[1][0]))
    }

    func testSubtractingTheMiddleOfALineSplitsTheRemainder() {
        let existing = [line(0, x: 50, width: 300)]
        let cut = [line(0, x: 120, width: 80)]
        let remaining = TextLineMarkupMerge.subtracting(cut, from: existing)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].minX, 50, accuracy: 0.1)
        XCTAssertEqual(remaining[0].maxX, 120, accuracy: 0.1)
        XCTAssertEqual(remaining[1].minX, 200, accuracy: 0.1)
        XCTAssertEqual(remaining[1].maxX, 350, accuracy: 0.1)
    }

    func testSameLineGapWithinAdjacentToleranceMerges() {
        let left = line(0, x: 50, width: 200)
        let right = line(0, x: 256, width: 80)
        XCTAssertLessThanOrEqual(right.minX - left.maxX, TextLineMarkupMerge.adjacentGap)
        let merged = TextLineMarkupMerge.merge([left, right])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].minX, 50, accuracy: 0.1)
        XCTAssertEqual(merged[0].maxX, 336, accuracy: 0.1)
    }

    func testDistantSameLineRunsStaySeparate() {
        let left = line(0, x: 50, width: 80)
        let right = line(0, x: 200, width: 80)
        XCTAssertGreaterThan(right.minX - left.maxX, TextLineMarkupMerge.adjacentGap)
        XCTAssertEqual(TextLineMarkupMerge.merge([left, right]).count, 2)
    }

    func testAdjacentLineBoxesWithVerticalOverlapAreNotHorizontalOverlap() {
        let upper = line(2, x: 50, width: 300)
        let lower = line(3, x: 50, width: 300)
        XCTAssertTrue(upper.intersects(lower))
        XCTAssertFalse(upper.isSameTextLine(as: lower))
        XCTAssertFalse(TextLineMarkupMerge.overlaps([upper], [lower]))
    }

    func testMultiLineHighlightGroupInteractsOnlyThroughRealLineOverlap() {
        let existingHighlight = [
            line(0, x: 50, width: 300),
            line(1, x: 50, width: 300),
            line(2, x: 50, width: 220),
        ]
        let selection = [line(4, x: 50, width: 300), line(5, x: 50, width: 300)]
        let plan = TextLineMarkupMerge.plan(existingGroups: [existingHighlight], selection: selection)
        XCTAssertTrue(plan.interactingGroupIndices.isEmpty)
        XCTAssertEqual(plan.addRects.count, 2)
    }
}
