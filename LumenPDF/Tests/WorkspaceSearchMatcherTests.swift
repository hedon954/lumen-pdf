import XCTest
@testable import LumenPDF

final class WorkspaceSearchMatcherTests: XCTestCase {
    func testEmptyQueryReturnsNoHits() {
        let records = WorkspaceSearchCatalog.records(notes: [Self.note(content: "Concurrency control")])

        XCTAssertTrue(
            WorkspaceSearchMatcher.hits(
                query: "   ",
                records: records,
                enabledKinds: Set(WorkspaceSearchKind.allCases)
            ).isEmpty
        )
    }

    func testNoteMatchesUserNoteAndOriginal() {
        let records = WorkspaceSearchCatalog.records(
            notes: [
                Self.note(
                    id: "n1",
                    content: "deterministic scheduling",
                    noteStorage: NoteTextList.encode(["需要对照 DST 实验"])
                )
            ]
        )

        let originalHits = WorkspaceSearchMatcher.hits(
            query: "Deterministic",
            records: records,
            enabledKinds: [.note]
        )
        let noteHits = WorkspaceSearchMatcher.hits(
            query: "DST 实验",
            records: records,
            enabledKinds: [.note]
        )

        XCTAssertEqual(originalHits.map(\.record.id), ["note:n1"])
        XCTAssertEqual(noteHits.map(\.record.id), ["note:n1"])
    }

    func testWordMatchesDefinitionAndEtymology() {
        let records = WorkspaceSearchCatalog.records(
            words: [
                WorkspaceSearchWordDraft(
                    id: "w1",
                    word: "scheduler",
                    sentence: "The scheduler records the random choices.",
                    pdfPath: "/tmp/a.pdf",
                    pdfName: "a.pdf",
                    pageIndex: 2,
                    boundsStr: "{{1, 1}, {10, 10}}",
                    phonetic: "",
                    partOfSpeech: "n.",
                    contextTranslation: "调度器",
                    contextExplanation: "负责记录随机选择",
                    etymology: "from Greek skedannymi",
                    generalDefinition: "a component that decides order",
                    contextSentenceTranslation: "调度器会记录随机选择。"
                )
            ]
        )

        XCTAssertEqual(
            WorkspaceSearchMatcher.hits(query: "调度器", records: records, enabledKinds: [.word])
                .map(\.record.title),
            ["scheduler"]
        )
        XCTAssertEqual(
            WorkspaceSearchMatcher.hits(query: "skedannymi", records: records, enabledKinds: [.word])
                .map(\.record.id),
            ["word:w1"]
        )
    }

    func testKindFilterExcludesOtherCategories() {
        let records = WorkspaceSearchCatalog.records(
            notes: [Self.note(id: "n1", content: "latency budget")],
            words: [
                WorkspaceSearchWordDraft(
                    id: "w1",
                    word: "latency",
                    sentence: "",
                    pdfPath: "/tmp/a.pdf",
                    pdfName: "a.pdf",
                    pageIndex: 0,
                    boundsStr: "",
                    phonetic: "",
                    partOfSpeech: "",
                    contextTranslation: "延迟",
                    contextExplanation: "",
                    etymology: "",
                    generalDefinition: "",
                    contextSentenceTranslation: ""
                )
            ]
        )

        let onlyNotes = WorkspaceSearchMatcher.hits(
            query: "latency",
            records: records,
            enabledKinds: [.note]
        )
        XCTAssertEqual(onlyNotes.map(\.record.kind), [.note])
    }

    func testMultiTokenQueryRequiresEveryToken() {
        let records = WorkspaceSearchCatalog.records(
            originalChunks: [
                WorkspaceSearchOriginalDraft(
                    id: "o1",
                    pdfPath: "/tmp/a.pdf",
                    pdfName: "a.pdf",
                    pageIndex: 4,
                    text: "Deterministic scheduling keeps every randomized execution reproducible."
                )
            ]
        )

        XCTAssertFalse(
            WorkspaceSearchMatcher.hits(
                query: "deterministic scheduling",
                records: records,
                enabledKinds: [.original]
            ).isEmpty
        )
        XCTAssertTrue(
            WorkspaceSearchMatcher.hits(
                query: "deterministic missing",
                records: records,
                enabledKinds: [.original]
            ).isEmpty
        )
    }

    func testTitleMatchRanksAboveHaystackMatch() {
        let records = [
            WorkspaceSearchRecord(
                id: "body",
                kind: .original,
                title: "Chapter notes",
                subtitle: "原文 · P1",
                haystack: "scheduler appears only in the body",
                snippetSource: "scheduler appears only in the body",
                pdfPath: "/tmp/a.pdf",
                pdfName: "a.pdf",
                pageIndex: 0,
                boundsStr: ""
            ),
            WorkspaceSearchRecord(
                id: "title",
                kind: .word,
                title: "scheduler",
                subtitle: "单词 · P2",
                haystack: "unrelated",
                snippetSource: "unrelated",
                pdfPath: "/tmp/a.pdf",
                pdfName: "a.pdf",
                pageIndex: 1,
                boundsStr: ""
            )
        ]

        let hits = WorkspaceSearchMatcher.hits(
            query: "scheduler",
            records: records,
            enabledKinds: Set(WorkspaceSearchKind.allCases)
        )
        XCTAssertEqual(hits.map(\.record.id), ["title", "body"])
    }

    func testSnippetExtractsTextAroundTheMatch() {
        let paragraph =
            "The scheduler records the random choices so later reruns can replay them without surprise."
        let snippet = WorkspaceSearchMatcher.snippet(
            from: paragraph,
            tokens: ["random", "choices"]
        )

        XCTAssertTrue(snippet.contains("random choices"))
        XCTAssertTrue(snippet.contains("scheduler") || snippet.hasPrefix("…"))
    }

    func testPageChunkerKeepsSearchableParagraphs() {
        let page = """
        Concurrency control

        Many systems use locks to protect shared state.
        Deterministic scheduling keeps every randomized execution reproducible.
        """
        let chunks = WorkspaceSearchPageChunker.chunks(from: page, maxLength: 80)

        XCTAssertFalse(chunks.isEmpty)
        let records = chunks.enumerated().map { index, text in
            WorkspaceSearchOriginalDraft(
                id: "p0-\(index)",
                pdfPath: "/tmp/a.pdf",
                pdfName: "a.pdf",
                pageIndex: 0,
                text: text
            )
        }
        let hits = WorkspaceSearchMatcher.hits(
            query: "deterministic scheduling",
            records: WorkspaceSearchCatalog.records(originalChunks: records),
            enabledKinds: [.original]
        )
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits[0].snippet.lowercased().contains("deterministic"))
    }

    func testExplanationDraftsAreSearchable() {
        let records = WorkspaceSearchCatalog.records(
            explanations: [
                WorkspaceSearchExplanationDraft(
                    id: "m1",
                    pdfPath: "/tmp/a.pdf",
                    pdfName: "a.pdf",
                    pageIndex: 3,
                    boundsStr: "{{0, 0}, {1, 1}}",
                    roleTitle: "AI 解释",
                    content: "这段在讲可重放的调度顺序。"
                )
            ]
        )

        XCTAssertEqual(
            WorkspaceSearchMatcher.hits(
                query: "可重放",
                records: records,
                enabledKinds: [.explanation]
            ).map(\.record.kind),
            [.explanation]
        )
    }

    func testCaseInsensitiveMatch() {
        let records = WorkspaceSearchCatalog.records(
            notes: [Self.note(id: "n1", content: "Concurrency control")]
        )
        XCTAssertEqual(
            WorkspaceSearchMatcher.hits(
                query: "CONCURRENCY",
                records: records,
                enabledKinds: [.note]
            ).map(\.record.id),
            ["note:n1"]
        )
    }

    private static func note(
        id: String = "n1",
        content: String,
        noteStorage: String = ""
    ) -> WorkspaceSearchNoteDraft {
        WorkspaceSearchNoteDraft(
            id: id,
            pdfPath: "/tmp/a.pdf",
            pdfName: "a.pdf",
            pageIndex: 1,
            boundsStr: "{{10, 20}, {100, 12}}",
            content: content,
            noteStorage: noteStorage
        )
    }
}
