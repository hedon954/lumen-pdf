import Foundation

struct PromptTemplateUpdateResult {
    let automaticallyUpdatedLanguages: [String]
    let pendingCustomLanguages: [String]
}

private enum PromptTemplateComponent: String, CaseIterable {
    case wordUser
    case sentenceUser
    case explanationUser
    case wordSystem
    case sentenceSystem
    case explanationSystem

    var title: String {
        switch self {
        case .wordUser: return "单词翻译 User Prompt"
        case .sentenceUser: return "整句翻译 User Prompt"
        case .explanationUser: return "选区解释 User Prompt"
        case .wordSystem: return "单词翻译 System Prompt"
        case .sentenceSystem: return "整句翻译 System Prompt"
        case .explanationSystem: return "选区解释 System Prompt"
        }
    }

    var baseKey: String {
        switch self {
        case .wordUser: return "word_prompt_template"
        case .sentenceUser: return "sentence_prompt_template"
        case .explanationUser: return "explanation_prompt_template"
        case .wordSystem: return "word_system_prompt"
        case .sentenceSystem: return "sentence_system_prompt"
        case .explanationSystem: return "explanation_system_prompt"
        }
    }

    func latest(for language: String) -> String {
        let defaults = PromptTemplateDefaults.defaults(for: language)
        switch self {
        case .wordUser: return defaults.word
        case .sentenceUser: return defaults.sentence
        case .explanationUser: return defaults.explanation
        case .wordSystem: return defaults.wordSystem
        case .sentenceSystem: return defaults.sentenceSystem
        case .explanationSystem: return defaults.explanationSystem
        }
    }

    var builtInDefaults: [String] {
        switch self {
        case .wordUser:
            return [
                PromptTemplateDefaults.wordChinese,
                PromptTemplateDefaults.wordEnglish,
                PromptTemplateDefaults.legacyWordChineseWithEmbeddedEtymology,
                PromptTemplateDefaults.legacyWordEnglishWithEmbeddedEtymology
            ]
        case .sentenceUser:
            return [PromptTemplateDefaults.sentenceChinese, PromptTemplateDefaults.sentenceEnglish]
        case .explanationUser:
            return [
                PromptTemplateDefaults.explanationChinese,
                PromptTemplateDefaults.explanationEnglish,
                PromptTemplateDefaults.legacyExplanation,
                PromptTemplateDefaults.legacyMarkdownExplanation
            ]
        case .wordSystem:
            return [PromptTemplateDefaults.wordSystemChinese, PromptTemplateDefaults.wordSystemEnglish]
        case .sentenceSystem:
            return [
                PromptTemplateDefaults.sentenceSystemChinese,
                PromptTemplateDefaults.sentenceSystemEnglish
            ]
        case .explanationSystem:
            return [
                PromptTemplateDefaults.explanationSystemChinese,
                PromptTemplateDefaults.explanationSystemEnglish,
                PromptTemplateDefaults.legacyExplanationSystem,
                PromptTemplateDefaults.legacyMarkdownExplanationSystem
            ]
        }
    }
}

final class PromptTemplateUpdateCoordinator {
    static let shared = PromptTemplateUpdateCoordinator()

    private let defaults: UserDefaults
    private let supportedLanguages = ["简体中文", "English"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func applyUpdatesAtLaunch() -> PromptTemplateUpdateResult {
        let activeLanguage = defaults.string(forKey: "target_language") ?? "简体中文"
        let activeSuffix = PromptTemplateDefaults.storageSuffix(for: activeLanguage)
        var automaticallyUpdatedLanguages: [String] = []
        var pendingCustomLanguages: [String] = []

        for language in supportedLanguages {
            let suffix = PromptTemplateDefaults.storageSuffix(for: language)
            for component in PromptTemplateComponent.allCases {
                let revisionKey = revisionStorageKey(component: component, suffix: suffix)
                let pendingKey = pendingStorageKey(component: component, suffix: suffix)

                if defaults.integer(forKey: revisionKey) >= PromptTemplateDefaults.templateRevision {
                    defaults.set(false, forKey: pendingKey)
                    continue
                }

                let languageKey = promptStorageKey(component: component, suffix: suffix)
                let storedTemplate = if suffix == activeSuffix {
                    defaults.string(forKey: component.baseKey)
                        ?? defaults.string(forKey: languageKey)
                } else {
                    defaults.string(forKey: languageKey)
                }
                let latestTemplate = component.latest(for: language)

                guard let storedTemplate else {
                    writeLatestTemplate(
                        latestTemplate,
                        component: component,
                        suffix: suffix,
                        activeSuffix: activeSuffix
                    )
                    markHandled(component: component, suffix: suffix)
                    continue
                }

                // Preserve a legacy global-only value in the language slot
                // before deciding whether it is built in or customized.
                defaults.set(storedTemplate, forKey: languageKey)

                let trimmed = storedTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || storedTemplate == latestTemplate {
                    writeLatestTemplate(
                        latestTemplate,
                        component: component,
                        suffix: suffix,
                        activeSuffix: activeSuffix
                    )
                    markHandled(component: component, suffix: suffix)
                } else if component.builtInDefaults.contains(storedTemplate) {
                    writeLatestTemplate(
                        latestTemplate,
                        component: component,
                        suffix: suffix,
                        activeSuffix: activeSuffix
                    )
                    markHandled(component: component, suffix: suffix)
                    appendUnique(language, to: &automaticallyUpdatedLanguages)
                } else {
                    defaults.set(true, forKey: pendingKey)
                    appendUnique(language, to: &pendingCustomLanguages)
                }
            }
        }

        return PromptTemplateUpdateResult(
            automaticallyUpdatedLanguages: automaticallyUpdatedLanguages,
            pendingCustomLanguages: pendingCustomLanguages
        )
    }

    func hasPendingUpdate(for language: String) -> Bool {
        !pendingComponents(for: language).isEmpty
    }

    func pendingTemplateTitles(for language: String) -> [String] {
        pendingComponents(for: language).map(\.title)
    }

    func acceptLatestTemplate(for language: String) {
        let suffix = PromptTemplateDefaults.storageSuffix(for: language)
        let activeLanguage = defaults.string(forKey: "target_language") ?? "简体中文"
        let activeSuffix = PromptTemplateDefaults.storageSuffix(for: activeLanguage)
        for component in pendingComponents(for: language) {
            writeLatestTemplate(
                component.latest(for: language),
                component: component,
                suffix: suffix,
                activeSuffix: activeSuffix
            )
            markHandled(component: component, suffix: suffix)
        }
    }

    func keepCurrentTemplate(for language: String) {
        let suffix = PromptTemplateDefaults.storageSuffix(for: language)
        for component in pendingComponents(for: language) {
            let languageKey = promptStorageKey(component: component, suffix: suffix)
            if defaults.string(forKey: languageKey) == nil,
               let globalTemplate = defaults.string(forKey: component.baseKey)
            {
                defaults.set(globalTemplate, forKey: languageKey)
            }
            markHandled(component: component, suffix: suffix)
        }
    }

    private func pendingComponents(for language: String) -> [PromptTemplateComponent] {
        let suffix = PromptTemplateDefaults.storageSuffix(for: language)
        return PromptTemplateComponent.allCases.filter { component in
            defaults.integer(forKey: revisionStorageKey(component: component, suffix: suffix))
                    < PromptTemplateDefaults.templateRevision
                && defaults.bool(forKey: pendingStorageKey(component: component, suffix: suffix))
        }
    }

    private func writeLatestTemplate(
        _ template: String,
        component: PromptTemplateComponent,
        suffix: String,
        activeSuffix: String
    ) {
        defaults.set(template, forKey: promptStorageKey(component: component, suffix: suffix))
        if suffix == activeSuffix {
            defaults.set(template, forKey: component.baseKey)
        }
    }

    private func markHandled(component: PromptTemplateComponent, suffix: String) {
        defaults.set(
            PromptTemplateDefaults.templateRevision,
            forKey: revisionStorageKey(component: component, suffix: suffix)
        )
        defaults.set(false, forKey: pendingStorageKey(component: component, suffix: suffix))
    }

    private func promptStorageKey(component: PromptTemplateComponent, suffix: String) -> String {
        "\(component.baseKey)_\(suffix)"
    }

    private func revisionStorageKey(component: PromptTemplateComponent, suffix: String) -> String {
        "prompt_template_revision_\(component.rawValue)_\(suffix)"
    }

    private func pendingStorageKey(component: PromptTemplateComponent, suffix: String) -> String {
        "prompt_template_update_pending_\(component.rawValue)_\(suffix)"
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        if !values.contains(value) {
            values.append(value)
        }
    }
}
