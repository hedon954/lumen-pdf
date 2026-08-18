//! Helpers for consuming OpenAI-compatible Server-Sent Events (SSE) streams
//! and progressively extracting JSON fields from a still-being-emitted object.
//!
//! Why this exists: by the time an LLM has finished producing every token of a
//! 7-field JSON response we've already burned 3–8 s. Streaming each delta and
//! emitting fields as they complete cuts perceived latency to the time-to-first
//! token (often < 1 s).
//!
//! Two stages:
//!
//! 1. `parse_sse_chunk` splits a raw byte chunk from `reqwest::bytes_stream()`
//!    into `(line_buffer, content_deltas)` — we keep the trailing fragment
//!    that hasn't seen a `\n` yet for the next chunk.
//! 2. `extract_complete_string_fields` scans the accumulating JSON buffer for
//!    `"key": "value"` pairs whose closing quote has already been received and
//!    returns them. Partial fields (still streaming) are simply absent from
//!    the result; once a field finishes it shows up on the next call.

use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize)]
pub struct TokenUsage {
    #[serde(default)]
    pub prompt_tokens: u64,
    #[serde(default)]
    pub completion_tokens: u64,
    #[serde(default)]
    pub total_tokens: u64,
}

/// Result of feeding one raw byte chunk into the SSE parser.
pub struct SseChunkOutcome {
    /// Concatenated `delta.content` strings extracted from this chunk.
    pub content_deltas: String,
    /// True when the stream signalled `data: [DONE]`.
    pub done: bool,
    /// Usage appears in the terminal OpenAI-compatible stream frame when
    /// `stream_options.include_usage` is supported by the provider.
    pub usage: Option<TokenUsage>,
}

/// Stateful SSE line buffer. Call `feed` with each `bytes_stream()` chunk; it
/// returns the new content deltas plus a `done` flag once `[DONE]` arrives.
#[derive(Default)]
pub struct SseAccumulator {
    /// Bytes received so far that haven't been split on `\n`.
    pending: String,
    pub finish_reason: Option<String>,
    pub reasoning: String,
    pub parsed_frames: usize,
    pub ignored_frames: usize,
    pub ignored_preview: String,
    pub gateway_error: Option<String>,
}

impl SseAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn feed(&mut self, chunk: &str) -> SseChunkOutcome {
        self.pending.push_str(chunk);
        let mut content = String::new();
        let mut done = false;
        let mut usage = None;

        // Process every fully-received line; keep the partial trailing line.
        while let Some(idx) = self.pending.find('\n') {
            let line = self.pending[..idx].trim_end_matches('\r').to_string();
            self.pending.drain(..=idx);
            let Some(payload) = sse_payload_from_line(&line) else {
                continue;
            };
            if payload.is_empty() {
                continue;
            }
            if payload == "[DONE]" {
                done = true;
                continue;
            }
            let view = interpret_sse_payload(payload);
            if !view.parsed {
                self.ignored_frames += 1;
                capture_preview(&mut self.ignored_preview, payload, 400);
                continue;
            }
            self.parsed_frames += 1;
            if let Some(reported_usage) = view.usage {
                usage = Some(reported_usage);
            }
            if let Some(reason) = view.finish_reason {
                self.finish_reason = Some(reason);
            }
            if let Some(error) = view.error {
                self.gateway_error = Some(error);
            }
            if !view.reasoning.is_empty() {
                self.reasoning.push_str(&view.reasoning);
            }
            if !view.content.is_empty() {
                content.push_str(&view.content);
            }
        }

        SseChunkOutcome {
            content_deltas: content,
            done,
            usage,
        }
    }

    /// Some gateways omit the trailing newline on the last SSE frame.
    pub fn flush(&mut self) -> SseChunkOutcome {
        if self.pending.is_empty() {
            return SseChunkOutcome {
                content_deltas: String::new(),
                done: false,
                usage: None,
            };
        }
        if !self.pending.ends_with('\n') {
            self.pending.push('\n');
        }
        self.feed("")
    }
}

#[derive(Debug, Default)]
pub struct SsePayloadView {
    pub content: String,
    pub reasoning: String,
    pub finish_reason: Option<String>,
    pub usage: Option<TokenUsage>,
    pub error: Option<String>,
    pub parsed: bool,
}

pub fn interpret_sse_payload(payload: &str) -> SsePayloadView {
    let trimmed = payload.trim();
    if trimmed.is_empty() {
        return SsePayloadView::default();
    }
    match serde_json::from_str::<Value>(trimmed) {
        Ok(value) => interpret_sse_value(&value),
        Err(_) => SsePayloadView::default(),
    }
}

pub fn extract_message_content_from_json(raw: &str) -> Option<(String, TokenUsage)> {
    let value = serde_json::from_str::<Value>(raw.trim()).ok()?;
    let view = interpret_sse_value(&value);
    let content = view.content.trim();
    if content.is_empty() {
        return None;
    }
    Some((content.to_string(), view.usage.unwrap_or_default()))
}

pub fn describe_empty_model_output(
    bytes_received: usize,
    accumulator: &SseAccumulator,
    raw_preview: &str,
    usage: TokenUsage,
    model: &str,
    url: &str,
) -> String {
    let mut parts = vec![
        "模型没有返回任何可用正文。".to_string(),
        format!("请求地址：{url}"),
        format!("模型：{}", if model.is_empty() { "未配置" } else { model }),
        format!(
            "收到 {bytes_received} 字节，成功解析 {} 个流式帧，忽略 {} 个无法识别的帧。",
            accumulator.parsed_frames, accumulator.ignored_frames
        ),
    ];
    if usage.total_tokens == 0 && usage.prompt_tokens == 0 && usage.completion_tokens == 0 {
        parts.push(
            "Token 用量为 0，说明接口几乎没有生成输出，模型很可能没有真正开始推理。".to_string(),
        );
    } else {
        parts.push(format!(
            "Token：输入 {}，输出 {}，合计 {}。",
            usage.prompt_tokens, usage.completion_tokens, usage.total_tokens
        ));
    }
    if let Some(reason) = &accumulator.finish_reason {
        parts.push(format!("finish_reason：{reason}"));
    }
    if let Some(error) = &accumulator.gateway_error {
        parts.push(format!("网关错误：{error}"));
    }
    if !accumulator.reasoning.trim().is_empty() {
        parts.push(format!(
            "模型只返回了思考过程，没有最终答案。思考预览：{}",
            preview_text(&accumulator.reasoning, 240)
        ));
    }
    if !accumulator.ignored_preview.trim().is_empty() {
        parts.push(format!(
            "未识别帧预览：{}",
            preview_text(&accumulator.ignored_preview, 280)
        ));
    }
    let preview = raw_preview.trim();
    if preview.is_empty() {
        parts.push(
            "原始响应完全为空：常见于网关返回空 body、流式协议不匹配，或请求在到达模型前被拒绝。"
                .to_string(),
        );
    } else {
        parts.push(format!("原始响应预览：{}", preview_text(preview, 420)));
    }
    parts.join(" ")
}

fn interpret_sse_value(value: &Value) -> SsePayloadView {
    let mut view = SsePayloadView {
        parsed: true,
        ..SsePayloadView::default()
    };

    if let Some(error) = value.get("error") {
        view.error = Some(sse_error_text(error));
    }

    if let Some(usage_value) = value.get("usage") {
        if let Ok(usage) = serde_json::from_value::<TokenUsage>(usage_value.clone()) {
            if usage.prompt_tokens > 0 || usage.completion_tokens > 0 || usage.total_tokens > 0 {
                view.usage = Some(usage);
            }
        }
    }

    let choices = value
        .get("choices")
        .and_then(Value::as_array)
        .cloned()
        .or_else(|| {
            value
                .pointer("/output/choices")
                .and_then(Value::as_array)
                .cloned()
        });

    if let Some(choice) = choices.as_ref().and_then(|items| items.first()) {
        view.finish_reason = choice
            .get("finish_reason")
            .and_then(Value::as_str)
            .filter(|reason| !reason.is_empty())
            .map(ToOwned::to_owned);
        append_content_from_node(choice.get("delta"), &mut view);
        append_content_from_node(choice.get("message"), &mut view);
        push_content_value(choice.get("text"), &mut view.content);
    }

    view
}

fn append_content_from_node(node: Option<&Value>, view: &mut SsePayloadView) {
    let Some(node) = node else {
        return;
    };
    push_content_value(node.get("content"), &mut view.content);
    push_content_value(node.get("reasoning_content"), &mut view.reasoning);
    push_content_value(node.get("reasoning"), &mut view.reasoning);
}

fn push_content_value(value: Option<&Value>, dest: &mut String) {
    let Some(value) = value else {
        return;
    };
    match value {
        Value::String(text) => dest.push_str(text),
        Value::Array(parts) => {
            for part in parts {
                if let Some(text) = part.get("text").and_then(Value::as_str) {
                    dest.push_str(text);
                } else if let Some(text) = part.as_str() {
                    dest.push_str(text);
                }
            }
        }
        _ => {}
    }
}

fn sse_error_text(error: &Value) -> String {
    if let Some(message) = error.get("message").and_then(Value::as_str) {
        if let Some(code) = error.get("code").and_then(Value::as_str) {
            return format!("{code}: {message}");
        }
        return message.to_string();
    }
    error.to_string()
}

fn sse_payload_from_line(line: &str) -> Option<&str> {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.starts_with(':') {
        return None;
    }
    if let Some(payload) = trimmed.strip_prefix("data:") {
        return Some(payload.trim());
    }
    if trimmed.starts_with('{') {
        return Some(trimmed);
    }
    None
}

fn capture_preview(buffer: &mut String, chunk: &str, limit: usize) {
    if buffer.len() >= limit {
        return;
    }
    let remaining = limit - buffer.len();
    let preview = preview_text(chunk, remaining);
    if !buffer.is_empty() {
        buffer.push('\n');
    }
    buffer.push_str(&preview);
}

pub fn preview_text(text: &str, limit: usize) -> String {
    let trimmed = text.trim();
    if trimmed.chars().count() <= limit {
        return trimmed.to_string();
    }
    let end = trimmed
        .char_indices()
        .nth(limit)
        .map(|(index, _)| index)
        .unwrap_or(trimmed.len());
    format!("{}…", &trimmed[..end])
}

/// Scan `buf` for top-level `"key": "value"` pairs whose closing `"` of the
/// value has already arrived. Returns `(key, decoded_value)` for every such
/// pair. Stops at the first incomplete value so we never emit half a field.
///
/// Tolerant by design:
/// - Skips characters that aren't part of a recognisable key/value start.
/// - Handles JSON string escapes (`\"`, `\\`, `\n`, `\u00ff`, etc.) inside values.
/// - Doesn't care about commas, surrounding `{}`, or whitespace, so it works
///   on the raw JSON-as-it-streams buffer without waiting for the closing brace.
///
/// UTF-8 safety: the structural delimiters we scan for (`"`, `:`, `\\`,
/// whitespace) are all ASCII (< 0x80) and cannot collide with continuation
/// bytes of multi-byte UTF-8 sequences, so byte-level scanning is safe even
/// when the buffer contains CJK / IPA / emoji characters.
pub fn extract_complete_string_fields(buf: &str) -> Vec<(String, String)> {
    let bytes = buf.as_bytes();
    let mut out: Vec<(String, String)> = Vec::new();
    let mut i = 0usize;

    while i < bytes.len() {
        if bytes[i] != b'"' {
            i += 1;
            continue;
        }
        let Some((key, after_key)) = read_json_string(buf, i + 1) else {
            // Closing quote of the key not yet streamed → nothing more we can
            // safely emit; bail out.
            break;
        };
        i = after_key;
        i = skip_ws(bytes, i);
        if i >= bytes.len() || bytes[i] != b':' {
            // Not a key, just a string literal in some other position. Move on.
            continue;
        }
        i += 1;
        i = skip_ws(bytes, i);
        if i >= bytes.len() {
            break;
        }
        if bytes[i] != b'"' {
            // Numbers/booleans/objects — not part of our string-only schema;
            // skip and keep scanning.
            continue;
        }
        let Some((value, after_val)) = read_json_string(buf, i + 1) else {
            // Value still streaming. Stop — wait for more bytes.
            break;
        };
        out.push((key, value));
        i = after_val;
    }

    out
}

fn skip_ws(bytes: &[u8], mut i: usize) -> usize {
    while i < bytes.len() {
        match bytes[i] {
            b' ' | b'\t' | b'\n' | b'\r' => i += 1,
            _ => break,
        }
    }
    i
}

/// Returns the in-progress value of `key` as the LLM streams it, even before
/// the closing quote arrives. `None` means the key hasn't been seen yet, or
/// its opening quote hasn't started.
///
/// Use this when you have a known schema with one specific field whose value
/// you want to render *as it streams in* (e.g. `"translation"` for sentence
/// translation). For the general "wait until each field completes" mode, use
/// `extract_complete_string_fields` instead.
///
/// The returned string already has JSON escapes resolved.
pub fn extract_streaming_string_value(buf: &str, key: &str) -> Option<String> {
    // Locate the key. We use a literal `"key"` match because in OpenAI-style
    // JSON output keys never contain escapes, and false positives (e.g. the
    // key string appearing inside another value) are not a concern in our
    // narrow schema.
    let needle = format!("\"{key}\"");
    let key_idx = buf.find(&needle)?;
    let bytes = buf.as_bytes();
    let mut i = key_idx + needle.len();
    i = skip_ws(bytes, i);
    if i >= bytes.len() || bytes[i] != b':' {
        return None;
    }
    i = skip_ws(bytes, i + 1);
    if i >= bytes.len() || bytes[i] != b'"' {
        return None;
    }
    Some(read_json_string_partial(buf, i + 1))
}

/// Read a JSON string starting at `start` (byte AFTER the opening quote)
/// and return whatever has been received so far — the closing quote may or
/// may not have arrived yet.
fn read_json_string_partial(buf: &str, start: usize) -> String {
    let mut out = String::new();
    let mut chars = buf[start..].char_indices();
    while let Some((_, c)) = chars.next() {
        match c {
            '"' => return out,
            '\\' => {
                let Some((_, esc)) = chars.next() else {
                    // Trailing `\` with no escape kind yet — drop it; the
                    // next chunk will deliver the rest. Returning what we
                    // have so far is fine because the caller compares
                    // against the previous emit and will simply not re-fire
                    // until something new shows up.
                    return out;
                };
                match esc {
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    '/' => out.push('/'),
                    'b' => out.push('\u{0008}'),
                    'f' => out.push('\u{000C}'),
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    'u' => {
                        let mut hex = String::with_capacity(4);
                        for _ in 0..4 {
                            let Some((_, hc)) = chars.next() else {
                                return out;
                            };
                            hex.push(hc);
                        }
                        if let Ok(cp) = u32::from_str_radix(&hex, 16) {
                            if let Some(ch) = char::from_u32(cp) {
                                out.push(ch);
                            }
                        }
                    }
                    other => out.push(other),
                }
            }
            other => out.push(other),
        }
    }
    out
}

/// Read a JSON string from `buf` starting at byte offset `start` (i.e. the
/// byte AFTER the opening quote). Returns `(decoded, byte_index_after_closing_quote)`,
/// or `None` if the closing quote hasn't been received yet.
fn read_json_string(buf: &str, start: usize) -> Option<(String, usize)> {
    let mut out = String::new();
    let mut chars = buf[start..].char_indices();
    while let Some((rel_i, c)) = chars.next() {
        let abs_i = start + rel_i;
        match c {
            '"' => return Some((out, abs_i + 1)),
            '\\' => {
                let (_, esc) = chars.next()?;
                match esc {
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    '/' => out.push('/'),
                    'b' => out.push('\u{0008}'),
                    'f' => out.push('\u{000C}'),
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    'u' => {
                        // \uXXXX — must read 4 hex digits.
                        let mut hex = String::with_capacity(4);
                        for _ in 0..4 {
                            let (_, hc) = chars.next()?;
                            hex.push(hc);
                        }
                        let cp = u32::from_str_radix(&hex, 16).ok()?;
                        if let Some(ch) = char::from_u32(cp) {
                            out.push(ch);
                        }
                    }
                    // Unknown escape — preserve verbatim so we don't crash on
                    // gateway quirks.
                    other => out.push(other),
                }
            }
            other => out.push(other),
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_usage_from_terminal_stream_frame() {
        let mut accumulator = SseAccumulator::new();
        let outcome = accumulator.feed(
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":8,\"total_tokens\":20}}\n\n",
        );

        assert_eq!(
            outcome.usage,
            Some(TokenUsage {
                prompt_tokens: 12,
                completion_tokens: 8,
                total_tokens: 20,
            })
        );
    }

    #[test]
    fn extract_simple_fields() {
        let buf = r#"{"word": "investigate", "phonetic": "/ɪnˈvɛstɪˌɡeɪt/""#;
        let fields = extract_complete_string_fields(buf);
        assert_eq!(
            fields,
            vec![
                ("word".to_string(), "investigate".to_string()),
                ("phonetic".to_string(), "/ɪnˈvɛstɪˌɡeɪt/".to_string()),
            ]
        );
    }

    #[test]
    fn stops_at_incomplete_value() {
        // The phonetic value's closing quote hasn't been streamed yet.
        let buf = r#"{"word": "investigate", "phonetic": "/ɪnˈvɛstɪ"#;
        let fields = extract_complete_string_fields(buf);
        assert_eq!(
            fields,
            vec![("word".to_string(), "investigate".to_string())]
        );
    }

    #[test]
    fn handles_escaped_quotes_in_value() {
        let buf = r#"{"context_explanation": "She said \"hi\" politely.""#;
        let fields = extract_complete_string_fields(buf);
        assert_eq!(
            fields,
            vec![(
                "context_explanation".to_string(),
                r#"She said "hi" politely."#.to_string()
            )]
        );
    }

    #[test]
    fn handles_unicode_escape() {
        let buf = r#"{"context_translation": "\u4f60\u597d""#;
        let fields = extract_complete_string_fields(buf);
        assert_eq!(
            fields,
            vec![("context_translation".to_string(), "你好".to_string())]
        );
    }

    #[test]
    fn empty_buffer_returns_empty() {
        assert!(extract_complete_string_fields("").is_empty());
        assert!(extract_complete_string_fields("{").is_empty());
        assert!(extract_complete_string_fields(r#"{"key""#).is_empty());
    }

    #[test]
    fn ignores_non_string_values() {
        // Numbers, booleans, etc. are silently skipped.
        let buf = r#"{"count": 5, "ok": true, "word": "hi""#;
        let fields = extract_complete_string_fields(buf);
        assert_eq!(fields, vec![("word".to_string(), "hi".to_string())]);
    }

    #[test]
    fn sse_accumulator_basic_flow() {
        let mut acc = SseAccumulator::new();
        let chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"hel\"}}]}\n\n";
        let out1 = acc.feed(chunk1);
        assert_eq!(out1.content_deltas, "hel");
        assert!(!out1.done);

        let chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\ndata: [DONE]\n\n";
        let out2 = acc.feed(chunk2);
        assert_eq!(out2.content_deltas, "lo");
        assert!(out2.done);
    }

    #[test]
    fn sse_accumulator_handles_split_lines() {
        let mut acc = SseAccumulator::new();
        // First half: line is split mid-way.
        let out1 = acc.feed("data: {\"choices\":[{\"delta\":{\"content\":\"par");
        assert_eq!(out1.content_deltas, "");
        assert!(!out1.done);
        // Second half: completes the previous line.
        let out2 = acc.feed("tial\"}}]}\n\n");
        assert_eq!(out2.content_deltas, "partial");
    }

    #[test]
    fn streaming_value_returns_partial_when_unclosed() {
        let buf = r#"{"translation": "你好世"#;
        assert_eq!(
            extract_streaming_string_value(buf, "translation"),
            Some("你好世".to_string())
        );
    }

    #[test]
    fn streaming_value_returns_complete_when_closed() {
        let buf = r#"{"translation": "你好世界"}"#;
        assert_eq!(
            extract_streaming_string_value(buf, "translation"),
            Some("你好世界".to_string())
        );
    }

    #[test]
    fn streaming_value_handles_escapes_mid_stream() {
        // Escaped quote inside the value, no closing quote yet.
        let buf = r#"{"translation": "She said \"hi"#;
        assert_eq!(
            extract_streaming_string_value(buf, "translation"),
            Some(r#"She said "hi"#.to_string())
        );
    }

    #[test]
    fn streaming_value_handles_unicode_escape() {
        let buf = r#"{"translation": "\u4f60\u597d"#;
        assert_eq!(
            extract_streaming_string_value(buf, "translation"),
            Some("你好".to_string())
        );
    }

    #[test]
    fn streaming_value_handles_dangling_backslash() {
        // The model just emitted `\` and we haven't seen the escape kind yet.
        let buf = r#"{"translation": "hello\"#;
        assert_eq!(
            extract_streaming_string_value(buf, "translation"),
            Some("hello".to_string())
        );
    }

    #[test]
    fn streaming_value_returns_none_when_key_missing() {
        let buf = r#"{"other": "x""#;
        assert!(extract_streaming_string_value(buf, "translation").is_none());
    }

    #[test]
    fn streaming_value_returns_none_when_value_not_started() {
        let buf = r#"{"translation""#;
        assert!(extract_streaming_string_value(buf, "translation").is_none());
        let buf2 = r#"{"translation":"#;
        assert!(extract_streaming_string_value(buf2, "translation").is_none());
        // Whitespace allowed after `:`.
        let buf3 = r#"{"translation": "#;
        assert!(extract_streaming_string_value(buf3, "translation").is_none());
    }

    #[test]
    fn streaming_value_returns_empty_when_value_just_started() {
        // Opening quote received but no characters yet — empty string.
        let buf = r#"{"translation": ""#;
        assert_eq!(
            extract_streaming_string_value(buf, "translation"),
            Some(String::new())
        );
    }

    #[test]
    fn sse_accumulator_ignores_non_data_lines() {
        let mut acc = SseAccumulator::new();
        let chunk = ": keep-alive\n\nevent: ping\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n";
        let out = acc.feed(chunk);
        assert_eq!(out.content_deltas, "ok");
    }

    #[test]
    fn sse_accumulator_reads_reasoning_and_plain_json_lines() {
        let mut acc = SseAccumulator::new();
        let chunk = "{\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}\n\n";
        let out = acc.feed(chunk);
        assert_eq!(out.content_deltas, "answer");
        assert_eq!(acc.reasoning, "think");
        assert_eq!(acc.finish_reason.as_deref(), Some("stop"));
    }

    #[test]
    fn extract_message_content_from_non_stream_json() {
        let raw = r#"{"choices":[{"message":{"content":"{\"translation\":\"你好\"}"}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#;
        let (content, usage) = extract_message_content_from_json(raw).unwrap();
        assert_eq!(content, r#"{"translation":"你好"}"#);
        assert_eq!(usage.total_tokens, 5);
    }

    #[test]
    fn interpret_sse_payload_reads_content_parts_and_gateway_error() {
        let parts = r#"{"choices":[{"delta":{"content":[{"type":"text","text":"hel"},{"type":"text","text":"lo"}]}}]}"#;
        assert_eq!(interpret_sse_payload(parts).content, "hello");

        let error = interpret_sse_payload(
            r#"{"error":{"code":"invalid_api_key","message":"Incorrect API key"}}"#,
        );
        assert_eq!(
            error.error.as_deref(),
            Some("invalid_api_key: Incorrect API key")
        );
    }

    #[test]
    fn empty_output_description_mentions_zero_tokens_and_raw_preview() {
        let description = describe_empty_model_output(
            12,
            &SseAccumulator::default(),
            "",
            TokenUsage::default(),
            "qwen3.6-flash",
            "https://example.test/v1/chat/completions",
        );
        assert!(description.contains("没有返回任何可用正文"));
        assert!(description.contains("Token 用量为 0"));
        assert!(description.contains("qwen3.6-flash"));
        assert!(description.contains("原始响应完全为空"));
    }
}
