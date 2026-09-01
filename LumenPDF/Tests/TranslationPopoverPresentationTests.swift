import XCTest
@testable import LumenPDF

final class TranslationPopoverPresentationTests: XCTestCase {
    func testLanguageLabelsMatchNativeTranslateCopy() {
        let chinese = TranslationPopoverPresentation.languageStyle(targetLanguage: "简体中文")

        XCTAssertEqual(chinese.sourceLabel, "英语 (美国)")
        XCTAssertEqual(chinese.targetLabel, "中文 (普通话，简体)")
        XCTAssertEqual(chinese.sourceSpeechCode, "en-US")
        XCTAssertEqual(chinese.targetSpeechCode, "zh-CN")
        XCTAssertEqual(
            TranslationPopoverPresentation.targetLabel(for: "繁體中文"),
            "中文 (繁體)"
        )
        XCTAssertEqual(TranslationPopoverPresentation.targetSpeechCode(for: "日本語"), "ja-JP")
        XCTAssertEqual(TranslationPopoverPresentation.targetSpeechCode(for: "한국어"), "ko-KR")
        XCTAssertEqual(TranslationPopoverPresentation.targetLabel(for: "English"), "English")
    }

    func testWordModeUsesCorrectedWordAndContextTranslation() {
        let source = TranslationPopoverPresentation.sourceText(
            isSentenceMode: false,
            selectedText: "There\n",
            resultWord: "There"
        )
        let translation = TranslationPopoverPresentation.primaryTranslation(
            isSentenceMode: false,
            contextTranslation: "那里",
            contextSentenceTranslation: "那里有一本书。"
        )

        XCTAssertEqual(source, "There")
        XCTAssertEqual(translation, "那里")
    }

    func testSentenceModePrefersFullSentenceTranslation() {
        let source = TranslationPopoverPresentation.sourceText(
            isSentenceMode: true,
            selectedText: "There is a book.",
            resultWord: "ignored"
        )
        let translation = TranslationPopoverPresentation.primaryTranslation(
            isSentenceMode: true,
            contextTranslation: "那里",
            contextSentenceTranslation: "那里有一本书。"
        )

        XCTAssertEqual(source, "There is a book.")
        XCTAssertEqual(translation, "那里有一本书。")
    }

    func testSentenceModeFallsBackToContextTranslation() {
        let translation = TranslationPopoverPresentation.primaryTranslation(
            isSentenceMode: true,
            contextTranslation: "那里有一本书。",
            contextSentenceTranslation: ""
        )

        XCTAssertEqual(translation, "那里有一本书。")
    }

    func testCopyPayloadIsThePrimaryTranslation() {
        let wordCopy = TranslationPopoverPresentation.primaryTranslation(
            isSentenceMode: false,
            contextTranslation: "那里",
            contextSentenceTranslation: "整句不应作为单词拷贝内容"
        )
        let sentenceCopy = TranslationPopoverPresentation.primaryTranslation(
            isSentenceMode: true,
            contextTranslation: "那里",
            contextSentenceTranslation: "那里有一本书。"
        )

        XCTAssertEqual(wordCopy, "那里")
        XCTAssertEqual(sentenceCopy, "那里有一本书。")
    }
}
