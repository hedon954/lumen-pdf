//! Repair and deserialize JSON that LLMs return for word/sentence translation.
//!
//! Models often wrap the object in markdown fences, leave a trailing comma, or
//! use Python/JS literals. `jsonrepair-rs` (a port of Jos de Jong's jsonrepair)
//! turns that into valid JSON before serde. Streaming field extraction only
//! strips fences so incomplete values are not closed early.

use crate::error::LumenError;
use crate::infrastructure::translator::streaming::preview_text;
use serde::de::DeserializeOwned;
use serde_json::Value;

pub fn parse_model_json<T: DeserializeOwned>(raw: &str) -> Result<T, LumenError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(empty_json_error());
    }

    if let Ok(value) = serde_json::from_str(trimmed) {
        return Ok(value);
    }

    let repaired = repair_model_json_text(trimmed);
    deserialize_repaired(&repaired).map_err(|err| json_parse_error(raw, err))
}

/// Best-effort valid JSON text after the model has finished emitting.
pub fn repair_model_json_text(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    jsonrepair_rs::jsonrepair(trimmed).unwrap_or_else(|_| normalize_json_payload(trimmed))
}

/// Drop markdown fences and leading prose so streaming scanners can see `{`.
/// Does not jsonrepair: that would close in-progress strings too early.
pub fn streaming_json_view(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if let Some(start) = trimmed.find('{') {
        return trimmed[start..].to_string();
    }
    strip_code_fence(trimmed)
}

fn deserialize_repaired<T: DeserializeOwned>(json: &str) -> Result<T, serde_json::Error> {
    match serde_json::from_str::<T>(json) {
        Ok(value) => Ok(value),
        Err(first) => {
            let Ok(value) = serde_json::from_str::<Value>(json) else {
                return Err(first);
            };
            let Some(object) = first_json_object(value) else {
                return Err(first);
            };
            serde_json::from_value(object)
        }
    }
}

fn first_json_object(value: Value) -> Option<Value> {
    match value {
        Value::Object(_) => Some(value),
        Value::Array(items) => items.into_iter().find(Value::is_object),
        _ => None,
    }
}

fn normalize_json_payload(raw: &str) -> String {
    let unfenced = strip_code_fence(raw.trim());
    extract_json_span(&unfenced)
        .map(ToOwned::to_owned)
        .unwrap_or(unfenced)
}

fn strip_code_fence(raw: &str) -> String {
    let trimmed = raw.trim();
    if !trimmed.starts_with("```") {
        return trimmed.to_string();
    }
    let mut lines = trimmed.lines();
    let _ = lines.next();
    let mut body: Vec<&str> = lines.collect();
    if body.last().is_some_and(|line| line.trim() == "```") {
        body.pop();
    }
    body.join("\n").trim().to_string()
}

fn extract_json_span(raw: &str) -> Option<&str> {
    let start = raw.find('{')?;
    let end = raw.rfind('}')?;
    if end >= start {
        Some(&raw[start..=end])
    } else {
        None
    }
}

fn empty_json_error() -> LumenError {
    LumenError::LlmApiError {
        message: "模型没有返回任何内容（空响应），因此无法解析 JSON。常见原因：网关返回空 body、流式协议不匹配，或模型拒绝输出。".into(),
    }
}

fn json_parse_error(raw: &str, err: serde_json::Error) -> LumenError {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return empty_json_error();
    }
    LumenError::SerializationError {
        message: format!(
            "{err}。响应长度 {} 字符。内容预览：{}",
            trimmed.chars().count(),
            preview_text(trimmed, 400)
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Debug, Deserialize)]
    struct WordJson {
        word: Option<String>,
        context_translation: Option<String>,
    }

    #[test]
    fn parses_markdown_fenced_json() {
        let parsed: WordJson = parse_model_json(
            "```json\n{\"word\":\"performed\",\"context_translation\":\"执行了\"}\n```\n",
        )
        .expect("fenced JSON should repair");
        assert_eq!(parsed.word.as_deref(), Some("performed"));
        assert_eq!(parsed.context_translation.as_deref(), Some("执行了"));
    }

    #[test]
    fn repairs_trailing_comma_and_single_quotes() {
        let parsed: WordJson =
            parse_model_json("{'word': 'performed', 'context_translation': '执行了',}")
                .expect("trailing comma / single quotes should repair");
        assert_eq!(parsed.word.as_deref(), Some("performed"));
    }

    #[test]
    fn repairs_python_literals() {
        let parsed: WordJson =
            parse_model_json(r#"{"word": "performed", "context_translation": None}"#)
                .expect("Python None should repair");
        assert_eq!(parsed.word.as_deref(), Some("performed"));
        assert_eq!(parsed.context_translation.as_deref(), None);
    }

    #[test]
    fn repairs_truncated_object() {
        let parsed: WordJson =
            parse_model_json(r#"{"word": "performed", "context_translation": "执行了""#)
                .expect("missing closing brace should repair");
        assert_eq!(parsed.word.as_deref(), Some("performed"));
        assert_eq!(parsed.context_translation.as_deref(), Some("执行了"));
    }

    #[test]
    fn extracts_object_from_prose_and_fences() {
        let parsed: WordJson = parse_model_json(
            "here you go\n```json\n{\"word\":\"performed\",\"context_translation\":\"执行了\"}\n```\n",
        )
        .expect("prose plus fenced JSON should repair");
        assert_eq!(parsed.word.as_deref(), Some("performed"));
    }

    #[test]
    fn empty_payload_is_llm_api_error() {
        match parse_model_json::<WordJson>("") {
            Err(LumenError::LlmApiError { message }) => {
                assert!(message.contains("空响应"));
            }
            Err(other) => panic!("unexpected error: {other}"),
            Ok(_) => panic!("empty payload should not parse"),
        }
    }

    #[test]
    fn streaming_view_keeps_truncated_object_open() {
        let view =
            streaming_json_view("```json\n{\"word\": \"performed\", \"context_translation\": \"执");
        assert!(view.starts_with('{'), "expected object start, got {view}");
        assert!(
            !view.contains("```"),
            "fence prefix should be dropped: {view}"
        );
        assert!(
            !view.trim_end().ends_with('}'),
            "truncated object must stay open: {view}"
        );
    }
}
