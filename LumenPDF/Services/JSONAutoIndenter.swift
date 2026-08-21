import Foundation

enum JSONAutoIndenter {
    static let indentWidth = 2

    struct NewlineEdit: Equatable {
        let replacement: String
        let cursorOffset: Int
    }

    struct ClosingEdit: Equatable {
        let linePrefixLength: Int
        let replacement: String
    }

    static func indentLevel(in text: String) -> Int {
        var level = 0
        var inString = false
        var escaped = false
        for character in text {
            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if character == "\\" {
                    escaped = true
                    continue
                }
                if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
                continue
            }
            if character == "{" || character == "[" {
                level += 1
            } else if character == "}" || character == "]" {
                level = max(0, level - 1)
            }
        }
        return level
    }

    static func newlineEdit(before: String, after: String) -> NewlineEdit {
        let level = indentLevel(in: before)
        let inner = String(repeating: " ", count: level * indentWidth)
        let trimmedAfter = after.drop(while: { $0 == " " || $0 == "\t" })
        if let first = trimmedAfter.first, first == "}" || first == "]" {
            let outer = String(repeating: " ", count: max(0, level - 1) * indentWidth)
            let replacement = "\n\(inner)\n\(outer)"
            return NewlineEdit(replacement: replacement, cursorOffset: 1 + inner.count)
        }
        let replacement = "\n\(inner)"
        return NewlineEdit(replacement: replacement, cursorOffset: replacement.count)
    }

    static func closingBracketEdit(before: String, bracket: Character) -> ClosingEdit? {
        guard bracket == "}" || bracket == "]" else { return nil }
        let line = currentLinePrefix(before)
        guard !line.isEmpty, line.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        let target = max(0, indentLevel(in: before) - 1) * indentWidth
        let prefixLength = line.utf16.count
        guard prefixLength != target else { return nil }
        return ClosingEdit(
            linePrefixLength: prefixLength,
            replacement: String(repeating: " ", count: target) + String(bracket)
        )
    }

    private static func currentLinePrefix(_ before: String) -> String {
        if let index = before.lastIndex(of: "\n") {
            return String(before[before.index(after: index)...])
        }
        return before
    }
}
