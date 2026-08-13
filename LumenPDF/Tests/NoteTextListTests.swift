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
}
