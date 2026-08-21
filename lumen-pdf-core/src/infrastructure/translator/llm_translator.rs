use crate::domain::translation::{
    entity::{ImageAttachment, ImageInputCapability, SentenceChunk, TranslationResult},
    repository::{StreamProgress, Translator},
};
use crate::error::LumenError;
use crate::infrastructure::translator::extra_config::merge_chat_request;
use crate::infrastructure::translator::http_client::shared_client;
use crate::infrastructure::translator::model_json::{parse_model_json, streaming_json_view};
use crate::infrastructure::translator::streaming::{
    describe_empty_model_output, extract_complete_string_fields, extract_message_content_from_json,
    extract_streaming_string_value, preview_text, SseAccumulator, SseChunkOutcome, TokenUsage,
};
use crate::infrastructure::translator::thinking_control::{
    ensure_no_think_suffix, ThinkingDisableKind, ThinkingDisablePolicy,
};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

#[derive(Clone)]
pub struct LlmConfig {
    pub base_url: String,
    pub api_key: String,
    pub model: String,
    pub target_language: String,
    pub word_prompt_template: String,
    pub sentence_prompt_template: String,
    pub explanation_prompt_template: String,
    pub word_system_prompt: String,
    pub sentence_system_prompt: String,
    pub explanation_system_prompt: String,
    pub extra_config: String,
}

pub struct LlmTranslator {
    config: LlmConfig,
}

pub const DEFAULT_WORD_SYSTEM_PROMPT: &str =
    "You are a professional language tutor. Always respond with valid JSON only.";
pub const DEFAULT_SENTENCE_SYSTEM_PROMPT: &str =
    "You are a professional translator. Always respond with valid JSON only.";
pub const DEFAULT_EXPLANATION_SYSTEM_PROMPT: &str =
    "You are a professional reading tutor. Return explanation text only; never return JSON for explanations.";
const DEFAULT_MAX_TOKENS: u32 = 4096;
const IMAGE_CAPABILITY_PROBE_PNG_BASE64: &str =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
static IMAGE_CAPABILITY_CACHE: OnceLock<RwLock<HashMap<String, ImageInputCapability>>> =
    OnceLock::new();

pub const DEFAULT_WORD_PROMPT_TEMPLATE: &str = r#"You are a professional language tutor. The user selected the word "{word}" while reading a PDF.

Context sentence: "{sentence}"

IMPORTANT: The selected text may contain OCR errors, line-break hyphens (e.g. "investi-\ngating"), or extra whitespace due to PDF extraction. In the "word" field, output the correctly spelled, properly joined word.

Respond with ONLY valid JSON in this exact format:
{
  "word": "correctly spelled word (fix any hyphenation, OCR errors, or typos from PDF extraction)",
  "phonetic": "IPA phonetic transcription",
  "part_of_speech": "noun/verb/adjective/adverb/etc",
  "context_translation": "Translation of the word in this specific context to {lang}",
  "context_explanation": "Why does it mean this here? Explain the nuance in {lang}",
  "etymology": "A short standalone word-origin, historical story, or morphology note in {lang}. Use an empty string when the information would be speculative or would not help understanding or memory.",
  "general_definition": "General English definition of the word",
  "context_sentence_translation": "Full translation of the ENTIRE context sentence above to {lang} (not just the word)"
}"#;

pub const DEFAULT_EXPLANATION_PROMPT_TEMPLATE: &str = r#"You are a professional reading tutor. Explain the selected English text in {lang} for a PDF reader from first principles.
你是一名专业阅读导师。请用{lang}从第一性原理解释用户在 PDF 中选中的英文内容。

Selected text / 选中文本: "{selection}"
Context / 上下文: "{context}"

Rules / 规则:
1. Start from first principles: identify basic concepts, assumptions, mechanisms, and constraints.
2. Explain meaning in context; do not merely translate.
3. Explain why the author says this here and how it connects to the surrounding argument.
4. Mention key terms and implied relationships; silently fix obvious OCR line-break or hyphenation errors.
5. Preserve real line breaks between distinct ideas and blocks.
6. Prefer layered explanation: intuition, first-principles mechanics, implications, and reading-note value.

Return ONLY the explanation text in {lang}. Do not wrap it in JSON, code fences, or quotes."#;

pub const DEFAULT_FOCUSED_EXPLANATION_PROMPT_TEMPLATE: &str = r#"You are a professional reading tutor. Explain the selected English text in {lang} for a PDF reader from first principles, centered on the user's question.
你是一名专业阅读导师。请用{lang}围绕用户的问题，从第一性原理解释 PDF 中选中的英文内容。

Selected text / 选中文本: "{selection}"
Context / 上下文: "{context}"
User question / 用户疑问: "{focus}"

Rules / 规则:
1. Answer the user's question directly first, then expand from first principles.
2. Center the explanation on the user's concern; omit generic background that does not help answer it.
3. Explain the selected text's contextual meaning and why the author says it here.
4. Mention key terms, assumptions, mechanisms, constraints, and implied relationships.
5. Silently fix obvious OCR line-break or hyphenation errors.
6. Preserve real line breaks between distinct ideas and blocks.

Return ONLY the explanation text in {lang}. Do not wrap it in JSON, code fences, or quotes."#;

pub const DEFAULT_SENTENCE_PROMPT_TEMPLATE: &str = r#"You are a professional translator and language tutor. Translate the following English text to {lang} and, if it is a long or complex sentence, also break it down so the reader can understand each fragment.

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
}"#;

fn render_prompt_template(template: &str, vars: &[(&str, &str)]) -> String {
    let mut rendered = template.to_string();
    for (key, value) in vars {
        rendered = rendered.replace(&format!("{{{key}}}"), value);
    }
    rendered
}

fn configured_template<'a>(configured: &'a str, default: &'a str) -> &'a str {
    let trimmed = configured.trim();
    if trimmed.is_empty() {
        default
    } else {
        configured
    }
}

impl LlmConfig {
    pub fn word_cache_scope(&self) -> String {
        let mut hasher = Sha256::new();
        hasher.update(
            configured_template(&self.word_prompt_template, DEFAULT_WORD_PROMPT_TEMPLATE)
                .as_bytes(),
        );
        hasher.update([0]);
        hasher.update(
            configured_template(&self.word_system_prompt, DEFAULT_WORD_SYSTEM_PROMPT).as_bytes(),
        );
        format!(
            "{}|word-prompt:{:x}",
            self.target_language,
            hasher.finalize()
        )
    }
}

impl LlmTranslator {
    pub fn new(config: LlmConfig) -> Self {
        Self { config }
    }

    fn build_prompt(&self, word: &str, sentence: &str) -> String {
        render_prompt_template(
            configured_template(
                &self.config.word_prompt_template,
                DEFAULT_WORD_PROMPT_TEMPLATE,
            ),
            &[
                ("word", word),
                ("sentence", sentence),
                ("lang", &self.config.target_language),
            ],
        )
    }

    fn build_explanation_prompt(&self, selection: &str, context: &str, focus: &str) -> String {
        let focus = focus.trim();
        let configured = self.config.explanation_prompt_template.trim();
        let template = if configured.is_empty() && !focus.is_empty() {
            DEFAULT_FOCUSED_EXPLANATION_PROMPT_TEMPLATE
        } else {
            configured_template(
                &self.config.explanation_prompt_template,
                DEFAULT_EXPLANATION_PROMPT_TEMPLATE,
            )
        };
        let mut prompt = render_prompt_template(
            template,
            &[
                ("selection", selection),
                ("context", context),
                ("focus", focus),
                ("lang", &self.config.target_language),
            ],
        );

        if !focus.is_empty() && !template.contains("{focus}") {
            prompt.push_str("\n\nUser question / 用户疑问: ");
            prompt.push_str(focus);
            prompt.push_str("\nPlease answer this question first, then explain from first principles. 请先回答这个问题，再从第一性原理解释。");
        }

        prompt
    }

    fn build_sentence_prompt(&self, sentence: &str) -> String {
        render_prompt_template(
            configured_template(
                &self.config.sentence_prompt_template,
                DEFAULT_SENTENCE_PROMPT_TEMPLATE,
            ),
            &[
                ("sentence", sentence),
                ("lang", &self.config.target_language),
            ],
        )
    }

    fn word_system_prompt(&self) -> String {
        configured_template(&self.config.word_system_prompt, DEFAULT_WORD_SYSTEM_PROMPT).to_string()
    }

    fn sentence_system_prompt(&self) -> String {
        configured_template(
            &self.config.sentence_system_prompt,
            DEFAULT_SENTENCE_SYSTEM_PROMPT,
        )
        .to_string()
    }

    fn explanation_system_prompt(&self) -> String {
        configured_template(
            &self.config.explanation_system_prompt,
            DEFAULT_EXPLANATION_SYSTEM_PROMPT,
        )
        .to_string()
    }

    pub async fn explain_selection_streaming(
        &self,
        selection: &str,
        context: &str,
        focus: &str,
        images: &[ImageAttachment],
        mut on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        let body = self.build_explanation_request(selection, context, focus, images, true);
        let url = self.completions_url();

        let completion = self
            .stream_completion(&url, &body, |raw, last_emitted| {
                if raw != *last_emitted {
                    *last_emitted = raw.to_string();
                    on_progress(TranslationResult {
                        word: selection.to_string(),
                        context_explanation: raw.to_string(),
                        source: "llm".to_string(),
                        ..Default::default()
                    });
                }
            })
            .await?;

        let final_result = TranslationResult {
            word: selection.to_string(),
            context_explanation: completion.content,
            source: "llm".to_string(),
            prompt_tokens: completion.usage.prompt_tokens,
            completion_tokens: completion.usage.completion_tokens,
            total_tokens: completion.usage.total_tokens,
            ..Default::default()
        };
        on_progress(final_result.clone());
        Ok(final_result)
    }

    pub async fn detect_image_input_capability(&self) -> ImageInputCapability {
        let cache_key = format!(
            "{}|{}",
            self.config.base_url.trim_end_matches('/'),
            self.config.model
        );
        let cache = IMAGE_CAPABILITY_CACHE.get_or_init(|| RwLock::new(HashMap::new()));
        if let Ok(guard) = cache.read() {
            if let Some(capability) = guard.get(&cache_key) {
                return *capability;
            }
        }

        if let Some(capability) = self.image_capability_from_model_metadata().await {
            if let Ok(mut guard) = cache.write() {
                guard.insert(cache_key, capability);
            }
            return capability;
        }

        let capability = self.probe_image_input_capability().await;
        if capability != ImageInputCapability::Unknown {
            if let Ok(mut guard) = cache.write() {
                guard.insert(cache_key, capability);
            }
        }
        capability
    }

    /// Translate a full sentence without word-level analysis (non-streaming).
    /// Returns a `TranslationResult` with `context_sentence_translation` and
    /// (when applicable) `sentence_breakdown` filled in.
    pub async fn translate_sentence(
        &self,
        sentence: &str,
    ) -> Result<TranslationResult, LumenError> {
        let body = self.build_sentence_request(sentence, false);
        let completion = self.send_chat_request(&body).await?;

        let parsed: SentencePromptJson = parse_model_json(&completion.content)?;
        Ok(parsed.into_result(sentence, completion.usage))
    }

    /// Streaming sentence translation.
    ///
    /// During the stream, `on_progress` is invoked **whenever a new character
    /// of the `translation` field arrives** — this gives the UI a real
    /// "watch the translation get written" effect (vs v1.0.4 which only
    /// emitted once the closing quote arrived).
    ///
    /// At end of stream, a strict JSON parse populates `sentence_breakdown`
    /// from the LLM response. The fully populated `TranslationResult` is
    /// returned and is also emitted as the final progress update.
    pub async fn translate_sentence_streaming(
        &self,
        sentence: &str,
        mut on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        let body = self.build_sentence_request(sentence, true);
        let url = self.completions_url();

        let completion = self
            .stream_completion(&url, &body, |raw, last_emitted| {
                // Stream the `translation` field character by character. Other
                // fields (`breakdown`) only appear at the end and are handled
                // after the stream closes.
                let Some(current) =
                    extract_streaming_string_value(&streaming_json_view(raw), "translation")
                else {
                    return;
                };
                if current != *last_emitted {
                    *last_emitted = current.clone();
                    on_progress(TranslationResult {
                        word: sentence.to_string(),
                        context_sentence_translation: current,
                        source: "llm".to_string(),
                        ..Default::default()
                    });
                }
            })
            .await?;

        // Final, authoritative parse: the streaming extractor is permissive
        // (string-only). At end of stream we run a strict JSON parse so we
        // can extract `breakdown` and guarantee a clean final result.
        let parsed: SentencePromptJson = parse_model_json(&completion.content)?;
        let final_result = parsed.into_result(sentence, completion.usage);
        // Emit a terminal progress event so the UI gets the breakdown without
        // having to wait for the outer caller to wire it.
        on_progress(final_result.clone());
        Ok(final_result)
    }

    fn completions_url(&self) -> String {
        format!(
            "{}/chat/completions",
            self.config.base_url.trim_end_matches('/')
        )
    }

    fn models_url(&self) -> String {
        format!("{}/models", self.config.base_url.trim_end_matches('/'))
    }

    async fn image_capability_from_model_metadata(&self) -> Option<ImageInputCapability> {
        let response = shared_client()
            .get(self.models_url())
            .bearer_auth(&self.config.api_key)
            .send()
            .await
            .ok()?;
        if !response.status().is_success() {
            return None;
        }
        let value: Value = response.json().await.ok()?;
        explicit_image_capability(&value, &self.config.model)
    }

    async fn probe_image_input_capability(&self) -> ImageInputCapability {
        let body = self.chat_request(
            vec![Message {
                role: "user".into(),
                content: RequestMessageContent::Parts(vec![
                    RequestContentPart::Text {
                        text: "Reply with OK.".into(),
                    },
                    RequestContentPart::ImageUrl {
                        image_url: ImageUrlContent {
                            url: format!(
                                "data:image/png;base64,{IMAGE_CAPABILITY_PROBE_PNG_BASE64}"
                            ),
                        },
                    },
                ]),
            }],
            false,
            None,
            Some(1),
        );

        let payload = match self.chat_json(&body) {
            Ok(value) => value,
            Err(_) => return ImageInputCapability::Unknown,
        };
        let response = match shared_client()
            .post(self.completions_url())
            .bearer_auth(&self.config.api_key)
            .json(&payload)
            .send()
            .await
        {
            Ok(response) => response,
            Err(_) => return ImageInputCapability::Unknown,
        };

        if response.status().is_success() {
            return ImageInputCapability::Supported;
        }

        let status = response.status();
        let error_body = response.text().await.unwrap_or_default();
        if is_unknown_optional_field_error(status, &error_body) && body.has_vendor_extensions() {
            let retry_payload = match self.chat_json(&body.clone().without_vendor_extensions()) {
                Ok(value) => value,
                Err(_) => return ImageInputCapability::Unknown,
            };
            let retry = match shared_client()
                .post(self.completions_url())
                .bearer_auth(&self.config.api_key)
                .json(&retry_payload)
                .send()
                .await
            {
                Ok(response) => response,
                Err(_) => return ImageInputCapability::Unknown,
            };
            if retry.status().is_success() {
                return ImageInputCapability::Supported;
            }
            let retry_status = retry.status();
            let retry_body = retry.text().await.unwrap_or_default();
            if (retry_status.as_u16() == 400 || retry_status.as_u16() == 422)
                && is_explicit_image_unsupported_error(&retry_body)
            {
                return ImageInputCapability::Unsupported;
            }
            return ImageInputCapability::Unknown;
        }

        if (status.as_u16() == 400 || status.as_u16() == 422)
            && is_explicit_image_unsupported_error(&error_body)
        {
            ImageInputCapability::Unsupported
        } else {
            ImageInputCapability::Unknown
        }
    }

    fn build_explanation_request(
        &self,
        selection: &str,
        context: &str,
        focus: &str,
        images: &[ImageAttachment],
        stream: bool,
    ) -> ChatRequest {
        let mut prompt = self.build_explanation_prompt(selection, context, focus);
        let user_content = if images.is_empty() {
            RequestMessageContent::Text(prompt)
        } else {
            prompt.push_str(
                "\n\nThe attached images are additional context for the user's question. Inspect and use their visual content when answering.",
            );
            let mut parts = vec![RequestContentPart::Text { text: prompt }];
            for (index, image) in images.iter().enumerate() {
                parts.push(RequestContentPart::Text {
                    text: format!("Attached image {}: {}", index + 1, image.file_name),
                });
                parts.push(RequestContentPart::ImageUrl {
                    image_url: ImageUrlContent {
                        url: format!("data:{};base64,{}", image.mime_type, image.base64_data),
                    },
                });
            }
            RequestMessageContent::Parts(parts)
        };

        self.chat_request(
            vec![
                Message {
                    role: "system".into(),
                    content: RequestMessageContent::Text(self.explanation_system_prompt()),
                },
                Message {
                    role: "user".into(),
                    content: user_content,
                },
            ],
            stream,
            None,
            Some(DEFAULT_MAX_TOKENS),
        )
    }

    fn build_sentence_request(&self, sentence: &str, stream: bool) -> ChatRequest {
        self.chat_request(
            vec![
                Message {
                    role: "system".into(),
                    content: RequestMessageContent::Text(self.sentence_system_prompt()),
                },
                Message {
                    role: "user".into(),
                    content: RequestMessageContent::Text(self.build_sentence_prompt(sentence)),
                },
            ],
            stream,
            Some(ResponseFormat {
                kind: "json_object".into(),
            }),
            Some(DEFAULT_MAX_TOKENS),
        )
    }

    fn build_word_request(&self, word: &str, sentence: &str, stream: bool) -> ChatRequest {
        self.chat_request(
            vec![
                Message {
                    role: "system".into(),
                    content: RequestMessageContent::Text(self.word_system_prompt()),
                },
                Message {
                    role: "user".into(),
                    content: RequestMessageContent::Text(self.build_prompt(word, sentence)),
                },
            ],
            stream,
            Some(ResponseFormat {
                kind: "json_object".into(),
            }),
            Some(DEFAULT_MAX_TOKENS),
        )
    }

    fn chat_request(
        &self,
        messages: Vec<Message>,
        stream: bool,
        response_format: Option<ResponseFormat>,
        max_tokens: Option<u32>,
    ) -> ChatRequest {
        let policy = ThinkingDisablePolicy::for_endpoint(&self.config.base_url, &self.config.model);
        let messages = if policy.append_no_think {
            with_no_think_on_last_user(messages)
        } else {
            messages
        };
        ChatRequest {
            model: self.config.model.clone(),
            messages,
            response_format,
            max_tokens,
            stream,
            stream_options: stream.then_some(StreamOptions {
                include_usage: true,
            }),
            enable_thinking: matches!(policy.kind, ThinkingDisableKind::EnableThinking)
                .then_some(false),
            chat_template_kwargs: matches!(policy.kind, ThinkingDisableKind::ChatTemplateKwargs)
                .then_some(ChatTemplateKwargs {
                    enable_thinking: false,
                }),
            thinking: matches!(policy.kind, ThinkingDisableKind::ThinkingType).then_some(
                ThinkingControl {
                    kind: "disabled".into(),
                },
            ),
            reasoning: matches!(policy.kind, ThinkingDisableKind::OpenRouterReasoning)
                .then_some(ReasoningControl { enabled: false }),
        }
    }

    fn chat_json(&self, body: &ChatRequest) -> Result<Value, LumenError> {
        merge_chat_request(body, &self.config.extra_config)
    }

    async fn send_chat_request(&self, body: &ChatRequest) -> Result<CompletionOutput, LumenError> {
        let url = self.completions_url();
        let payload = self.chat_json(body)?;
        let resp = shared_client()
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .json(&payload)
            .send()
            .await
            .map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;

        let resp = if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            if is_unknown_optional_field_error(status, &text) && body.has_vendor_extensions() {
                let compatible_body = body.clone().without_vendor_extensions();
                let retry_payload = self.chat_json(&compatible_body)?;
                let retry = shared_client()
                    .post(&url)
                    .bearer_auth(&self.config.api_key)
                    .json(&retry_payload)
                    .send()
                    .await
                    .map_err(|e| LumenError::LlmApiError {
                        message: e.to_string(),
                    })?;
                if !retry.status().is_success() {
                    let retry_status = retry.status();
                    let retry_text = retry.text().await.unwrap_or_default();
                    return Err(LumenError::LlmApiError {
                        message: format!("HTTP {retry_status}: {retry_text}"),
                    });
                }
                retry
            } else {
                return Err(LumenError::LlmApiError {
                    message: format!("HTTP {status}: {text}"),
                });
            }
        } else {
            resp
        };

        let raw = resp.text().await.map_err(|e| LumenError::LlmApiError {
            message: e.to_string(),
        })?;
        let chat: ChatResponse =
            serde_json::from_str(&raw).map_err(|e| LumenError::LlmApiError {
                message: format!(
                    "无法解析模型响应 JSON：{e}。原始响应预览：{}",
                    preview_text(&raw, 420)
                ),
            })?;

        let message = chat.choices.into_iter().next().map(|choice| choice.message);
        let content = message
            .as_ref()
            .and_then(|item| item.content.clone())
            .unwrap_or_default();
        let reasoning = message
            .as_ref()
            .and_then(|item| item.reasoning_content.clone())
            .unwrap_or_default();
        let usage = chat.usage.unwrap_or_default();
        if content.trim().is_empty() {
            let mut accumulator = SseAccumulator::default();
            accumulator.reasoning = reasoning;
            return Err(LumenError::LlmApiError {
                message: describe_empty_model_output(
                    raw.len(),
                    &accumulator,
                    &raw,
                    usage,
                    &self.config.model,
                    &url,
                ),
            });
        }
        Ok(CompletionOutput { content, usage })
    }

    /// Drive an OpenAI-compatible streaming completion: fire the request,
    /// consume the SSE byte stream, and call `on_chunk` after every UTF-8
    /// safe append to the accumulating raw JSON content. Returns the full
    /// accumulated content string when the stream completes.
    async fn stream_completion<F>(
        &self,
        url: &str,
        body: &ChatRequest,
        mut on_chunk: F,
    ) -> Result<CompletionOutput, LumenError>
    where
        F: FnMut(&str, &mut String),
    {
        let payload = self.chat_json(body)?;
        let mut resp = shared_client()
            .post(url)
            .bearer_auth(&self.config.api_key)
            .json(&payload)
            .send()
            .await
            .map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            let can_retry_without_usage =
                is_unknown_optional_field_error(status, &text) && body.has_vendor_extensions();
            if can_retry_without_usage {
                let compatible_body = body.clone().without_vendor_extensions();
                let retry_payload = self.chat_json(&compatible_body)?;
                resp = shared_client()
                    .post(url)
                    .bearer_auth(&self.config.api_key)
                    .json(&retry_payload)
                    .send()
                    .await
                    .map_err(|e| LumenError::LlmApiError {
                        message: e.to_string(),
                    })?;
                if !resp.status().is_success() {
                    let retry_status = resp.status();
                    let retry_text = resp.text().await.unwrap_or_default();
                    return Err(LumenError::LlmApiError {
                        message: format!("HTTP {retry_status}: {retry_text}"),
                    });
                }
            } else {
                return Err(LumenError::LlmApiError {
                    message: format!("HTTP {status}: {text}"),
                });
            }
        }

        let mut byte_buf: Vec<u8> = Vec::new();
        let mut content_buf = String::new();
        let mut sse = SseAccumulator::new();
        // `on_chunk` callbacks may want to track previously-emitted state
        // across invocations without owning their own state; expose a
        // mutable string scratch they can repurpose freely.
        let mut scratch = String::new();
        let mut stream = resp.bytes_stream();
        let mut usage = TokenUsage::default();
        let mut raw_preview = String::new();
        let mut bytes_received = 0usize;

        while let Some(item) = stream.next().await {
            let bytes = item.map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;
            bytes_received += bytes.len();
            append_raw_preview(&mut raw_preview, &bytes, 8_000);
            byte_buf.extend_from_slice(&bytes);
            // Decode the longest valid-UTF-8 prefix; keep any trailing partial
            // multi-byte char in `byte_buf` for the next iteration so we never
            // emit replacement characters mid-stream.
            let valid_len = match std::str::from_utf8(&byte_buf) {
                Ok(s) => s.len(),
                Err(e) => e.valid_up_to(),
            };
            if valid_len == 0 {
                continue;
            }
            // SAFETY: valid_len is the result of `valid_up_to` (or full length
            // when fully valid), so the prefix slice is guaranteed valid UTF-8.
            let valid_str =
                unsafe { std::str::from_utf8_unchecked(&byte_buf[..valid_len]) }.to_string();
            byte_buf.drain(..valid_len);

            let outcome = sse.feed(&valid_str);
            let done = outcome.done;
            apply_stream_outcome(
                outcome,
                &mut usage,
                &mut content_buf,
                &mut on_chunk,
                &mut scratch,
            );
            if sse.gateway_error.is_some() || done {
                break;
            }
        }

        let flushed = sse.flush();
        apply_stream_outcome(
            flushed,
            &mut usage,
            &mut content_buf,
            &mut on_chunk,
            &mut scratch,
        );

        if let Some(error) = sse.gateway_error.clone() {
            return Err(LumenError::LlmApiError {
                message: format!(
                    "{error} {}",
                    describe_empty_model_output(
                        bytes_received,
                        &sse,
                        &raw_preview,
                        usage,
                        &self.config.model,
                        url
                    )
                ),
            });
        }

        if content_buf.trim().is_empty() {
            if let Some((extracted, extracted_usage)) =
                extract_message_content_from_json(&raw_preview)
            {
                content_buf = extracted;
                if usage.total_tokens == 0 {
                    usage = extracted_usage;
                }
                on_chunk(&content_buf, &mut scratch);
            }
        }

        if content_buf.trim().is_empty() {
            return Err(LumenError::LlmApiError {
                message: describe_empty_model_output(
                    bytes_received,
                    &sse,
                    &raw_preview,
                    usage,
                    &self.config.model,
                    url,
                ),
            });
        }

        Ok(CompletionOutput {
            content: content_buf,
            usage,
        })
    }
}

fn apply_stream_outcome<F>(
    outcome: SseChunkOutcome,
    usage: &mut TokenUsage,
    content_buf: &mut String,
    on_chunk: &mut F,
    scratch: &mut String,
) where
    F: FnMut(&str, &mut String),
{
    if let Some(reported_usage) = outcome.usage {
        *usage = reported_usage;
    }
    if !outcome.content_deltas.is_empty() {
        content_buf.push_str(&outcome.content_deltas);
        on_chunk(content_buf, scratch);
    }
}

fn append_raw_preview(preview: &mut String, bytes: &[u8], limit: usize) {
    if preview.len() >= limit {
        return;
    }
    let remaining = limit - preview.len();
    let take = bytes.len().min(remaining);
    preview.push_str(&String::from_utf8_lossy(&bytes[..take]));
}

fn map_to_translation_result(
    map: &HashMap<String, String>,
    fallback_word: &str,
) -> TranslationResult {
    TranslationResult {
        word: map
            .get("word")
            .cloned()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| fallback_word.to_string()),
        phonetic: map.get("phonetic").cloned().unwrap_or_default(),
        part_of_speech: map.get("part_of_speech").cloned().unwrap_or_default(),
        context_translation: map.get("context_translation").cloned().unwrap_or_default(),
        context_explanation: map.get("context_explanation").cloned().unwrap_or_default(),
        etymology: map.get("etymology").cloned().unwrap_or_default(),
        general_definition: map.get("general_definition").cloned().unwrap_or_default(),
        context_sentence_translation: map
            .get("context_sentence_translation")
            .cloned()
            .unwrap_or_default(),
        source: "llm".to_string(),
        llm_error_message: String::new(),
        fallback_error_message: String::new(),
        is_complete_failure: false,
        sentence_breakdown: Vec::new(),
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
    }
}

fn explicit_image_capability(root: &Value, model: &str) -> Option<ImageInputCapability> {
    let model_value = match root.get("data") {
        Some(Value::Array(models)) => models
            .iter()
            .find(|candidate| candidate.get("id").and_then(Value::as_str) == Some(model)),
        Some(Value::Object(_)) => root.get("data"),
        _ => Some(root),
    }?;

    if let Some(supports_vision) = model_value
        .pointer("/capabilities/vision")
        .and_then(Value::as_bool)
    {
        return Some(if supports_vision {
            ImageInputCapability::Supported
        } else {
            ImageInputCapability::Unsupported
        });
    }

    let modalities = model_value
        .pointer("/architecture/input_modalities")
        .or_else(|| model_value.get("input_modalities"))
        .or_else(|| model_value.get("modalities"))?
        .as_array()?;
    let has_image = modalities
        .iter()
        .filter_map(Value::as_str)
        .any(|modality| modality.eq_ignore_ascii_case("image"));
    Some(if has_image {
        ImageInputCapability::Supported
    } else {
        ImageInputCapability::Unsupported
    })
}

fn is_explicit_image_unsupported_error(body: &str) -> bool {
    let lower = body.to_lowercase();
    let mentions_image = lower.contains("image")
        || lower.contains("vision")
        || lower.contains("multimodal")
        || lower.contains("image_url");
    let says_unsupported = lower.contains("unsupported")
        || lower.contains("not support")
        || lower.contains("does not support")
        || lower.contains("doesn't support")
        || lower.contains("only text")
        || lower.contains("text-only")
        || lower.contains("invalid content type")
        || lower.contains("only supported by")
        || lower.contains("cannot process");
    mentions_image && says_unsupported
}

#[derive(Clone, Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<ResponseFormat>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
    #[serde(skip_serializing_if = "is_false")]
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream_options: Option<StreamOptions>,
    /// Qwen / DashScope / SiliconFlow and many OpenAI-compatible gateways.
    #[serde(skip_serializing_if = "Option::is_none")]
    enable_thinking: Option<bool>,
    /// vLLM / SGLang chat templates that read `enable_thinking` from kwargs.
    #[serde(skip_serializing_if = "Option::is_none")]
    chat_template_kwargs: Option<ChatTemplateKwargs>,
    /// DeepSeek / GLM / Anthropic-compatible thinking control.
    #[serde(skip_serializing_if = "Option::is_none")]
    thinking: Option<ThinkingControl>,
    /// OpenRouter reasoning switch.
    #[serde(skip_serializing_if = "Option::is_none")]
    reasoning: Option<ReasoningControl>,
}

impl ChatRequest {
    fn has_vendor_extensions(&self) -> bool {
        self.stream_options.is_some()
            || self.enable_thinking.is_some()
            || self.chat_template_kwargs.is_some()
            || self.thinking.is_some()
            || self.reasoning.is_some()
    }

    fn without_vendor_extensions(mut self) -> Self {
        self.stream_options = None;
        self.enable_thinking = None;
        self.chat_template_kwargs = None;
        self.thinking = None;
        self.reasoning = None;
        self
    }
}

#[derive(Clone, Serialize)]
struct ChatTemplateKwargs {
    enable_thinking: bool,
}

#[derive(Clone, Serialize)]
struct ThinkingControl {
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Clone, Serialize)]
struct ReasoningControl {
    enabled: bool,
}

fn with_no_think_on_last_user(mut messages: Vec<Message>) -> Vec<Message> {
    if let Some(message) = messages.iter_mut().rev().find(|item| item.role == "user") {
        match &mut message.content {
            RequestMessageContent::Text(text) => {
                *text = ensure_no_think_suffix(text);
            }
            RequestMessageContent::Parts(parts) => {
                if let Some(RequestContentPart::Text { text }) = parts
                    .iter_mut()
                    .rev()
                    .find(|part| matches!(part, RequestContentPart::Text { .. }))
                {
                    *text = ensure_no_think_suffix(text);
                }
            }
        }
    }
    messages
}

fn is_unknown_optional_field_error(status: reqwest::StatusCode, body: &str) -> bool {
    if status.as_u16() != 400 {
        return false;
    }
    let lower = body.to_lowercase();
    lower.contains("unknown field")
        || lower.contains("unrecognized request")
        || lower.contains("unexpected argument")
        || lower.contains("enable_thinking")
        || lower.contains("chat_template_kwargs")
        || lower.contains("stream_options")
        || lower.contains("include_usage")
        || lower.contains("reasoning")
}

#[derive(Clone, Serialize)]
struct StreamOptions {
    include_usage: bool,
}

fn is_false(b: &bool) -> bool {
    !*b
}

#[derive(Clone, Serialize)]
struct Message {
    role: String,
    content: RequestMessageContent,
}

#[derive(Clone, Serialize)]
#[serde(untagged)]
enum RequestMessageContent {
    Text(String),
    Parts(Vec<RequestContentPart>),
}

#[derive(Clone, Serialize)]
#[serde(tag = "type")]
enum RequestContentPart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image_url")]
    ImageUrl { image_url: ImageUrlContent },
}

#[derive(Clone, Serialize)]
struct ImageUrlContent {
    url: String,
}

#[derive(Clone, Serialize)]
struct ResponseFormat {
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    #[serde(default)]
    choices: Vec<Choice>,
    #[serde(default)]
    usage: Option<TokenUsage>,
}

struct CompletionOutput {
    content: String,
    usage: TokenUsage,
}

#[derive(Deserialize)]
struct Choice {
    message: ResponseMessageContent,
}

#[derive(Deserialize)]
struct ResponseMessageContent {
    #[serde(default)]
    content: Option<String>,
    #[serde(default)]
    reasoning_content: Option<String>,
}

#[derive(Deserialize)]
struct LlmTranslationJson {
    word: Option<String>,
    phonetic: Option<String>,
    part_of_speech: Option<String>,
    context_translation: Option<String>,
    context_explanation: Option<String>,
    etymology: Option<String>,
    general_definition: Option<String>,
    context_sentence_translation: Option<String>,
}

impl LlmTranslationJson {
    fn into_result(self, fallback_word: &str, usage: TokenUsage) -> TranslationResult {
        TranslationResult {
            word: self.word.unwrap_or_else(|| fallback_word.to_string()),
            phonetic: self.phonetic.unwrap_or_default(),
            part_of_speech: self.part_of_speech.unwrap_or_default(),
            context_translation: self.context_translation.unwrap_or_default(),
            context_explanation: self.context_explanation.unwrap_or_default(),
            etymology: self.etymology.unwrap_or_default(),
            general_definition: self.general_definition.unwrap_or_default(),
            context_sentence_translation: self.context_sentence_translation.unwrap_or_default(),
            source: "llm".to_string(),
            llm_error_message: String::new(),
            fallback_error_message: String::new(),
            is_complete_failure: false,
            sentence_breakdown: Vec::new(),
            prompt_tokens: usage.prompt_tokens,
            completion_tokens: usage.completion_tokens,
            total_tokens: usage.total_tokens,
        }
    }
}

/// Wire format the LLM produces in sentence mode: a translation plus an
/// optional breakdown array for long / complex sentences.
#[derive(Deserialize)]
struct SentencePromptJson {
    translation: Option<String>,
    #[serde(default)]
    breakdown: Vec<SentenceChunkJson>,
}

#[derive(Deserialize)]
struct SentenceChunkJson {
    original: Option<String>,
    translation: Option<String>,
    explanation: Option<String>,
    #[serde(default)]
    grammar: String,
}

impl SentencePromptJson {
    /// Materialize into a fully-populated `TranslationResult` for sentence
    /// mode. `original_sentence` is stored in `word` so callers can correlate
    /// the result with the user's selection (consistent with v1.0.4).
    fn into_result(self, original_sentence: &str, usage: TokenUsage) -> TranslationResult {
        let breakdown: Vec<SentenceChunk> = self
            .breakdown
            .into_iter()
            .map(|c| SentenceChunk {
                original: c.original.unwrap_or_default(),
                translation: c.translation.unwrap_or_default(),
                explanation: c.explanation.unwrap_or_default(),
                grammar: c.grammar,
            })
            // Drop entirely-empty chunks defensively in case the model emits
            // a stray `{}` placeholder when it decides not to break down.
            .filter(|c| !c.original.is_empty() || !c.translation.is_empty())
            .collect();

        TranslationResult {
            word: original_sentence.to_string(),
            context_sentence_translation: self.translation.unwrap_or_default(),
            source: "llm".to_string(),
            sentence_breakdown: breakdown,
            prompt_tokens: usage.prompt_tokens,
            completion_tokens: usage.completion_tokens,
            total_tokens: usage.total_tokens,
            ..Default::default()
        }
    }
}

#[async_trait::async_trait]
impl Translator for LlmTranslator {
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, LumenError> {
        let body = self.build_word_request(word, sentence, false);
        let completion = self.send_chat_request(&body).await?;

        let parsed: LlmTranslationJson = parse_model_json(&completion.content)?;

        Ok(parsed.into_result(word, completion.usage))
    }

    async fn translate_streaming(
        &self,
        word: &str,
        sentence: &str,
        mut on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        let url = self.completions_url();
        let body = self.build_word_request(word, sentence, true);

        let mut last_keys: Vec<String> = Vec::new();
        let completion = self
            .stream_completion(&url, &body, |raw, _: &mut String| {
                let fields = extract_complete_string_fields(&streaming_json_view(raw));
                if fields.is_empty() {
                    return;
                }
                // Later occurrences of the same key win — robust against any
                // gateway that emits the same field twice.
                let mut map: HashMap<String, String> = HashMap::new();
                let mut current_keys: Vec<String> = Vec::new();
                for (k, v) in fields {
                    if !current_keys.contains(&k) {
                        current_keys.push(k.clone());
                    }
                    map.insert(k, v);
                }
                // Re-emitting on every chunk would flood SwiftUI with redundant
                // diffs. Emitting only when the set of completed keys grows
                // strikes the right balance between responsiveness and noise.
                if current_keys.len() == last_keys.len() {
                    return;
                }
                last_keys = current_keys;
                on_progress(map_to_translation_result(&map, word));
            })
            .await?;

        // End-of-stream: strict parse so missing optional fields default to
        // empty strings via serde and we always return a complete result.
        let parsed: LlmTranslationJson = parse_model_json(&completion.content)?;
        Ok(parsed.into_result(word, completion.usage))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn translator_with(base_url: &str, model: &str) -> LlmTranslator {
        LlmTranslator::new(LlmConfig {
            base_url: base_url.into(),
            api_key: "key".into(),
            model: model.into(),
            target_language: "简体中文".into(),
            word_prompt_template: String::new(),
            sentence_prompt_template: String::new(),
            explanation_prompt_template: String::new(),
            word_system_prompt: String::new(),
            sentence_system_prompt: String::new(),
            explanation_system_prompt: String::new(),
            extra_config: String::new(),
        })
    }

    fn translator() -> LlmTranslator {
        translator_with("https://example.com/v1", "vision-model")
    }

    fn dashscope_qwen() -> LlmTranslator {
        translator_with(
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "qwen-plus",
        )
    }

    #[test]
    fn explanation_request_serializes_images_as_openai_content_parts() {
        let request = translator().build_explanation_request(
            "selected",
            "context",
            "what does the diagram show?",
            &[ImageAttachment {
                file_name: "diagram.png".into(),
                mime_type: "image/png".into(),
                base64_data: "aGVsbG8=".into(),
            }],
            true,
        );

        let json = serde_json::to_value(request).unwrap();
        let parts = json["messages"][1]["content"].as_array().unwrap();

        assert_eq!(parts[0]["type"], "text");
        assert_eq!(parts[1]["text"], "Attached image 1: diagram.png");
        assert_eq!(parts[2]["type"], "image_url");
        assert_eq!(
            parts[2]["image_url"]["url"],
            "data:image/png;base64,aGVsbG8="
        );
    }

    #[test]
    fn explanation_request_keeps_plain_text_shape_without_images() {
        let request = translator().build_explanation_request("selected", "context", "", &[], true);
        let json = serde_json::to_value(request).unwrap();

        assert!(json["messages"][1]["content"].is_string());
    }

    #[test]
    fn dashscope_qwen_only_sends_enable_thinking_and_no_think() {
        let translator = dashscope_qwen();
        let requests = [
            translator.build_word_request("word", "a sentence", false),
            translator.build_sentence_request("a sentence", true),
            translator.build_explanation_request("selected", "context", "", &[], true),
        ];
        for request in requests {
            let json = serde_json::to_value(&request).unwrap();
            assert_eq!(json["enable_thinking"], false);
            assert!(json.get("chat_template_kwargs").is_none());
            assert!(json.get("thinking").is_none());
            assert!(json.get("reasoning").is_none());
            assert_last_user_ends_with_no_think(&json);
        }
    }

    #[test]
    fn extra_config_overrides_builtin_thinking_fields() {
        let mut translator = dashscope_qwen();
        translator.config.extra_config =
            r#"{"enable_thinking": true, "thinking_budget": 0}"#.into();
        let json = translator
            .chat_json(&translator.build_word_request("word", "a sentence", false))
            .unwrap();
        assert_eq!(json["enable_thinking"], true);
        assert_eq!(json["thinking_budget"], 0);
        assert!(json["messages"].is_array());
    }

    #[test]
    fn openai_omits_vendor_thinking_fields() {
        let json = serde_json::to_value(
            translator_with("https://api.openai.com/v1", "gpt-4o").build_word_request(
                "word",
                "a sentence",
                false,
            ),
        )
        .unwrap();
        assert!(json.get("enable_thinking").is_none());
        assert!(json.get("chat_template_kwargs").is_none());
        assert!(json.get("thinking").is_none());
        assert!(json.get("reasoning").is_none());
    }

    #[test]
    fn self_hosted_qwen_uses_chat_template_kwargs() {
        let json = serde_json::to_value(
            translator_with("http://127.0.0.1:8000/v1", "Qwen/Qwen3-8B").build_word_request(
                "word",
                "a sentence",
                false,
            ),
        )
        .unwrap();
        assert!(json.get("enable_thinking").is_none());
        assert_eq!(json["chat_template_kwargs"]["enable_thinking"], false);
        assert!(json.get("thinking").is_none());
        assert_last_user_ends_with_no_think(&json);
    }

    #[test]
    fn deepseek_uses_thinking_type_disabled() {
        let json =
            serde_json::to_value(
                translator_with("https://api.deepseek.com/v1", "deepseek-v4-flash")
                    .build_word_request("word", "a sentence", false),
            )
            .unwrap();
        assert_eq!(json["thinking"]["type"], "disabled");
        assert!(json.get("enable_thinking").is_none());
        assert!(json.get("chat_template_kwargs").is_none());
    }

    #[test]
    fn openrouter_uses_reasoning_enabled_false() {
        let json =
            serde_json::to_value(
                translator_with("https://openrouter.ai/api/v1", "qwen/qwen3-32b")
                    .build_word_request("word", "a sentence", false),
            )
            .unwrap();
        assert_eq!(json["reasoning"]["enabled"], false);
        assert!(json.get("enable_thinking").is_none());
        assert!(json.get("thinking").is_none());
    }

    #[test]
    fn stripping_vendor_extensions_omits_thinking_fields() {
        let request = dashscope_qwen()
            .build_word_request("word", "a sentence", true)
            .without_vendor_extensions();
        let json = serde_json::to_value(request).unwrap();
        assert!(json.get("enable_thinking").is_none());
        assert!(json.get("chat_template_kwargs").is_none());
        assert!(json.get("thinking").is_none());
        assert!(json.get("reasoning").is_none());
        assert!(json.get("stream_options").is_none());
    }

    fn assert_last_user_ends_with_no_think(json: &Value) {
        let messages = json["messages"].as_array().unwrap();
        let user = messages
            .iter()
            .rev()
            .find(|message| message["role"] == "user")
            .unwrap();
        let content = if user["content"].is_string() {
            user["content"].as_str().unwrap().to_string()
        } else {
            user["content"]
                .as_array()
                .unwrap()
                .iter()
                .rev()
                .find_map(|part| part["text"].as_str())
                .unwrap()
                .to_string()
        };
        assert!(
            content.trim_end().ends_with("/no_think"),
            "expected /no_think suffix, got {content}"
        );
    }

    #[test]
    fn unknown_thinking_fields_are_retryable_on_bad_request() {
        assert!(is_unknown_optional_field_error(
            reqwest::StatusCode::BAD_REQUEST,
            r#"{"error":{"message":"Unrecognized request argument supplied: enable_thinking"}}"#
        ));
        assert!(!is_unknown_optional_field_error(
            reqwest::StatusCode::UNAUTHORIZED,
            "enable_thinking"
        ));
    }

    #[test]
    fn reads_image_capability_from_openrouter_style_metadata() {
        let metadata = serde_json::json!({
            "data": [{
                "id": "vision-model",
                "architecture": {
                    "input_modalities": ["text", "image"]
                }
            }]
        });

        assert_eq!(
            explicit_image_capability(&metadata, "vision-model"),
            Some(ImageInputCapability::Supported)
        );
    }

    #[test]
    fn reads_explicit_text_only_capability_from_metadata() {
        let metadata = serde_json::json!({
            "data": [{
                "id": "text-model",
                "architecture": {
                    "input_modalities": ["text"]
                }
            }]
        });

        assert_eq!(
            explicit_image_capability(&metadata, "text-model"),
            Some(ImageInputCapability::Unsupported)
        );
    }

    #[test]
    fn only_classifies_explicit_image_errors_as_unsupported() {
        assert!(is_explicit_image_unsupported_error(
            r#"{"error":{"message":"This model does not support image_url content"}}"#
        ));
        assert!(!is_explicit_image_unsupported_error(
            r#"{"error":{"message":"Rate limit exceeded"}}"#
        ));
    }

    #[test]
    fn word_cache_scope_is_stable_for_the_same_effective_prompt() {
        let config = translator().config;
        let mut explicit_defaults = config.clone();
        explicit_defaults.word_prompt_template = DEFAULT_WORD_PROMPT_TEMPLATE.into();
        explicit_defaults.word_system_prompt = DEFAULT_WORD_SYSTEM_PROMPT.into();

        assert_eq!(
            config.word_cache_scope(),
            explicit_defaults.word_cache_scope()
        );
    }

    #[test]
    fn word_cache_scope_changes_when_the_prompt_changes() {
        let config = translator().config;
        let mut customized = config.clone();
        customized.word_prompt_template = "custom {word} {sentence} {lang}".into();

        assert_ne!(config.word_cache_scope(), customized.word_cache_scope());
    }
}
