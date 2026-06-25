import Foundation

/// PDF 文本流里常带有按排版插入的换行，展示时合并为一段连贯句子。
enum ContextSentenceFormatting {
    static func displayParagraph(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"([A-Za-z])-\s*\n\s*([A-Za-z])"#,
                with: "$1$2",
                options: .regularExpression
            )
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
