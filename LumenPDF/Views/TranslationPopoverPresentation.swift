import Foundation

/// Layout-independent mapping from current translation data to the native
/// Look Up / Translate popover labels and hero texts.
enum TranslationPopoverPresentation {
    struct LanguageStyle: Equatable {
        let sourceLabel: String
        let targetLabel: String
        let sourceSpeechCode: String
        let targetSpeechCode: String
    }

    static func languageStyle(targetLanguage: String) -> LanguageStyle {
        LanguageStyle(
            sourceLabel: "英语 (美国)",
            targetLabel: targetLabel(for: targetLanguage),
            sourceSpeechCode: "en-US",
            targetSpeechCode: targetSpeechCode(for: targetLanguage)
        )
    }

    static func sourceText(
        isSentenceMode: Bool,
        selectedText: String,
        resultWord: String?
    ) -> String {
        let raw: String
        if isSentenceMode {
            raw = selectedText
        } else if let resultWord, !resultWord.isEmpty {
            raw = resultWord
        } else {
            raw = selectedText
        }
        return ContextSentenceFormatting.displayParagraph(raw)
    }

    /// Word mode uses the contextual word gloss. Sentence mode prefers the
    /// full-sentence translation, then falls back to `contextTranslation`.
    static func primaryTranslation(
        isSentenceMode: Bool,
        contextTranslation: String,
        contextSentenceTranslation: String
    ) -> String {
        if isSentenceMode {
            if !contextSentenceTranslation.isEmpty {
                return contextSentenceTranslation
            }
            return contextTranslation
        }
        return contextTranslation
    }

    static func targetLabel(for language: String) -> String {
        switch language {
        case "简体中文":
            return "中文 (普通话，简体)"
        case "繁體中文":
            return "中文 (繁體)"
        case "English":
            return "English"
        case "日本語":
            return "日本語"
        case "한국어":
            return "한국어"
        default:
            return language.isEmpty ? "中文 (普通话，简体)" : language
        }
    }

    static func showsStreamingProgress(isLoading: Bool, primaryTranslation: String) -> Bool {
        isLoading && primaryTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func targetSpeechCode(for language: String) -> String {
        switch language {
        case "简体中文":
            return "zh-CN"
        case "繁體中文":
            return "zh-TW"
        case "English":
            return "en-US"
        case "日本語":
            return "ja-JP"
        case "한국어":
            return "ko-KR"
        default:
            return "zh-CN"
        }
    }
}
