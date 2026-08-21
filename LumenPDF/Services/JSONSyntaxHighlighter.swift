import AppKit
import Foundation

enum JSONSyntaxTokenKind: Equatable {
    case key
    case string
    case number
    case keyword
    case punctuation
    case plain
}

struct JSONSyntaxToken: Equatable {
    let range: NSRange
    let kind: JSONSyntaxTokenKind
}

enum JSONSyntaxHighlighter {
    static func tokens(in text: String) -> [JSONSyntaxToken] {
        let nsText = text as NSString
        let length = nsText.length
        var index = 0
        var tokens: [JSONSyntaxToken] = []

        while index < length {
            let character = nsText.character(at: index)
            if isWhitespace(character) {
                index += 1
                continue
            }
            if isPunctuation(character) {
                tokens.append(JSONSyntaxToken(range: NSRange(location: index, length: 1), kind: .punctuation))
                index += 1
                continue
            }
            if character == 0x22 {
                let (range, next) = scanString(in: nsText, from: index)
                let after = skipWhitespace(in: nsText, from: next)
                let kind: JSONSyntaxTokenKind =
                    after < length && nsText.character(at: after) == 0x3A ? .key : .string
                tokens.append(JSONSyntaxToken(range: range, kind: kind))
                index = next
                continue
            }
            if isNumberStart(character, in: nsText, at: index) {
                let (range, next) = scanNumber(in: nsText, from: index)
                tokens.append(JSONSyntaxToken(range: range, kind: .number))
                index = next
                continue
            }
            if let (range, next) = scanKeyword(in: nsText, from: index) {
                tokens.append(JSONSyntaxToken(range: range, kind: .keyword))
                index = next
                continue
            }
            tokens.append(JSONSyntaxToken(range: NSRange(location: index, length: 1), kind: .plain))
            index += 1
        }
        return tokens
    }

    static func attributedString(
        from text: String,
        font: NSFont,
        colors: JSONSyntaxColors = .system
    ) -> NSAttributedString {
        let output = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: colors.plain
            ]
        )
        for token in tokens(in: text) {
            output.addAttribute(.foregroundColor, value: colors.color(for: token.kind), range: token.range)
        }
        return output
    }
}

struct JSONSyntaxColors {
    var key: NSColor
    var string: NSColor
    var number: NSColor
    var keyword: NSColor
    var punctuation: NSColor
    var plain: NSColor

    static let system = JSONSyntaxColors(
        key: .systemPurple,
        string: .systemOrange,
        number: .systemBlue,
        keyword: .systemPink,
        punctuation: .secondaryLabelColor,
        plain: .labelColor
    )

    func color(for kind: JSONSyntaxTokenKind) -> NSColor {
        switch kind {
        case .key: return key
        case .string: return string
        case .number: return number
        case .keyword: return keyword
        case .punctuation: return punctuation
        case .plain: return plain
        }
    }
}

private func isWhitespace(_ character: unichar) -> Bool {
    character == 0x20 || character == 0x09 || character == 0x0A || character == 0x0D
}

private func isPunctuation(_ character: unichar) -> Bool {
    character == 0x7B || character == 0x7D || character == 0x5B || character == 0x5D
        || character == 0x3A || character == 0x2C
}

private func isDigit(_ character: unichar) -> Bool {
    character >= 0x30 && character <= 0x39
}

private func isNumberStart(_ character: unichar, in text: NSString, at index: Int) -> Bool {
    if isDigit(character) {
        return true
    }
    if character == 0x2D, index + 1 < text.length, isDigit(text.character(at: index + 1)) {
        return true
    }
    return false
}

private func skipWhitespace(in text: NSString, from index: Int) -> Int {
    var cursor = index
    while cursor < text.length, isWhitespace(text.character(at: cursor)) {
        cursor += 1
    }
    return cursor
}

private func scanString(in text: NSString, from start: Int) -> (NSRange, Int) {
    var cursor = start + 1
    while cursor < text.length {
        let character = text.character(at: cursor)
        if character == 0x5C {
            cursor += cursor + 1 < text.length ? 2 : 1
            continue
        }
        if character == 0x22 {
            return (NSRange(location: start, length: cursor - start + 1), cursor + 1)
        }
        cursor += 1
    }
    return (NSRange(location: start, length: text.length - start), text.length)
}

private func scanNumber(in text: NSString, from start: Int) -> (NSRange, Int) {
    var cursor = start
    if text.character(at: cursor) == 0x2D {
        cursor += 1
    }
    while cursor < text.length, isDigit(text.character(at: cursor)) {
        cursor += 1
    }
    if cursor < text.length, text.character(at: cursor) == 0x2E {
        cursor += 1
        while cursor < text.length, isDigit(text.character(at: cursor)) {
            cursor += 1
        }
    }
    if cursor < text.length {
        let exponent = text.character(at: cursor)
        if exponent == 0x65 || exponent == 0x45 {
            cursor += 1
            if cursor < text.length {
                let sign = text.character(at: cursor)
                if sign == 0x2B || sign == 0x2D {
                    cursor += 1
                }
            }
            while cursor < text.length, isDigit(text.character(at: cursor)) {
                cursor += 1
            }
        }
    }
    return (NSRange(location: start, length: cursor - start), cursor)
}

private func scanKeyword(in text: NSString, from start: Int) -> (NSRange, Int)? {
    for keyword in ["true", "false", "null"] as [NSString] {
        let length = keyword.length
        if start + length <= text.length,
           text.substring(with: NSRange(location: start, length: length)) == (keyword as String)
        {
            let boundary = start + length
            if boundary == text.length || !isKeywordContinue(text.character(at: boundary)) {
                return (NSRange(location: start, length: length), boundary)
            }
        }
    }
    return nil
}

private func isKeywordContinue(_ character: unichar) -> Bool {
    (character >= 0x41 && character <= 0x5A)
        || (character >= 0x61 && character <= 0x7A)
        || isDigit(character)
        || character == 0x5F
}
