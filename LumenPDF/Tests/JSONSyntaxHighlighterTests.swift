import XCTest
@testable import LumenPDF

final class JSONSyntaxHighlighterTests: XCTestCase {
    func testHighlightsKeysStringsNumbersAndKeywords() {
        let source = #"{"enable_thinking": false, "n": 1, "name": "qwen"}"#
        let tokens = JSONSyntaxHighlighter.tokens(in: source)
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.key))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.punctuation))
    }

    func testUnclosedStringIsStillHighlighted() {
        let tokens = JSONSyntaxHighlighter.tokens(in: #"{"foo": "bar"#)
        XCTAssertEqual(tokens.last?.kind, .string)
    }
}
