import Foundation

enum WorkspaceSearchKind: String, CaseIterable, Identifiable, Hashable {
    case note
    case underline
    case word
    case original
    case explanation

    var id: String { rawValue }

    static let defaultEnabled: Set<WorkspaceSearchKind> = [.note, .underline]
    static let minimumQueryLength = 2
    static let extendedHaystackQueryLength = 4

    var title: String {
        switch self {
        case .note: return "笔记"
        case .underline: return "划线"
        case .word: return "单词"
        case .original: return "原文"
        case .explanation: return "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .note: return "note.text"
        case .underline: return "underline"
        case .word: return "character.book.closed"
        case .original: return "doc.plaintext"
        case .explanation: return "sparkles"
        }
    }

    var inspectorMode: ReadingInspectorMode? {
        switch self {
        case .word: return .words
        case .note: return .notes
        case .explanation: return .ai
        case .original, .underline: return nil
        }
    }
}

struct WorkspaceSearchRecord: Identifiable, Equatable {
    let id: String
    let kind: WorkspaceSearchKind
    let title: String
    let subtitle: String
    let haystack: String
    let primaryHaystack: String
    let snippetSource: String
    let pdfPath: String
    let pdfName: String
    let pageIndex: Int
    let boundsStr: String
    let normalizedTitle: String
    let normalizedHaystack: String
    let normalizedPrimary: String

    init(
        id: String,
        kind: WorkspaceSearchKind,
        title: String,
        subtitle: String,
        haystack: String,
        primaryHaystack: String? = nil,
        snippetSource: String,
        pdfPath: String,
        pdfName: String,
        pageIndex: Int,
        boundsStr: String
    ) {
        let primary = primaryHaystack ?? haystack
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.haystack = haystack
        self.primaryHaystack = primary
        self.snippetSource = snippetSource
        self.pdfPath = pdfPath
        self.pdfName = pdfName
        self.pageIndex = pageIndex
        self.boundsStr = boundsStr
        self.normalizedTitle = WorkspaceSearchMatcher.normalize(title)
        self.normalizedHaystack = WorkspaceSearchMatcher.normalize(haystack)
        self.normalizedPrimary = WorkspaceSearchMatcher.normalize(primary)
    }
}

struct WorkspaceSearchHit: Identifiable, Equatable {
    let record: WorkspaceSearchRecord
    let score: Int
    let snippet: String

    var id: String { record.id }
}

struct WorkspaceSearchNoteDraft: Equatable {
    var id: String
    var pdfPath: String
    var pdfName: String
    var pageIndex: Int
    var boundsStr: String
    var content: String
    var noteStorage: String
}

struct WorkspaceSearchWordDraft: Equatable {
    var id: String
    var word: String
    var sentence: String
    var pdfPath: String
    var pdfName: String
    var pageIndex: Int
    var boundsStr: String
    var phonetic: String
    var partOfSpeech: String
    var contextTranslation: String
    var contextExplanation: String
    var etymology: String
    var generalDefinition: String
    var contextSentenceTranslation: String
}

struct WorkspaceSearchUnderlineDraft: Equatable {
    var id: String
    var pdfPath: String
    var pdfName: String
    var pageIndex: Int
    var boundsStr: String
    var text: String
    var type: String
}

struct WorkspaceSearchOriginalDraft: Equatable {
    var id: String
    var pdfPath: String
    var pdfName: String
    var pageIndex: Int
    var text: String
}

struct WorkspaceSearchExplanationDraft: Equatable {
    var id: String
    var pdfPath: String
    var pdfName: String
    var pageIndex: Int
    var boundsStr: String
    var roleTitle: String
    var content: String
}

enum WorkspaceSearchPageChunker {
    static let defaultMaxLength = 480

    static func chunks(from pageText: String, maxLength: Int = defaultMaxLength) -> [String] {
        let collapsed = PDFExtractedTextCollapser.collapse(pageText)
        let lines = collapsed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { ContextSentenceFormatting.displayParagraph($0) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var current = ""
        for line in lines {
            if current.isEmpty {
                current = line
                continue
            }
            if current.count + 1 + line.count <= maxLength {
                current += " " + line
            } else {
                result.append(current)
                current = line
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

enum WorkspaceSearchCatalog {
    static func records(
        notes: [WorkspaceSearchNoteDraft] = [],
        words: [WorkspaceSearchWordDraft] = [],
        underlines: [WorkspaceSearchUnderlineDraft] = [],
        originalChunks: [WorkspaceSearchOriginalDraft] = [],
        explanations: [WorkspaceSearchExplanationDraft] = []
    ) -> [WorkspaceSearchRecord] {
        notes.map(record(from:))
            + words.map(record(from:))
            + underlines.map(record(from:))
            + originalChunks.map(record(from:))
            + explanations.map(record(from:))
    }

    static func record(from note: WorkspaceSearchNoteDraft) -> WorkspaceSearchRecord {
        let noteItems = NoteTextList.decode(note.noteStorage)
        let original = ContextSentenceFormatting.displayParagraph(note.content)
        let title = firstNonEmpty(noteItems) ?? truncated(original, limit: 42)
        let haystack = ([original] + noteItems).joined(separator: "\n")
        return WorkspaceSearchRecord(
            id: "note:\(note.id)",
            kind: .note,
            title: title.isEmpty ? "笔记" : title,
            subtitle: locationSubtitle(pdfName: note.pdfName, pageIndex: note.pageIndex, kind: .note),
            haystack: haystack,
            snippetSource: firstNonEmpty(noteItems) ?? original,
            pdfPath: note.pdfPath,
            pdfName: note.pdfName,
            pageIndex: note.pageIndex,
            boundsStr: note.boundsStr
        )
    }

    static func record(from word: WorkspaceSearchWordDraft) -> WorkspaceSearchRecord {
        let sentence = ContextSentenceFormatting.displayParagraph(word.sentence)
        let primary = [
            word.word,
            word.phonetic,
            word.contextTranslation,
            word.generalDefinition
        ].joined(separator: "\n")
        let haystack = [
            primary,
            word.partOfSpeech,
            word.contextExplanation,
            word.etymology,
            sentence,
            word.contextSentenceTranslation
        ].joined(separator: "\n")
        return WorkspaceSearchRecord(
            id: "word:\(word.id)",
            kind: .word,
            title: word.word.isEmpty ? "单词" : word.word,
            subtitle: locationSubtitle(pdfName: word.pdfName, pageIndex: word.pageIndex, kind: .word),
            haystack: haystack,
            primaryHaystack: primary,
            snippetSource: firstNonEmpty([
                word.contextTranslation,
                word.generalDefinition,
                word.contextExplanation,
                sentence
            ]) ?? word.word,
            pdfPath: word.pdfPath,
            pdfName: word.pdfName,
            pageIndex: word.pageIndex,
            boundsStr: word.boundsStr
        )
    }

    static func record(from underline: WorkspaceSearchUnderlineDraft) -> WorkspaceSearchRecord {
        let text = ContextSentenceFormatting.displayParagraph(underline.text)
        let kindLabel = underline.type == "highlight" ? "高亮" : "划线"
        return WorkspaceSearchRecord(
            id: "underline:\(underline.pdfPath)#\(underline.pageIndex)#\(underline.boundsStr)",
            kind: .underline,
            title: truncated(text, limit: 42).isEmpty ? kindLabel : truncated(text, limit: 42),
            subtitle: locationSubtitle(
                pdfName: underline.pdfName,
                pageIndex: underline.pageIndex,
                kind: .underline,
                extra: kindLabel
            ),
            haystack: text,
            snippetSource: text,
            pdfPath: underline.pdfPath,
            pdfName: underline.pdfName,
            pageIndex: underline.pageIndex,
            boundsStr: underline.boundsStr
        )
    }

    static func record(from chunk: WorkspaceSearchOriginalDraft) -> WorkspaceSearchRecord {
        let text = ContextSentenceFormatting.displayParagraph(chunk.text)
        return WorkspaceSearchRecord(
            id: chunk.id,
            kind: .original,
            title: truncated(text, limit: 42).isEmpty ? "原文" : truncated(text, limit: 42),
            subtitle: locationSubtitle(pdfName: chunk.pdfName, pageIndex: chunk.pageIndex, kind: .original),
            haystack: text,
            snippetSource: text,
            pdfPath: chunk.pdfPath,
            pdfName: chunk.pdfName,
            pageIndex: chunk.pageIndex,
            boundsStr: ""
        )
    }

    static func record(from explanation: WorkspaceSearchExplanationDraft) -> WorkspaceSearchRecord {
        let content = explanation.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceSearchRecord(
            id: "explanation:\(explanation.id)",
            kind: .explanation,
            title: truncated(content, limit: 42).isEmpty ? explanation.roleTitle : truncated(content, limit: 42),
            subtitle: locationSubtitle(
                pdfName: explanation.pdfName,
                pageIndex: explanation.pageIndex,
                kind: .explanation,
                extra: explanation.roleTitle
            ),
            haystack: content,
            snippetSource: content,
            pdfPath: explanation.pdfPath,
            pdfName: explanation.pdfName,
            pageIndex: explanation.pageIndex,
            boundsStr: explanation.boundsStr
        )
    }

    private static func locationSubtitle(
        pdfName: String,
        pageIndex: Int,
        kind: WorkspaceSearchKind,
        extra: String? = nil
    ) -> String {
        var parts = [kind.title]
        if let extra, !extra.isEmpty, extra != kind.title {
            parts.append(extra)
        }
        if !pdfName.isEmpty {
            parts.append(pdfName)
        }
        parts.append("P\(pageIndex + 1)")
        return parts.joined(separator: " · ")
    }

    private static func firstNonEmpty(_ values: [String]) -> String? {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

enum WorkspaceSearchMatcher {
    static let resultLimit = 40
    static let snippetRadius = 48

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{00ad}", with: "")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    static func tokens(in query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func hits(
        query: String,
        records: [WorkspaceSearchRecord],
        enabledKinds: Set<WorkspaceSearchKind>,
        limit: Int = resultLimit
    ) -> [WorkspaceSearchHit] {
        let tokens = tokens(in: query)
        let needle = tokens.joined(separator: " ")
        guard needle.count >= WorkspaceSearchKind.minimumQueryLength else { return [] }

        let kinds = enabledKinds.isEmpty ? WorkspaceSearchKind.defaultEnabled : enabledKinds
        let useExtendedHaystack = needle.count >= WorkspaceSearchKind.extendedHaystackQueryLength

        let ranked = records.compactMap { record -> WorkspaceSearchHit? in
            guard kinds.contains(record.kind) else { return nil }
            let title = record.normalizedTitle
            let body = useExtendedHaystack ? record.normalizedHaystack : record.normalizedPrimary
            let blob = title.isEmpty ? body : "\(title) \(body)"
            guard tokens.allSatisfy({ blob.contains($0) }) else { return nil }

            var score = 0
            if title == needle {
                score += 500
            } else if title.hasPrefix(needle) {
                score += 360
            } else if title.contains(needle) {
                score += 240
            }
            for token in tokens where title.contains(token) {
                score += 50
            }
            if body.contains(needle) {
                score += 70
            }
            for token in tokens where body.contains(token) {
                score += 8
            }
            if record.kind == .original {
                score -= min(40, record.normalizedHaystack.count / 80)
            }

            return WorkspaceSearchHit(
                record: record,
                score: score,
                snippet: snippet(from: record.snippetSource, tokens: tokens)
            )
        }

        let kindOrder = Dictionary(
            uniqueKeysWithValues: WorkspaceSearchKind.allCases.enumerated().map { ($1, $0) }
        )
        return ranked
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let leftKind = kindOrder[lhs.record.kind] ?? 0
                let rightKind = kindOrder[rhs.record.kind] ?? 0
                if leftKind != rightKind { return leftKind < rightKind }
                if lhs.record.pageIndex != rhs.record.pageIndex {
                    return lhs.record.pageIndex < rhs.record.pageIndex
                }
                return lhs.record.title.localizedStandardCompare(rhs.record.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    static func snippet(from text: String, tokens: [String], radius: Int = snippetRadius) -> String {
        let source = ContextSentenceFormatting.displayParagraph(text)
        guard !source.isEmpty else { return "" }
        let lowered = source.lowercased()
        let match = tokens
            .compactMap { token -> Range<String.Index>? in
                lowered.range(of: token.lowercased())
            }
            .min(by: { $0.lowerBound < $1.lowerBound })

        guard let match else {
            if source.count <= radius * 2 { return source }
            return String(source.prefix(radius * 2)).trimmingCharacters(in: .whitespaces) + "…"
        }

        let startDistance = source.distance(from: source.startIndex, to: match.lowerBound)
        let endDistance = source.distance(from: source.startIndex, to: match.upperBound)
        let startOffset = max(0, startDistance - radius)
        let endOffset = min(source.count, endDistance + radius)
        let start = source.index(source.startIndex, offsetBy: startOffset)
        let end = source.index(source.startIndex, offsetBy: endOffset)
        var snippet = String(source[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if startOffset > 0 { snippet = "…" + snippet }
        if endOffset < source.count { snippet += "…" }
        return snippet
    }
}
