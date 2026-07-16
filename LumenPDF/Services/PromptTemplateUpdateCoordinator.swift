import Foundation

struct PromptTemplateUpdateResult {
    let automaticallyUpdatedLanguages: [String]
    let pendingCustomLanguages: [String]
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
            let revisionKey = revisionStorageKey(suffix: suffix)
            let pendingKey = pendingStorageKey(suffix: suffix)

            if defaults.integer(forKey: revisionKey) >= PromptTemplateDefaults.wordTemplateRevision {
                defaults.set(false, forKey: pendingKey)
                continue
            }

            let languageKey = promptStorageKey(suffix: suffix)
            let storedTemplate = if suffix == activeSuffix {
                defaults.string(forKey: "word_prompt_template")
                    ?? defaults.string(forKey: languageKey)
            } else {
                defaults.string(forKey: languageKey)
            }
            let latestTemplate = PromptTemplateDefaults.defaults(for: language).word

            guard let storedTemplate else {
                writeLatestTemplate(latestTemplate, suffix: suffix, activeSuffix: activeSuffix)
                markHandled(suffix: suffix)
                continue
            }

            // Preserve a legacy global-only value in the language-specific slot
            // before deciding whether it is built-in or customized.
            defaults.set(storedTemplate, forKey: languageKey)

            if storedTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || storedTemplate == latestTemplate
            {
                writeLatestTemplate(latestTemplate, suffix: suffix, activeSuffix: activeSuffix)
                markHandled(suffix: suffix)
            } else if PromptTemplateDefaults.wordBuiltInDefaults.contains(storedTemplate) {
                writeLatestTemplate(latestTemplate, suffix: suffix, activeSuffix: activeSuffix)
                markHandled(suffix: suffix)
                automaticallyUpdatedLanguages.append(language)
            } else {
                defaults.set(true, forKey: pendingKey)
                pendingCustomLanguages.append(language)
            }
        }

        return PromptTemplateUpdateResult(
            automaticallyUpdatedLanguages: automaticallyUpdatedLanguages,
            pendingCustomLanguages: pendingCustomLanguages
        )
    }

    func hasPendingUpdate(for language: String) -> Bool {
        let suffix = PromptTemplateDefaults.storageSuffix(for: language)
        return defaults.integer(forKey: revisionStorageKey(suffix: suffix))
                < PromptTemplateDefaults.wordTemplateRevision
            && defaults.bool(forKey: pendingStorageKey(suffix: suffix))
    }

    func acceptLatestTemplate(for language: String) {
        let suffix = PromptTemplateDefaults.storageSuffix(for: language)
        let activeLanguage = defaults.string(forKey: "target_language") ?? "简体中文"
        let activeSuffix = PromptTemplateDefaults.storageSuffix(for: activeLanguage)
        let latestTemplate = PromptTemplateDefaults.defaults(for: language).word
        writeLatestTemplate(latestTemplate, suffix: suffix, activeSuffix: activeSuffix)
        markHandled(suffix: suffix)
    }

    func keepCurrentTemplate(for language: String) {
        let suffix = PromptTemplateDefaults.storageSuffix(for: language)
        let languageKey = promptStorageKey(suffix: suffix)
        if defaults.string(forKey: languageKey) == nil,
           let globalTemplate = defaults.string(forKey: "word_prompt_template")
        {
            defaults.set(globalTemplate, forKey: languageKey)
        }
        markHandled(suffix: suffix)
    }

    private func writeLatestTemplate(
        _ template: String,
        suffix: String,
        activeSuffix: String
    ) {
        defaults.set(template, forKey: promptStorageKey(suffix: suffix))
        if suffix == activeSuffix {
            defaults.set(template, forKey: "word_prompt_template")
        }
    }

    private func markHandled(suffix: String) {
        defaults.set(
            PromptTemplateDefaults.wordTemplateRevision,
            forKey: revisionStorageKey(suffix: suffix)
        )
        defaults.set(false, forKey: pendingStorageKey(suffix: suffix))
    }

    private func promptStorageKey(suffix: String) -> String {
        "word_prompt_template_\(suffix)"
    }

    private func revisionStorageKey(suffix: String) -> String {
        "word_prompt_template_revision_\(suffix)"
    }

    private func pendingStorageKey(suffix: String) -> String {
        "word_prompt_template_update_pending_\(suffix)"
    }
}
