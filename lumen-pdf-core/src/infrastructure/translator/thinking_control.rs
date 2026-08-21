//! Built-in Extra Config that disables thinking for a given OpenAI-compatible
//! provider. The JSON is shown in Settings; an empty Extra Config means "use
//! this default", while a user-supplied object (including `{}`) replaces it.

use serde_json::{json, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThinkingDisableKind {
    None,
    /// DashScope / SiliconFlow / Alibaba OpenAI-compatible: `enable_thinking`.
    EnableThinking,
    /// vLLM / SGLang chat templates: `chat_template_kwargs.enable_thinking`.
    ChatTemplateKwargs,
    /// DeepSeek / GLM: `thinking: { "type": "disabled" }`.
    ThinkingType,
    /// OpenRouter: `reasoning: { "enabled": false }`.
    OpenRouterReasoning,
}

impl ThinkingDisableKind {
    pub fn for_endpoint(base_url: &str, model: &str) -> Self {
        let host = host_of(base_url);
        let qwen = is_qwen_family(model);

        if is_openai_host(&host) || is_gemini_host(&host) {
            return Self::None;
        }
        if is_dashscope_host(&host) || is_siliconflow_host(&host) {
            return Self::EnableThinking;
        }
        if is_openrouter_host(&host) {
            return Self::OpenRouterReasoning;
        }
        if is_zhipu_host(&host) || is_deepseek_host(&host) || is_volcengine_host(&host) {
            return Self::ThinkingType;
        }
        if qwen {
            return Self::ChatTemplateKwargs;
        }
        if is_glm_family(model) || is_deepseek_family(model) {
            return Self::ThinkingType;
        }
        Self::None
    }

    pub fn extra_config_json(self) -> String {
        let value = match self {
            Self::None => return String::new(),
            Self::EnableThinking => json!({"enable_thinking": false}),
            Self::ChatTemplateKwargs => json!({"chat_template_kwargs": {"enable_thinking": false}}),
            Self::ThinkingType => json!({"thinking": {"type": "disabled"}}),
            Self::OpenRouterReasoning => json!({"reasoning": {"enabled": false}}),
        };
        compact_json(&value)
    }
}

/// Empty Extra Config → provider default. Any saved object, including `{}`, is
/// used as-is so the user can turn the built-in fields off.
pub fn resolve_extra_config(raw: &str, base_url: &str, model: &str) -> String {
    if raw.trim().is_empty() {
        ThinkingDisableKind::for_endpoint(base_url, model).extra_config_json()
    } else {
        raw.to_string()
    }
}

pub fn default_extra_config_json(base_url: &str, model: &str) -> String {
    ThinkingDisableKind::for_endpoint(base_url, model).extra_config_json()
}

fn compact_json(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_default()
}

pub fn is_qwen_family(model: &str) -> bool {
    let model = model.to_ascii_lowercase();
    model.contains("qwen") || model.contains("qwq") || model == "coder-model"
}

fn is_glm_family(model: &str) -> bool {
    let model = model.to_ascii_lowercase();
    model.contains("glm") || model.contains("chatglm")
}

fn is_deepseek_family(model: &str) -> bool {
    model.to_ascii_lowercase().contains("deepseek")
}

fn host_of(base_url: &str) -> String {
    let trimmed = base_url.trim();
    let without_scheme = trimmed
        .strip_prefix("https://")
        .or_else(|| trimmed.strip_prefix("http://"))
        .unwrap_or(trimmed);
    without_scheme
        .split('/')
        .next()
        .unwrap_or("")
        .rsplit('@')
        .next()
        .unwrap_or("")
        .split(':')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase()
}

fn is_dashscope_host(host: &str) -> bool {
    host.contains("dashscope")
        || host.contains("bailian")
        || host.contains("alibaba-inc.com")
        || host.contains("aliyuncs.com")
        || host.contains("idealab")
}

fn is_siliconflow_host(host: &str) -> bool {
    host.contains("siliconflow")
}

fn is_openrouter_host(host: &str) -> bool {
    host.contains("openrouter.ai")
}

fn is_zhipu_host(host: &str) -> bool {
    host.contains("bigmodel.cn") || host.contains("api.z.ai") || host.ends_with(".z.ai")
}

fn is_deepseek_host(host: &str) -> bool {
    host == "api.deepseek.com" || host.ends_with(".deepseek.com")
}

fn is_volcengine_host(host: &str) -> bool {
    host.contains("volces.com") || host.contains("volcengine")
}

fn is_openai_host(host: &str) -> bool {
    host == "api.openai.com" || host.ends_with(".openai.com")
}

fn is_gemini_host(host: &str) -> bool {
    host.contains("generativelanguage.googleapis.com")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn dashscope_qwen_default_is_enable_thinking() {
        let extra = default_extra_config_json(
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "qwen-plus",
        );
        assert_eq!(extra, json!({"enable_thinking": false}).to_string());
    }

    #[test]
    fn alibaba_idealab_default_is_enable_thinking() {
        let extra = default_extra_config_json(
            "https://idealab.alibaba-inc.com/api/openai/v1",
            "qwen3.7-flash",
        );
        assert_eq!(extra, json!({"enable_thinking": false}).to_string());
    }

    #[test]
    fn siliconflow_qwen_default_is_enable_thinking() {
        let extra = default_extra_config_json("https://api.siliconflow.cn/v1", "Qwen/Qwen3-8B");
        assert_eq!(extra, json!({"enable_thinking": false}).to_string());
    }

    #[test]
    fn self_hosted_qwen_default_is_chat_template_kwargs() {
        let extra = default_extra_config_json("http://127.0.0.1:8000/v1", "Qwen/Qwen3-8B");
        assert_eq!(
            extra,
            json!({"chat_template_kwargs": {"enable_thinking": false}}).to_string()
        );
    }

    #[test]
    fn openai_default_is_empty() {
        assert!(default_extra_config_json("https://api.openai.com/v1", "gpt-4o").is_empty());
    }

    #[test]
    fn deepseek_default_is_thinking_type() {
        let extra = default_extra_config_json("https://api.deepseek.com/v1", "deepseek-v4-flash");
        assert_eq!(extra, json!({"thinking": {"type": "disabled"}}).to_string());
    }

    #[test]
    fn openrouter_default_is_reasoning() {
        let extra = default_extra_config_json("https://openrouter.ai/api/v1", "qwen/qwen3-32b");
        assert_eq!(extra, json!({"reasoning": {"enabled": false}}).to_string());
    }

    #[test]
    fn custom_glm_default_is_thinking_type() {
        let extra = default_extra_config_json("https://gateway.example/v1", "glm-4.6");
        assert_eq!(extra, json!({"thinking": {"type": "disabled"}}).to_string());
    }

    #[test]
    fn empty_extra_resolves_to_provider_default() {
        let resolved = resolve_extra_config(
            "  ",
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "qwen-plus",
        );
        assert_eq!(resolved, json!({"enable_thinking": false}).to_string());
    }

    #[test]
    fn explicit_empty_object_replaces_default() {
        let resolved = resolve_extra_config(
            "{}",
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "qwen-plus",
        );
        assert_eq!(resolved, "{}");
    }

    #[test]
    fn user_extra_is_kept_as_is() {
        let raw = r#"{"enable_thinking": true, "thinking_budget": 0}"#;
        let resolved = resolve_extra_config(
            raw,
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "qwen-plus",
        );
        assert_eq!(resolved, raw);
    }

    #[test]
    fn unknown_gpt_default_is_empty() {
        assert!(default_extra_config_json("https://gateway.example/v1", "gpt-4o").is_empty());
    }
}
