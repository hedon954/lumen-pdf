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
}
