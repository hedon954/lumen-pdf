import XCTest
@testable import LumenPDF

final class TextLineMarkupMergeTests: XCTestCase {
    private final class UndoTarget: NSObject {}

    private final class UndoStateTarget: NSObject {
        var value = 0

        func setValue(_ newValue: Int, using manager: UndoManager) {
            let previousValue = value
            manager.registerUndo(withTarget: self) { target in
                target.setValue(previousValue, using: manager)
            }
            value = newValue
        }
    }

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

    func testPageMarkupCodecRoundTripsCrossPageGeometry() {
        let markups = [
            PDFPageMarkup(pageIndex: 8, lineRects: [line(0, x: 50, width: 220)], text: "first"),
            PDFPageMarkup(pageIndex: 9, lineRects: [line(1, x: 60, width: 180)], text: "second"),
        ]

        let encoded = PDFPageMarkupCodec.encode(markups)
        let decoded = PDFPageMarkupCodec.decode(encoded, fallbackPage: 0, fallbackBoundsStr: "")

        XCTAssertTrue(UnderlineNoteMergePolicy.sameGeometry(decoded, markups))
        XCTAssertEqual(decoded.map(\.pageIndex), [8, 9])
    }

    func testPageMarkupCodecFallsBackForLegacySinglePageNote() {
        let boundsStr = AnnotationBoundsCodec.string(from: [line(2, x: 70, width: 160)])

        let decoded = PDFPageMarkupCodec.decode(
            "",
            fallbackPage: 12,
            fallbackBoundsStr: boundsStr,
            fallbackText: "legacy"
        )

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].pageIndex, 12)
        XCTAssertEqual(decoded[0].boundsStr, boundsStr)
        XCTAssertEqual(decoded[0].text, "legacy")
    }

    func testCrossPageCoverageRequiresEverySelectedPage() {
        let selected = [
            PDFPageMarkup(pageIndex: 3, lineRects: [line(0, x: 80, width: 100)], text: ""),
            PDFPageMarkup(pageIndex: 4, lineRects: [line(1, x: 80, width: 100)], text: ""),
        ]
        let onlyFirstPage = [
            PDFPageMarkup(pageIndex: 3, lineRects: [line(0, x: 50, width: 300)], text: ""),
        ]

        XCTAssertFalse(UnderlineNoteMergePolicy.markups(selected, areCoveredBy: onlyFirstPage))
        XCTAssertTrue(UnderlineNoteMergePolicy.markups(selected, overlap: onlyFirstPage))
    }

    func testCrossPageMergeKeepsGeometryOnBothPages() {
        let existing = [
            PDFPageMarkup(pageIndex: 6, lineRects: [line(0, x: 50, width: 120)], text: ""),
        ]
        let selected = [
            PDFPageMarkup(pageIndex: 6, lineRects: [line(0, x: 160, width: 100)], text: ""),
            PDFPageMarkup(pageIndex: 7, lineRects: [line(1, x: 50, width: 240)], text: ""),
        ]

        let merged = UnderlineNoteMergePolicy.mergePageMarkups([existing, selected])

        XCTAssertEqual(merged.map(\.pageIndex), [6, 7])
        XCTAssertEqual(merged[0].lineRects.count, 1)
        XCTAssertEqual(merged[0].lineRects[0].minX, 50, accuracy: 0.1)
        XCTAssertEqual(merged[0].lineRects[0].maxX, 260, accuracy: 0.1)
    }

    func testFreeAndNoteUnderlinesShareTheSamePageMarkupPayload() throws {
        let center = NotificationCenter()
        let bus = ReaderEventBus(center: center)
        let markups = [
            PDFPageMarkup(pageIndex: 2, lineRects: [line(0, x: 30, width: 180)], text: "first"),
            PDFPageMarkup(pageIndex: 3, lineRects: [line(1, x: 40, width: 150)], text: "second"),
        ]
        var freeUserInfo: [AnyHashable: Any]?
        var noteUserInfo: [AnyHashable: Any]?
        let freeToken = center.addObserver(forName: .addFreeAnnotation, object: nil, queue: nil) {
            freeUserInfo = $0.userInfo
        }
        let noteToken = center.addObserver(forName: .addUnderlineNote, object: nil, queue: nil) {
            noteUserInfo = $0.userInfo
        }
        defer {
            center.removeObserver(freeToken)
            center.removeObserver(noteToken)
        }

        bus.postFreeAnnotations(type: "underline", markups: markups, filePath: "/tmp/book.pdf")
        bus.postAddUnderlineNote(noteId: "note-1", markups: markups, filePath: "/tmp/book.pdf")

        XCTAssertEqual(try XCTUnwrap(freeUserInfo?["pageIndexes"] as? [Int]), [2, 3])
        XCTAssertEqual(
            try XCTUnwrap(freeUserInfo?["pageIndexes"] as? [Int]),
            try XCTUnwrap(noteUserInfo?["pageIndexes"] as? [Int])
        )
        XCTAssertEqual(
            try XCTUnwrap(freeUserInfo?["boundsStrs"] as? [String]),
            try XCTUnwrap(noteUserInfo?["boundsStrs"] as? [String])
        )
    }

    func testSelectionJumpCarriesEveryNotePageMarkup() throws {
        let center = NotificationCenter()
        let bus = ReaderEventBus(center: center)
        let markups = [
            PDFPageMarkup(pageIndex: 4, lineRects: [line(0, x: 30, width: 180)], text: "first"),
            PDFPageMarkup(pageIndex: 5, lineRects: [line(1, x: 40, width: 150)], text: "second"),
        ]
        var userInfo: [AnyHashable: Any]?
        let token = center.addObserver(forName: .jumpToSelectionBounds, object: nil, queue: nil) {
            userInfo = $0.userInfo
        }
        defer { center.removeObserver(token) }

        bus.postJumpToSelectionBounds(
            page: 4,
            filePath: "/tmp/book.pdf",
            boundsStr: markups[0].boundsStr,
            markups: markups,
            itemId: "note:n1",
            kind: "note"
        )

        XCTAssertEqual(try XCTUnwrap(userInfo?["pageIndexes"] as? [Int]), [4, 5])
        XCTAssertEqual(try XCTUnwrap(userInfo?["boundsStrs"] as? [String]), markups.map(\.boundsStr))
        XCTAssertEqual(userInfo?["pageIndex"] as? Int, 4)
        XCTAssertEqual(userInfo?["boundsStr"] as? String, markups[0].boundsStr)
    }

    @MainActor
    func testReaderUndoHistoryKeepsFiftyTopLevelActions() {
        let manager = UndoManager()
        let target = UndoTarget()
        ReaderUndoHistoryPolicy.configure(manager)
        manager.groupsByEvent = false

        for index in 0..<(ReaderUndoHistoryPolicy.capacity + 5) {
            manager.beginUndoGrouping()
            manager.registerUndo(withTarget: target) { _ in }
            manager.setActionName("操作 \(index)")
            manager.endUndoGrouping()
        }

        XCTAssertGreaterThanOrEqual(
            ReaderUndoHistoryPolicy.capacity,
            ReaderUndoHistoryPolicy.minimumRequiredLevels
        )
        XCTAssertEqual(manager.undoCount, ReaderUndoHistoryPolicy.capacity)
    }

    @MainActor
    func testClearingReaderUndoActionsPreservesOtherWindowHistory() {
        let manager = UndoManager()
        let reader = UndoTarget()
        let textEditor = UndoTarget()
        ReaderUndoHistoryPolicy.configure(manager)
        manager.groupsByEvent = false

        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: reader) { _ in }
        manager.setActionName("划线")
        manager.endUndoGrouping()

        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: textEditor) { _ in }
        manager.setActionName("输入")
        manager.endUndoGrouping()

        ReaderUndoHistoryPolicy.clearActions(for: reader, from: manager)

        XCTAssertEqual(manager.undoCount, 1)
        XCTAssertEqual(manager.undoActionName, "输入")
    }

    @MainActor
    func testNewUndoableActionClearsThePreviousRedoBranch() {
        let manager = UndoManager()
        let target = UndoStateTarget()
        ReaderUndoHistoryPolicy.configure(manager)
        manager.groupsByEvent = false

        manager.beginUndoGrouping()
        target.setValue(1, using: manager)
        manager.endUndoGrouping()
        manager.undo()

        XCTAssertEqual(target.value, 0)
        XCTAssertTrue(manager.canRedo)

        manager.beginUndoGrouping()
        target.setValue(2, using: manager)
        manager.endUndoGrouping()

        XCTAssertEqual(target.value, 2)
        XCTAssertFalse(manager.canRedo)
    }

    func testNoteUndoSnapshotPreservesIdentityAndCreationOrder() {
        let markups = [
            PDFPageMarkup(pageIndex: 7, lineRects: [line(0, x: 50, width: 220)], text: "selection")
        ]
        let entry = NoteEntry(
            id: "stable-note-id",
            pdfPath: "/tmp/book.pdf",
            pdfName: "book.pdf",
            pageIndex: 7,
            content: "selection",
            note: NoteTextList.encode(["memo"]),
            boundsStr: markups[0].boundsStr,
            pageMarkups: PDFPageMarkupCodec.encode(markups),
            createdAt: 123
        )

        let restored = NoteUndoInfo(entry).entry

        XCTAssertEqual(restored.id, entry.id)
        XCTAssertEqual(restored.createdAt, entry.createdAt)
        XCTAssertEqual(restored.pageMarkups, entry.pageMarkups)
        XCTAssertEqual(restored.note, entry.note)
    }

    func testMergedNoteTextKeepsItemsSeparate() {
        let merged = UnderlineNoteMergePolicy.mergedNoteText(
            existing: [NoteTextList.encode(["第一条", "第二条"])],
            new: "第三条"
        )

        XCTAssertEqual(NoteTextList.decode(merged), ["第一条", "第二条", "第三条"])
    }
}
