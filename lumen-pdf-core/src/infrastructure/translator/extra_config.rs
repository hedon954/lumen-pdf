//! Merge user-supplied chat-completions extra fields into a request body.
//!
//! Reserved keys (`messages`, `stream`, `stream_options`) stay under the app's
//! control. Other keys deep-merge, and the user's value wins on conflict.

use crate::error::LumenError;
use serde::Serialize;
use serde_json::{Map, Value};

const RESERVED_KEYS: &[&str] = &["messages", "stream", "stream_options"];

pub fn merge_chat_request<T: Serialize>(body: &T, extra_config: &str) -> Result<Value, LumenError> {
    let mut value = serde_json::to_value(body)
        .map_err(|err| LumenError::serialization(format!("无法序列化 LLM 请求：{err}")))?;
    if let Some(extra) = parse_extra_object(extra_config)? {
        merge_objects(&mut value, extra);
    }
    Ok(value)
}

fn parse_extra_object(raw: &str) -> Result<Option<Map<String, Value>>, LumenError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let value: Value = serde_json::from_str(trimmed)
        .map_err(|err| LumenError::serialization(format!("Extra Config 不是合法 JSON：{err}")))?;
    match value {
        Value::Object(map) => Ok(Some(map)),
        _ => Err(LumenError::serialization(
            "Extra Config 必须是 JSON 对象，例如 {\"enable_thinking\": false}。",
        )),
    }
}

fn merge_objects(base: &mut Value, extra: Map<String, Value>) {
    let Some(base_map) = base.as_object_mut() else {
        return;
    };
    for (key, extra_value) in extra {
        if RESERVED_KEYS.contains(&key.as_str()) {
            continue;
        }
        match base_map.get_mut(&key) {
            Some(existing) if existing.is_object() && extra_value.is_object() => {
                if let Value::Object(nested) = extra_value {
                    merge_objects(existing, nested);
                }
            }
            _ => {
                base_map.insert(key, extra_value);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn empty_extra_leaves_body_unchanged() {
        let body = json!({"model": "qwen-plus", "messages": [1]});
        let merged = merge_chat_request(&body, "  ").unwrap();
        assert_eq!(merged, body);
    }

    #[test]
    fn extra_fields_override_and_deep_merge() {
        let body = json!({
            "model": "qwen-plus",
            "enable_thinking": false,
            "chat_template_kwargs": {"enable_thinking": false}
        });
        let merged = merge_chat_request(
            &body,
            r#"{"enable_thinking": true, "thinking_budget": 0, "chat_template_kwargs": {"foo": 1}}"#,
        )
        .unwrap();
        assert_eq!(merged["enable_thinking"], true);
        assert_eq!(merged["thinking_budget"], 0);
        assert_eq!(merged["chat_template_kwargs"]["enable_thinking"], false);
        assert_eq!(merged["chat_template_kwargs"]["foo"], 1);
    }

    #[test]
    fn reserved_keys_cannot_replace_messages_or_stream() {
        let body = json!({
            "messages": [{"role": "user"}],
            "stream": true,
            "stream_options": {"include_usage": true}
        });
        let merged = merge_chat_request(
            &body,
            r#"{"messages": [], "stream": false, "stream_options": null, "temperature": 0.2}"#,
        )
        .unwrap();
        assert_eq!(merged["messages"].as_array().unwrap().len(), 1);
        assert_eq!(merged["stream"], true);
        assert_eq!(merged["stream_options"]["include_usage"], true);
        assert_eq!(merged["temperature"], 0.2);
    }

    #[test]
    fn non_object_extra_is_an_error() {
        let body = json!({"model": "qwen-plus"});
        let err = merge_chat_request(&body, "[1, 2]").unwrap_err();
        match err {
            LumenError::SerializationError { message, .. } => {
                assert!(message.contains("JSON 对象"), "{message}");
            }
            other => panic!("unexpected error: {other}"),
        }
    }
}
