//! Format a redacted `/chat/completions` dump for the user-facing call log.

use serde_json::Value;

pub fn format_http_request(url: &str, payload: &Value) -> String {
    let mut body = payload.clone();
    redact_embedded_secrets(&mut body);
    move_messages_last(&mut body);
    let pretty = serde_json::to_string_pretty(&body).unwrap_or_else(|_| body.to_string());
    format!("POST {url}\nAuthorization: Bearer ***\nContent-Type: application/json\n\n{pretty}")
}

fn move_messages_last(body: &mut Value) {
    let Some(obj) = body.as_object_mut() else {
        return;
    };
    if let Some(messages) = obj.remove("messages") {
        obj.insert("messages".to_string(), messages);
    }
}

fn redact_embedded_secrets(value: &mut Value) {
    match value {
        Value::String(text) => {
            if text.starts_with("data:") {
                *text = redact_data_url(text);
            }
        }
        Value::Array(items) => {
            for item in items {
                redact_embedded_secrets(item);
            }
        }
        Value::Object(map) => {
            for nested in map.values_mut() {
                redact_embedded_secrets(nested);
            }
        }
        _ => {}
    }
}

fn redact_data_url(raw: &str) -> String {
    match raw.split_once(',') {
        Some((prefix, data)) => format!("{prefix},<omitted {} bytes>", data.len()),
        None => "<omitted data url>".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn dump_redacts_bearer_and_keeps_extra_config_before_messages() {
        let payload = json!({
            "model": "qwen-plus",
            "messages": [{
                "role": "user",
                "content": "a very long prompt that should not hide extra fields"
            }],
            "enable_thinking": false
        });
        let dump = format_http_request(
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            &payload,
        );
        assert!(dump.starts_with(
            "POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions\n"
        ));
        assert!(dump.contains("Authorization: Bearer ***"));
        assert!(!dump.to_lowercase().contains("bearer sk-"));
        let extra_at = dump.find("\"enable_thinking\"").expect("extra config");
        let messages_at = dump.find("\"messages\"").expect("messages");
        assert!(
            extra_at < messages_at,
            "extra fields must stay visible before messages"
        );
        assert!(dump.contains("\"enable_thinking\": false"));
    }

    #[test]
    fn dump_redacts_image_data_urls() {
        let payload = json!({
            "model": "gpt-4o",
            "messages": [{
                "role": "user",
                "content": [{
                    "type": "image_url",
                    "image_url": {
                        "url": "data:image/png;base64,QUJDREVGR0g="
                    }
                }]
            }]
        });
        let dump = format_http_request("https://api.openai.com/v1/chat/completions", &payload);
        assert!(dump.contains("data:image/png;base64,<omitted 12 bytes>"));
        assert!(!dump.contains("QUJDREVGR0g="));
    }
}
