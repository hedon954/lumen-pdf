import XCTest
@testable import LumenPDF

final class JSONAutoIndenterTests: XCTestCase {
    func testEnterBetweenBracesInsertsIndentedBlankLine() {
        let edit = JSONAutoIndenter.newlineEdit(before: "{", after: "}")
        XCTAssertEqual(edit.replacement, "\n  \n")
        XCTAssertEqual(edit.cursorOffset, 3)
        XCTAssertEqual(String(edit.replacement.prefix(edit.cursorOffset)), "\n  ")

        let result = "{" + edit.replacement + "}"
        XCTAssertEqual(result, "{\n  \n}")
    }

    func testEnterAfterCommaKeepsObjectIndent() {
        let before = "{\n  \"a\": 1,"
        let edit = JSONAutoIndenter.newlineEdit(before: before, after: "\n}")
        XCTAssertEqual(edit.replacement, "\n  ")
        XCTAssertEqual(
            before + edit.replacement + "\n}",
            "{\n  \"a\": 1,\n  \n}"
        )
    }

    func testEnterInsideNestedObjectUsesDeeperIndent() {
        let before = "{\n  \"k\": {"
        let edit = JSONAutoIndenter.newlineEdit(before: before, after: "}}")
        XCTAssertEqual(edit.replacement, "\n    \n  ")
        XCTAssertEqual(edit.cursorOffset, 5)
    }

    func testBracesInsideStringsDoNotChangeIndent() {
        XCTAssertEqual(JSONAutoIndenter.indentLevel(in: #"{"a": "{not a block"}"#), 1)
        let edit = JSONAutoIndenter.newlineEdit(
            before: "{\n  \"a\": \"{not a block\",",
            after: "\n}"
        )
        XCTAssertEqual(edit.replacement, "\n  ")
    }

    func testClosingBraceOnOverIndentedLineOutdents() {
        let before = "{\n    "
        let edit = try XCTUnwrap(JSONAutoIndenter.closingBracketEdit(before: before, bracket: "}"))
        XCTAssertEqual(edit.linePrefixLength, 4)
        XCTAssertEqual(edit.replacement, "}")
    }

    func testClosingBraceOnCorrectIndentLeavesTypingAlone() {
        XCTAssertNil(JSONAutoIndenter.closingBracketEdit(before: "{\n", bracket: "}"))
        XCTAssertNil(JSONAutoIndenter.closingBracketEdit(before: "{\n  \"a\": 1", bracket: "}"))
    }
}
