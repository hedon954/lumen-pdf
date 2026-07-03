import SwiftUI

struct SettingsView: View {
    /// When non-nil, this view is shown as a setup sheet; the closure is called to dismiss it.
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
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
    @State private var showSavedBadge = false
    @State private var saveErrorMessage: String?
    @State private var loadedPromptLanguage = "简体中文"

    var body: some View {
        Form {
            Section("LLM 配置") {
                TextField("例：https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveSettings() }

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { apiKey = KeychainService.load(key: "llm_api_key") ?? "" }
                    .onSubmit { saveSettings() }

                TextField("例：gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveSettings() }
            }

            Section("翻译设置") {
                Picker("目标语言", selection: $targetLanguage) {
                    Text("简体中文").tag("简体中文")
                    Text("繁體中文").tag("繁體中文")
                    Text("English").tag("English")
                    Text("日本語").tag("日本語")
                    Text("한국어").tag("한국어")
                }
            }

            Section("提示词模板") {
                Text("User prompt 可用变量：{lang}、{word}、{sentence}、{selection}、{context}、{focus}。切换目标语言时会切换到对应语言的提示词模板；目前内置中文和英文两套模板。单词/整句翻译仍需保留 JSON 输出格式；选区解释会直接展示模型输出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                promptEditor(
                    title: "单词翻译",
                    text: $wordPromptTemplate,
                    defaultValue: activePromptDefaults.word
                )

                promptEditor(
                    title: "整句翻译",
                    text: $sentencePromptTemplate,
                    defaultValue: activePromptDefaults.sentence
                )

                promptEditor(
                    title: "选区解释（第一性原理）",
                    text: $explanationPromptTemplate,
                    defaultValue: activePromptDefaults.explanation
                )
            }

            Section("System Prompt") {
                promptEditor(
                    title: "单词翻译 System Prompt",
                    text: $wordSystemPrompt,
                    defaultValue: activePromptDefaults.wordSystem,
                    minHeight: 72
                )

                promptEditor(
                    title: "整句翻译 System Prompt",
                    text: $sentenceSystemPrompt,
                    defaultValue: activePromptDefaults.sentenceSystem,
                    minHeight: 72
                )

                promptEditor(
                    title: "选区解释 System Prompt",
                    text: $explanationSystemPrompt,
                    defaultValue: activePromptDefaults.explanationSystem,
                    minHeight: 72
                )
            }

            HStack {
                Spacer()

                if showSavedBadge {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let saveErrorMessage {
                    Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                // Extra button shown in setup-sheet mode
                if let dismiss = onDismiss {
                    Button("稍后设置") {
                        dismiss()
                    }
                }

                Button("保存设置") {
                    saveSettings()
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadedPromptLanguage = targetLanguage
            migratePromptDefaultsIfNeeded()
            loadPromptTemplates(for: targetLanguage, replacingLegacyDefaults: true)
        }
        .onChange(of: targetLanguage) { newLanguage in
            persistPromptTemplates(for: loadedPromptLanguage)
            loadPromptTemplates(for: newLanguage, replacingLegacyDefaults: false)
            loadedPromptLanguage = newLanguage
            applyRuntimeConfig()
        }
        .frame(width: 760, height: 860)
    }

    private var activePromptDefaults: PromptTemplateDefaults.LanguageDefaults {
        PromptTemplateDefaults.defaults(for: targetLanguage)
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

        func template(_ baseKey: String, currentValue: String, languageDefault: String, legacyDefaults: [String] = []) -> String {
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
                // Earlier versions could accidentally save the currently visible Chinese
                // defaults into the English prompt slots while switching languages. If a
                // stored value is one of our built-in templates but not the selected
                // language's built-in template, treat it as stale and replace it.
                if PromptTemplateDefaults.allBuiltInDefaults.contains(stored)
                    && !languageBuiltInDefaults.contains(stored)
                {
                    return languageDefault
                }
                return stored
            }
            if replacingLegacyDefaults && (legacyDefaults + PromptTemplateDefaults.allBuiltInDefaults).contains(currentValue) {
                return languageDefault
            }
            return languageDefault
        }

        wordPromptTemplate = template("word_prompt_template", currentValue: wordPromptTemplate, languageDefault: languageDefaults.word)
        sentencePromptTemplate = template("sentence_prompt_template", currentValue: sentencePromptTemplate, languageDefault: languageDefaults.sentence)
        explanationPromptTemplate = template(
            "explanation_prompt_template",
            currentValue: explanationPromptTemplate,
            languageDefault: languageDefaults.explanation,
            legacyDefaults: [PromptTemplateDefaults.legacyExplanation, PromptTemplateDefaults.legacyMarkdownExplanation]
        )
        wordSystemPrompt = template("word_system_prompt", currentValue: wordSystemPrompt, languageDefault: languageDefaults.wordSystem)
        sentenceSystemPrompt = template("sentence_system_prompt", currentValue: sentenceSystemPrompt, languageDefault: languageDefaults.sentenceSystem)
        explanationSystemPrompt = template(
            "explanation_system_prompt",
            currentValue: explanationSystemPrompt,
            languageDefault: languageDefaults.explanationSystem,
            legacyDefaults: [PromptTemplateDefaults.legacyExplanationSystem, PromptTemplateDefaults.legacyMarkdownExplanationSystem]
        )
        persistPromptTemplates(for: language)
    }

    private func promptEditor(title: String, text: Binding<String>, defaultValue: String, minHeight: CGFloat = 180) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("恢复默认") { text.wrappedValue = defaultValue }
            }
            TextEditor(text: text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: minHeight)
                .border(.separator)
        }
        .padding(.vertical, 6)
    }

    private func syncRuntimeConfig() throws {
        persistPromptTemplates(for: targetLanguage)
        let normalizedBaseURL = SettingsRuntimeService.shared.normalizedLLMBaseURL(baseURL)
        if normalizedBaseURL != baseURL {
            baseURL = normalizedBaseURL
        }
        try SettingsRuntimeService.shared.updateConfig(
            baseURL: normalizedBaseURL,
            apiKey: apiKey,
            model: model,
            targetLanguage: targetLanguage,
            wordPromptTemplate: wordPromptTemplate,
            sentencePromptTemplate: sentencePromptTemplate,
            explanationPromptTemplate: explanationPromptTemplate,
            wordSystemPrompt: wordSystemPrompt,
            sentenceSystemPrompt: sentenceSystemPrompt,
            explanationSystemPrompt: explanationSystemPrompt
        )
    }

    private func saveSettings() {
        KeychainService.save(key: "llm_api_key", value: apiKey)
        applyRuntimeConfig()
    }

    private func applyRuntimeConfig() {
        do {
            try syncRuntimeConfig()
            saveErrorMessage = nil
            appState.showToast("LLM 配置已生效")
            withAnimation { showSavedBadge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSavedBadge = false }
            }
        } catch {
            showSavedBadge = false
            saveErrorMessage = "保存失败"
            appState.showToast(TranslationErrorFormatter.userMessage(from: error))
        }
    }
}

private enum PromptTemplateDefaults {
    struct LanguageDefaults {
        let word: String
        let sentence: String
        let explanation: String
        let wordSystem: String
        let sentenceSystem: String
        let explanationSystem: String
    }

    static func storageSuffix(for language: String) -> String {
        language.localizedCaseInsensitiveContains("中文") || language.localizedCaseInsensitiveContains("Chinese") ? "zh" : "en"
    }

    static func defaults(for language: String) -> LanguageDefaults {
        storageSuffix(for: language) == "zh" ? chinese : english
    }

    static let word = wordChinese
    static let sentence = sentenceChinese
    static let explanation = explanationChinese
    static let wordSystem = wordSystemChinese
    static let sentenceSystem = sentenceSystemChinese
    static let explanationSystem = explanationSystemChinese

    static let chinese = LanguageDefaults(
        word: wordChinese,
        sentence: sentenceChinese,
        explanation: explanationChinese,
        wordSystem: wordSystemChinese,
        sentenceSystem: sentenceSystemChinese,
        explanationSystem: explanationSystemChinese
    )

    static let english = LanguageDefaults(
        word: wordEnglish,
        sentence: sentenceEnglish,
        explanation: explanationEnglish,
        wordSystem: wordSystemEnglish,
        sentenceSystem: sentenceSystemEnglish,
        explanationSystem: explanationSystemEnglish
    )

    static let allBuiltInDefaults = [
        wordChinese, sentenceChinese, explanationChinese,
        wordEnglish, sentenceEnglish, explanationEnglish,
        wordSystemChinese, sentenceSystemChinese, explanationSystemChinese,
        wordSystemEnglish, sentenceSystemEnglish, explanationSystemEnglish
    ]

    static let legacyExplanationSystem = "You are a professional reading tutor. Always respond with valid JSON only."
    static let legacyMarkdownExplanationSystem = "You are a professional reading tutor. Return clear Markdown/plain text only; never return JSON for explanations."
    static let wordSystemEnglish = "You are a professional language tutor. Always respond with valid JSON only."
    static let sentenceSystemEnglish = "You are a professional translator. Always respond with valid JSON only."
    static let explanationSystemEnglish = "You are a professional reading tutor. Return explanation text only; never return JSON for explanations."
    static let wordSystemChinese = "你是专业语言导师。只输出有效 JSON。"
    static let sentenceSystemChinese = "你是专业翻译和语言导师。只输出有效 JSON。"
    static let explanationSystemChinese = "你是专业阅读导师。只输出解释文本，不要输出 JSON。"

    static let wordEnglish = #"""
You are a professional language tutor. The user selected the word "{word}" while reading a PDF.

Context sentence: "{sentence}"

IMPORTANT: The selected text may contain OCR errors, line-break hyphens (e.g. "investi-\ngating"), or extra whitespace due to PDF extraction. In the "word" field, output the correctly spelled, properly joined word.

Respond with ONLY valid JSON in this exact format:
{
  "word": "correctly spelled word (fix any hyphenation, OCR errors, or typos from PDF extraction)",
  "phonetic": "IPA phonetic transcription",
  "part_of_speech": "noun/verb/adjective/adverb/etc",
  "context_translation": "Translation of the word in this specific context to {lang}",
  "context_explanation": "Why does it mean this here? Explain the nuance in {lang}",
  "general_definition": "General English definition of the word",
  "context_sentence_translation": "Full translation of the ENTIRE context sentence above to {lang} (not just the word)"
}
"""#

    static let explanationEnglish = #"""
You are a professional reading tutor. Explain the selected English text in {lang} for a PDF reader from first principles.
你是一名专业阅读导师。请用{lang}从第一性原理解释用户在 PDF 中选中的英文内容。

Selected text / 选中文本: "{selection}"
Context / 上下文: "{context}"
Optional user question / 用户疑问: "{focus}"

Rules / 规则:
1. If the user question is non-empty, answer that question first and center the explanation on it.
2. If the user question is empty, provide a quick general explanation.
3. Start from first principles: identify basic concepts, assumptions, mechanisms, and constraints.
4. Explain meaning in context; do not merely translate.
5. Preserve real line breaks between distinct ideas and blocks.

Return ONLY the explanation text in {lang}. Do not wrap it in JSON, code fences, or quotes.
"""#

    static let legacyMarkdownExplanation = #"""
You are a professional reading tutor. Explain the selected English text in {lang} for a PDF reader from first principles.

Selected text: "{selection}"
Context around the selection: "{context}"

Rules:
1. Start from first principles: identify the basic concepts, assumptions, causal mechanisms, and constraints that make the statement true or important.
2. Explain what the selected text means in this context; do not merely translate it.
3. Explain why the author says this here and how it connects to the surrounding argument.
4. Mention key terms and implied relationships; fix obvious OCR line-break or hyphenation errors silently.
5. Format the answer like a high-quality reading note in {lang}: start with a short bold thesis paragraph, then use clear Markdown section headings such as `## 一、...`, numbered lists, bullet lists, and short paragraphs. Do not use Markdown tables; use bullet lists instead because the explanation is shown in a compact reader bubble.
6. Preserve real line breaks: every heading, paragraph, numbered item, and bullet item must be on its own line, with a blank line between blocks. Never collapse the explanation into one giant paragraph.
7. Do not artificially shorten the answer. Use enough detail to make the idea understandable, while avoiding irrelevant digressions.
8. Prefer a clear layered explanation: intuition first, then first-principles mechanics, then implications, then a concise takeaway useful for notes.

Return ONLY the Markdown explanation text. Do not wrap it in JSON, code fences, or quotes.
"""#

    static let legacyExplanation = #"""
You are a professional reading tutor. Explain the selected English text in {lang} for a PDF reader from first principles.

Selected text: "{selection}"
Context around the selection: "{context}"

Rules:
1. Start from first principles: identify the basic concepts, assumptions, causal mechanisms, and constraints that make the statement true or important.
2. Explain what the selected text means in this context; do not merely translate it.
3. Explain why the author says this here and how it connects to the surrounding argument.
4. Mention key terms and implied relationships; fix obvious OCR line-break or hyphenation errors silently.
5. Use Markdown: headings, bullet lists, bold key terms, short paragraphs, and code/math-style notation when useful.
6. Preserve real line breaks. Put a blank line between sections and before every numbered or bulleted list item; never collapse the explanation into one giant paragraph.
7. Do not artificially shorten the answer. Use enough detail to make the idea understandable, while avoiding irrelevant digressions.
8. Prefer a clear layered explanation: intuition first, then first-principles mechanics, then implications, then a concise takeaway useful for notes.

Return ONLY the Markdown explanation text. Do not wrap it in JSON, code fences, or quotes.
"""#

    static let sentenceEnglish = #"""
You are a professional translator and language tutor. Translate the following English text to {lang} and, if it is a long or complex sentence, also break it down so the reader can understand each fragment.

Text: "{sentence}"

Rules:
1. Provide a natural, fluent translation in `translation`.
2. Preserve meaning and tone of the original; fix OCR errors / broken words if present.
3. Decide whether the sentence is "long or complex":
   - SHORT / SIMPLE (≤10 words, no clauses, plain SVO) → set `breakdown` to an empty array `[]`.
   - LONG / COMPLEX (multiple clauses, inversion, parallel structure, complex adverbials, etc.) → split it into 2–5 logical fragments.
4. For each fragment in `breakdown`, output an object with EXACTLY these fields:
   - `original`: the English fragment, copied verbatim from the source.
   - `translation`: that fragment's translation in {lang}.
   - `explanation`: in {lang}, briefly explain word choices / contextual meaning. ≤2 sentences.
   - `grammar`: ONLY fill this when the fragment contains a grammatically noteworthy structure (subordinate clause, inversion, subjunctive mood, parallel structure, participle clause, nested complex structures, etc.). Leave it as an EMPTY STRING for plain SVO fragments. Be concise — 1 to 3 sentences in {lang}, naming the structure and explaining its role.

Respond with ONLY valid JSON in this exact format:
{
  "translation": "<full translation in {lang}>",
  "breakdown": [
    {
      "original": "<English fragment>",
      "translation": "<{lang} translation of the fragment>",
      "explanation": "<{lang} explanation>",
      "grammar": "<{lang} grammar analysis OR empty string>"
    }
  ]
}
"""#

    static let wordChinese = #"""
你是专业语言导师。用户在阅读 PDF 时选中了英文单词「{word}」。

上下文句子：「{sentence}」

重要：选中文本可能包含 OCR 错误、PDF 抽取导致的断行连字符（例如 "investi-\ngating"）或多余空格。请在 "word" 字段中输出修正拼写、正确合并后的单词。

只输出符合以下格式的有效 JSON：
{
  "word": "修正后的英文单词（修复 PDF 抽取导致的断词、OCR 错误或拼写错误）",
  "phonetic": "IPA 音标",
  "part_of_speech": "名词/动词/形容词/副词等词性",
  "context_translation": "该词在当前语境下翻译成{lang}的意思",
  "context_explanation": "用{lang}解释它为什么在这里表示这个意思，以及语义细微差别",
  "general_definition": "该英文单词的通用英文释义",
  "context_sentence_translation": "将上面的整句上下文完整翻译成{lang}（不要只翻译该单词）"
}
"""#

    static let sentenceChinese = #"""
你是专业翻译和语言导师。请将下面的英文文本翻译成{lang}；如果它是长句或复杂句，还要拆解句子，让读者理解每个片段。

文本：「{sentence}」

规则：
1. 在 `translation` 中给出自然、流畅的译文。
2. 保留原文含义和语气；如有 OCR 错误或 PDF 抽取造成的断词，请静默修复。
3. 判断句子是否“长或复杂”：
   - 短句/简单句（≤10 个词、无从句、普通 SVO）→ 将 `breakdown` 设为空数组 `[]`。
   - 长句/复杂句（多个从句、倒装、并列结构、复杂状语等）→ 拆成 2–5 个逻辑片段。
4. `breakdown` 中每个片段必须严格包含这些字段：
   - `original`：英文片段，尽量按原文摘录。
   - `translation`：该片段的{lang}翻译。
   - `explanation`：用{lang}简要说明用词或语境含义，不超过 2 句。
   - `grammar`：只有片段存在值得说明的语法结构（从句、倒装、虚拟语气、并列、分词结构、嵌套复杂结构等）时填写；普通 SVO 片段留空字符串。请简洁，1–3 句。

只输出符合以下格式的有效 JSON：
{
  "translation": "<完整{lang}译文>",
  "breakdown": [
    {
      "original": "<英文片段>",
      "translation": "<该片段的{lang}译文>",
      "explanation": "<{lang}解释>",
      "grammar": "<{lang}语法分析，或空字符串>"
    }
  ]
}
"""#

    static let explanationChinese = #"""
你是专业阅读导师。请用{lang}从第一性原理解释用户在 PDF 中选中的英文内容。

选中文本：「{selection}」
上下文：「{context}」
用户疑问（可为空）：「{focus}」

规则：
1. 如果用户疑问不为空，先直接回答这个问题，再围绕该关注点展开解释。
2. 如果用户疑问为空，给出快速、通用的解释。
3. 从第一性原理出发：指出基础概念、前提、机制和约束。
4. 解释它在当前上下文中的意思，不要只是翻译。
5. 保留清晰换行，让不同观点、段落和列表分开。

只返回{lang}解释文本。不要包裹 JSON、代码块或引号。
"""#

}
