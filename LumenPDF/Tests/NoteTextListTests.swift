import XCTest
@testable import LumenPDF

final class NoteTextListTests: XCTestCase {
    func testRemovingOneItemKeepsTheRemainingItems() {
        let stored = NoteTextList.encode(["第一条", "第二条", "第三条"])

        let updated = NoteTextList.removingItem(at: 1, from: stored)

        XCTAssertEqual(updated.map { NoteTextList.decode($0) }, ["第一条", "第三条"])
    }

    func testRemovingLastItemReturnsEmptyStorage() {
        let stored = NoteTextList.encode(["唯一一条"])

        let updated = NoteTextList.removingItem(at: 0, from: stored)

        XCTAssertEqual(updated, "")
    }

    func testRemovingUnknownItemDoesNotChangeStorage() {
        let stored = NoteTextList.encode(["第一条"])

        XCTAssertNil(NoteTextList.removingItem(at: 1, from: stored))
    }

    func testReplacingItemUpdatesOnlyTheTargetedNote() {
        let stored = NoteTextList.encode(["第一条", "第二条", "第三条"])

        let updated = NoteTextList.replacingItem(at: 1, with: "  改过的第二条  ", from: stored)

        XCTAssertEqual(updated.map { NoteTextList.decode($0) }, ["第一条", "改过的第二条", "第三条"])
    }

    func testReplacingUnknownOrEmptyItemDoesNotChangeStorage() {
        let stored = NoteTextList.encode(["第一条"])

        XCTAssertNil(NoteTextList.replacingItem(at: 1, with: "新内容", from: stored))
        XCTAssertNil(NoteTextList.replacingItem(at: 0, with: "   ", from: stored))
    }

    func testAutoSavePolicyIgnoresUnchangedAndEmptyText() {
        XCTAssertEqual(NoteAutoSavePolicy.textToSave("新内容", lastSaved: "旧内容"), "新内容")
        XCTAssertNil(NoteAutoSavePolicy.textToSave("  旧内容  ", lastSaved: "旧内容"))
        XCTAssertNil(NoteAutoSavePolicy.textToSave("   ", lastSaved: "旧内容"))
    }

    func testDelayedEditorCannotOverwriteShiftedItemAfterDeletion() {
        let stored = NoteTextList.encode(["第二条", "第三条"])
        XCTAssertNil(NoteTextList.replacingItem(
            at: 0, with: "第一条的延迟保存", from: stored,
            expectedText: "第一条", expectedCount: 3
        ))
        // Even identical adjacent text must not make an old editor target a new row.
        XCTAssertNil(NoteTextList.replacingItem(
            at: 0, with: "过期修改", from: NoteTextList.encode(["重复"]),
            expectedText: "重复", expectedCount: 2
        ))
    }

    func testEditingThenDeletingAnotherItemKeepsLatestText() {
        let stored = NoteTextList.encode(["第一条", "第二条", "第三条"])
        let edited = NoteTextList.replacingItem(
            at: 1, with: "已修改", from: stored, expectedText: "第二条", expectedCount: 3
        )!
        let deleted = NoteTextList.removingItem(at: 0, from: edited)!
        XCTAssertEqual(NoteTextList.decode(deleted), ["已修改", "第三条"])
        let editedAgain = NoteTextList.replacingItem(
            at: 0, with: "再次修改", from: deleted, expectedText: "已修改", expectedCount: 2
        )!
        XCTAssertEqual(NoteTextList.decode(editedAgain), ["再次修改", "第三条"])
    }
}
