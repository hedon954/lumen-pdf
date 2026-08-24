import SwiftUI

struct SettingsView: View {
    /// When non-nil, this view is shown as a setup sheet; the closure is called to dismiss it.
    var onDismiss: (() -> Void)? = nil

    @AppStorage("llm_base_url") private var baseURL = ""
    @AppStorage("llm_model") private var model = ""
    @AppStorage("target_language") private var targetLanguage = "简体中文"
    @AppStorage("word_prompt_template") private var wordPromptTemplate = PromptTemplateDefaults.word
    @AppStorage("sentence_prompt_template") private var sentencePromptTemplate = PromptTemplateDefaults.sentence
    @AppStorage("explanation_prompt_template") private var explanationPromptTemplate = PromptTemplateDefaults.explanation
    @AppStorage("word_system_prompt") private var wordSystemPrompt = PromptTemplateDefaults.wordSystem
    @AppStorage("sentence_system_prompt") private var sentenceSystemPrompt = PromptTemplateDefaults.sentenceSystem
    @AppStorage("explanation_system_prompt") private var explanationSystemPrompt = PromptTemplateDefaults.explanationSystem

    @State private var apiKey = ""
    @State private var extraConfig = ""
    @State private var selectedDestination: SettingsDestination = .llm
    @State private var selectedPromptKind: PromptTemplateKind = .word
    @State private var showSavedBadge = false
    @State private var saveErrorMessage: String?
    @State private var loadedPromptLanguage = "简体中文"
    @State private var pendingUpdateTitles: [String] = []
    @StateObject private var llmConfiguration = LLMConfigurationModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDestination) {
                Section("设置") {
                    ForEach(SettingsDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                detail
                Divider()
                saveBar
            }
        }
        .toolbarVisibility(.visible, for: .windowToolbar)
        .onAppear(perform: load)
        .onChange(of: targetLanguage) { _, newLanguage in
            persistPromptTemplates(for: loadedPromptLanguage)
            loadPromptTemplates(for: newLanguage, replacingLegacyDefaults: false)
            loadedPromptLanguage = newLanguage
            refreshPromptUpdateState()
            _ = applyRuntimeConfig()
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }

    private var saveBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if showSavedBadge {
                    Label("设置已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let saveErrorMessage {
                    Label {
                        Text(saveErrorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    .help(saveErrorMessage)
                    .accessibilityIdentifier("settings.saveError")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let dismiss = onDismiss {
                Button("稍后设置", action: dismiss)
                    .buttonStyle(.borderless)
            }
            Button("保存设置") {
                if saveSettings() {
                    onDismiss?()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedDestination {
        case .llm:
            LLMSettingsPage(
                baseURL: $baseURL,
                apiKey: $apiKey,
                model: $model,
                extraConfig: $extraConfig,
                configuration: llmConfiguration,
                onSubmit: { _ = saveSettings() }
            )
        case .translation:
            TranslationSettingsPage(targetLanguage: $targetLanguage)
        case .prompts:
            PromptSettingsPage(
                selectedKind: $selectedPromptKind,
                wordPrompt: $wordPromptTemplate,
                sentencePrompt: $sentencePromptTemplate,
                explanationPrompt: $explanationPromptTemplate,
                wordSystemPrompt: $wordSystemPrompt,
                sentenceSystemPrompt: $sentenceSystemPrompt,
                explanationSystemPrompt: $explanationSystemPrompt,
                defaults: activePromptDefaults,
                pendingUpdateTitles: pendingUpdateTitles,
                onKeepCustomTemplates: keepCustomTemplates,
                onAcceptLatestTemplates: acceptLatestTemplates
            )
        case .logs:
            LLMCallLogSettingsPage()
        case .usage:
            LLMUsageSettingsPage(currentModel: $model)
        }
    }

    private var activePromptDefaults: PromptTemplateDefaults.LanguageDefaults {
        PromptTemplateDefaults.defaults(for: targetLanguage)
    }

    private func load() {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL: String
        if trimmedBaseURL.isEmpty {
            resolvedBaseURL = ""
        } else {
            resolvedBaseURL = BridgeService.normalizedLLMBaseURL(trimmedBaseURL)
            if resolvedBaseURL != baseURL {
                baseURL = resolvedBaseURL
            }
        }
        apiKey = KeychainService.loadLLMAPIKey(for: resolvedBaseURL) ?? ""
        extraConfig = LLMSettingsStore().effectiveExtraConfig(for: resolvedBaseURL, model: model)
        llmConfiguration.remember(baseURL: baseURL, model: model)
        if llmConfiguration.shouldAutomaticallyRefresh(baseURL: baseURL, apiKey: apiKey) {
            Task {
                await llmConfiguration.refreshModels(baseURL: baseURL, apiKey: apiKey)
            }
        }
        loadedPromptLanguage = targetLanguage
        migratePromptDefaultsIfNeeded()
        loadPromptTemplates(for: targetLanguage, replacingLegacyDefaults: true)
        refreshPromptUpdateState()
    }

    private func migratePromptDefaultsIfNeeded() {
        if explanationSystemPrompt == PromptTemplateDefaults.legacyExplanationSystem
            || explanationSystemPrompt == PromptTemplateDefaults.legacyMarkdownExplanationSystem
        {
            explanationSystemPrompt = PromptTemplateDefaults.explanationSystem
        }
        if explanationPromptTemplate == PromptTemplateDefaults.legacyExplanation
            || explanationPromptTemplate == PromptTemplateDefaults.legacyMarkdownExplanation
        {
            explanationPromptTemplate = PromptTemplateDefaults.explanation
        }
    }

    private func refreshPromptUpdateState() {
        pendingUpdateTitles =
            PromptTemplateUpdateCoordinator.shared.pendingTemplateTitles(for: targetLanguage)
    }

    private func keepCustomTemplates() {
        PromptTemplateUpdateCoordinator.shared.keepCurrentTemplate(for: targetLanguage)
        refreshPromptUpdateState()
    }

    private func acceptLatestTemplates() {
        PromptTemplateUpdateCoordinator.shared.acceptLatestTemplate(for: targetLanguage)
        loadPromptTemplates(for: targetLanguage, replacingLegacyDefaults: false)
        refreshPromptUpdateState()
        _ = applyRuntimeConfig()
    }

    private func promptStorageKey(_ baseKey: String, language: String) -> String {
        "\(baseKey)_\(PromptTemplateDefaults.storageSuffix(for: language))"
    }

    private func persistPromptTemplates(for language: String) {
        let defaults = UserDefaults.standard
        defaults.set(wordPromptTemplate, forKey: promptStorageKey("word_prompt_template", language: language))
        defaults.set(sentencePromptTemplate, forKey: promptStorageKey("sentence_prompt_template", language: language))
        defaults.set(explanationPromptTemplate, forKey: promptStorageKey("explanation_prompt_template", language: language))
        defaults.set(wordSystemPrompt, forKey: promptStorageKey("word_system_prompt", language: language))
        defaults.set(sentenceSystemPrompt, forKey: promptStorageKey("sentence_system_prompt", language: language))
        defaults.set(explanationSystemPrompt, forKey: promptStorageKey("explanation_system_prompt", language: language))
    }

    private func loadPromptTemplates(for language: String, replacingLegacyDefaults: Bool) {
        let defaults = UserDefaults.standard
        let languageDefaults = PromptTemplateDefaults.defaults(for: language)

        func template(
            _ baseKey: String,
            currentValue: String,
            languageDefault: String,
            legacyDefaults: [String] = []
        ) -> String {
            let key = promptStorageKey(baseKey, language: language)
            let languageBuiltInDefaults = [
                languageDefaults.word,
                languageDefaults.sentence,
                languageDefaults.explanation,
                languageDefaults.wordSystem,
                languageDefaults.sentenceSystem,
                languageDefaults.explanationSystem
            ]

            if let stored = defaults.string(forKey: key) {
                if PromptTemplateDefaults.allBuiltInDefaults.contains(stored)
                    && !languageBuiltInDefaults.contains(stored)
                {
                    return languageDefault
                }
                return stored
            }
            if replacingLegacyDefaults
                && (legacyDefaults + PromptTemplateDefaults.allBuiltInDefaults).contains(currentValue)
            {
                return languageDefault
            }
            return languageDefault
        }

        wordPromptTemplate = template(
            "word_prompt_template",
            currentValue: wordPromptTemplate,
            languageDefault: languageDefaults.word
        )
        sentencePromptTemplate = template(
            "sentence_prompt_template",
            currentValue: sentencePromptTemplate,
            languageDefault: languageDefaults.sentence
        )
        explanationPromptTemplate = template(
            "explanation_prompt_template",
            currentValue: explanationPromptTemplate,
            languageDefault: languageDefaults.explanation,
            legacyDefaults: [
                PromptTemplateDefaults.legacyExplanation,
                PromptTemplateDefaults.legacyMarkdownExplanation
            ]
        )
        wordSystemPrompt = template(
            "word_system_prompt",
            currentValue: wordSystemPrompt,
            languageDefault: languageDefaults.wordSystem
        )
        sentenceSystemPrompt = template(
            "sentence_system_prompt",
            currentValue: sentenceSystemPrompt,
            languageDefault: languageDefaults.sentenceSystem
        )
        explanationSystemPrompt = template(
            "explanation_system_prompt",
            currentValue: explanationSystemPrompt,
            languageDefault: languageDefaults.explanationSystem,
            legacyDefaults: [
                PromptTemplateDefaults.legacyExplanationSystem,
                PromptTemplateDefaults.legacyMarkdownExplanationSystem
            ]
        )
        persistPromptTemplates(for: language)
    }

    private func validationErrors() -> [String] {
        let prompts: [(PromptTemplateKind, String, String)] = [
            (.word, wordPromptTemplate, wordSystemPrompt),
            (.sentence, sentencePromptTemplate, sentenceSystemPrompt),
            (.explanation, explanationPromptTemplate, explanationSystemPrompt)
        ]
        return prompts.flatMap { kind, userPrompt, systemPrompt in
            PromptTemplateValidator.validatePair(
                userPrompt: userPrompt,
                systemPrompt: systemPrompt,
                kind: kind
            ).errors.map { "\(kind.title)：\($0)" }
        }
    }

    private func syncRuntimeConfig(persistCredentials: Bool) throws {
        let errors = validationErrors()
        guard errors.isEmpty else {
            throw SettingsPromptValidationError(messages: errors)
        }

        persistPromptTemplates(for: targetLanguage)
        let persisted: (baseURL: String, model: String)
        if persistCredentials {
            persisted = try SettingsRuntimeService.shared.persistAndUpdateConfig(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                targetLanguage: targetLanguage,
                wordPromptTemplate: wordPromptTemplate,
                sentencePromptTemplate: sentencePromptTemplate,
                explanationPromptTemplate: explanationPromptTemplate,
                wordSystemPrompt: wordSystemPrompt,
                sentenceSystemPrompt: sentenceSystemPrompt,
                explanationSystemPrompt: explanationSystemPrompt,
                extraConfig: extraConfig
            )
        } else {
            let normalizedBaseURL = BridgeService.normalizedLLMBaseURL(baseURL)
            persisted = (normalizedBaseURL, model)
            let liveExtra = try LLMExtraConfig.liveJSON(
                extraConfig,
                baseURL: persisted.baseURL,
                model: persisted.model
            )
            try SettingsRuntimeService.shared.updateConfig(
                baseURL: persisted.baseURL,
                apiKey: apiKey,
                model: persisted.model,
                targetLanguage: targetLanguage,
                wordPromptTemplate: wordPromptTemplate,
                sentencePromptTemplate: sentencePromptTemplate,
                explanationPromptTemplate: explanationPromptTemplate,
                wordSystemPrompt: wordSystemPrompt,
                sentenceSystemPrompt: sentenceSystemPrompt,
                explanationSystemPrompt: explanationSystemPrompt,
                extraConfig: liveExtra
            )
        }
        if persisted.baseURL != baseURL, !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = persisted.baseURL
        }
        if persisted.model != model {
            model = persisted.model
        }
        if persistCredentials,
           extraConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            extraConfig = LLMExtraConfig.defaultJSON(
                baseURL: persisted.baseURL,
                model: persisted.model
            )
        }
    }

    @discardableResult
    private func saveSettings() -> Bool {
        guard applyRuntimeConfig(persistCredentials: true) else { return false }
        llmConfiguration.remember(baseURL: baseURL, model: model)
        return true
    }

    @discardableResult
    private func applyRuntimeConfig(persistCredentials: Bool = false) -> Bool {
        do {
            try syncRuntimeConfig(persistCredentials: persistCredentials)
            saveErrorMessage = nil
            withAnimation { showSavedBadge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSavedBadge = false }
            }
            return true
        } catch {
            showSavedBadge = false
            saveErrorMessage = SettingsSaveFeedback.message(for: error)
            if error is SettingsPromptValidationError {
                selectedDestination = .prompts
            } else if error is LLMExtraConfigError {
                selectedDestination = .llm
            }
            return false
        }
    }
}

enum SettingsSaveFeedback {
    static func message(for error: Error) -> String {
        if let validationError = error as? SettingsPromptValidationError {
            return validationError.localizedDescription
        }
        if let keychainError = error as? KeychainServiceError {
            return keychainError.localizedDescription
        }
        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "保存失败，请稍后重试。" : fallback
    }
}

struct SettingsPromptValidationError: LocalizedError {
    let messages: [String]

    var errorDescription: String? {
        "提示词验证失败：\(messages.first ?? "请检查动态变量")"
    }
}
