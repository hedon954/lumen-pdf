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

    var body: some View {
        Form {
            Section("LLM 配置") {
                TextField("例：https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { apiKey = KeychainService.load(key: "llm_api_key") ?? "" }

                TextField("例：gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            Section("翻译设置") {
                Picker("目标语言", selection: $targetLanguage) {
                    Text("简体中文").tag("简体中文")
                    Text("繁體中文").tag("繁體中文")
                    Text("日本語").tag("日本語")
                    Text("한국어").tag("한국어")
                }
            }

            Section("提示词模板") {
                Text("User prompt 可用变量：{lang}、{word}、{sentence}、{selection}、{context}。请保留 JSON 输出格式，否则可能导致译文解析失败。System prompt 建议继续要求模型输出合法 JSON。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                promptEditor(
                    title: "单词翻译",
                    text: $wordPromptTemplate,
                    defaultValue: PromptTemplateDefaults.word
                )

                promptEditor(
                    title: "整句翻译",
                    text: $sentencePromptTemplate,
                    defaultValue: PromptTemplateDefaults.sentence
                )

                promptEditor(
                    title: "选区解释（第一性原理）",
                    text: $explanationPromptTemplate,
                    defaultValue: PromptTemplateDefaults.explanation
                )
            }

            Section("System Prompt") {
                promptEditor(
                    title: "单词翻译 System Prompt",
                    text: $wordSystemPrompt,
                    defaultValue: PromptTemplateDefaults.wordSystem,
                    minHeight: 72
                )

                promptEditor(
                    title: "整句翻译 System Prompt",
                    text: $sentenceSystemPrompt,
                    defaultValue: PromptTemplateDefaults.sentenceSystem,
                    minHeight: 72
                )

                promptEditor(
                    title: "选区解释 System Prompt",
                    text: $explanationSystemPrompt,
                    defaultValue: PromptTemplateDefaults.explanationSystem,
                    minHeight: 72
                )
            }

            HStack {
                Spacer()

                if showSavedBadge {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
        .frame(width: 760, height: 860)
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

    private func saveSettings() {
        KeychainService.save(key: "llm_api_key", value: apiKey)
        // Hot-swap config in the running Rust backend — takes effect immediately.
        BridgeService.shared.updateConfig(
            baseURL: baseURL,
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
        withAnimation { showSavedBadge = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedBadge = false }
        }
    }
}

private enum PromptTemplateDefaults {
    static let wordSystem = "You are a professional language tutor. Always respond with valid JSON only."
    static let sentenceSystem = "You are a professional translator. Always respond with valid JSON only."
    static let explanationSystem = "You are a professional reading tutor. Always respond with valid JSON only."

    static let word = #"""
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

    static let explanation = #"""
You are a professional reading tutor. Explain the selected English text in {lang} for a PDF reader from first principles.

Selected text: "{selection}"
Context around the selection: "{context}"

Rules:
1. Start from first principles: identify the basic concepts, assumptions, causal mechanisms, and constraints that make the statement true or important.
2. Explain what the selected text means in this context; do not merely translate it.
3. Explain why the author says this here and how it connects to the surrounding argument.
4. Mention key terms and implied relationships; fix obvious OCR line-break or hyphenation errors silently.
5. Prefer a clear layered explanation: intuition first, then details, then a concise takeaway useful for notes.

Respond with ONLY valid JSON in this exact format:
{
  "explanation": "<{lang} explanation>"
}
"""#

    static let sentence = #"""
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
}
