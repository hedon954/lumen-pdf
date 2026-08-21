//! Choose the thinking-disable fields that a given OpenAI-compatible provider
//! actually honours. Sending every vendor extension at once is worse than
//! sending none: a 400 on an unknown field strips the one field that works.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThinkingDisableKind {
    None,
    /// DashScope / SiliconFlow top-level `enable_thinking: false`.
    EnableThinking,
    /// vLLM / SGLang chat templates: `chat_template_kwargs.enable_thinking`.
    ChatTemplateKwargs,
    /// DeepSeek / GLM: `thinking: { "type": "disabled" }`.
    ThinkingType,
    /// OpenRouter: `reasoning: { "enabled": false }`.
    OpenRouterReasoning,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThinkingDisablePolicy {
    pub kind: ThinkingDisableKind,
    pub append_no_think: bool,
}

impl ThinkingDisablePolicy {
    pub const NONE: Self = Self {
        kind: ThinkingDisableKind::None,
        append_no_think: false,
    };

    pub fn for_endpoint(base_url: &str, model: &str) -> Self {
        let host = host_of(base_url);
        let qwen = is_qwen_family(model);

        if is_openai_host(&host) || is_gemini_host(&host) {
            return Self::NONE;
        }
        if is_dashscope_host(&host) {
            return Self {
                kind: ThinkingDisableKind::EnableThinking,
                append_no_think: qwen,
            };
        }
        if is_siliconflow_host(&host) {
            return Self {
                kind: ThinkingDisableKind::EnableThinking,
                append_no_think: qwen,
            };
        }
        if is_openrouter_host(&host) {
            return Self {
                kind: ThinkingDisableKind::OpenRouterReasoning,
                append_no_think: qwen,
            };
        }
        if is_zhipu_host(&host) || is_deepseek_host(&host) || is_volcengine_host(&host) {
            return Self {
                kind: ThinkingDisableKind::ThinkingType,
                append_no_think: false,
            };
        }
        if qwen {
            return Self {
                kind: ThinkingDisableKind::ChatTemplateKwargs,
                append_no_think: true,
            };
        }
        if is_glm_family(model) || is_deepseek_family(model) {
            return Self {
                kind: ThinkingDisableKind::ThinkingType,
                append_no_think: false,
            };
        }
        Self::NONE
    }
}

pub fn ensure_no_think_suffix(text: &str) -> String {
    let trimmed = text.trim_end();
    if trimmed.ends_with("/no_think") {
        return text.to_string();
    }
    if trimmed.is_empty() {
        return "/no_think".to_string();
    }
    format!("{trimmed}\n/no_think")
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
    host.contains("dashscope") || host.contains("bailian")
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

    #[test]
    fn dashscope_qwen_uses_enable_thinking_and_no_think() {
        let policy = ThinkingDisablePolicy::for_endpoint(
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "qwen-plus",
        );
        assert_eq!(policy.kind, ThinkingDisableKind::EnableThinking);
        assert!(policy.append_no_think);
    }

    #[test]
    fn dashscope_intl_matches_beijing_preset() {
        let policy = ThinkingDisablePolicy::for_endpoint(
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            "qwen3-max",
        );
        assert_eq!(policy.kind, ThinkingDisableKind::EnableThinking);
        assert!(policy.append_no_think);
    }

    #[test]
    fn siliconflow_qwen_uses_enable_thinking_only() {
        let policy =
            ThinkingDisablePolicy::for_endpoint("https://api.siliconflow.cn/v1", "Qwen/Qwen3-8B");
        assert_eq!(policy.kind, ThinkingDisableKind::EnableThinking);
        assert!(policy.append_no_think);
    }

    #[test]
    fn self_hosted_qwen_uses_chat_template_kwargs() {
        let policy =
            ThinkingDisablePolicy::for_endpoint("http://127.0.0.1:8000/v1", "Qwen/Qwen3-8B");
        assert_eq!(policy.kind, ThinkingDisableKind::ChatTemplateKwargs);
        assert!(policy.append_no_think);
    }

    #[test]
    fn openai_sends_no_thinking_fields() {
        let policy = ThinkingDisablePolicy::for_endpoint("https://api.openai.com/v1", "gpt-4o");
        assert_eq!(policy, ThinkingDisablePolicy::NONE);
    }

    #[test]
    fn deepseek_uses_thinking_type() {
        let policy =
            ThinkingDisablePolicy::for_endpoint("https://api.deepseek.com/v1", "deepseek-v4-flash");
        assert_eq!(policy.kind, ThinkingDisableKind::ThinkingType);
        assert!(!policy.append_no_think);
    }

    #[test]
    fn zhipu_uses_thinking_type() {
        let policy =
            ThinkingDisablePolicy::for_endpoint("https://open.bigmodel.cn/api/paas/v4", "glm-4.6");
        assert_eq!(policy.kind, ThinkingDisableKind::ThinkingType);
    }

    #[test]
    fn openrouter_uses_reasoning_flag() {
        let policy =
            ThinkingDisablePolicy::for_endpoint("https://openrouter.ai/api/v1", "qwen/qwen3-32b");
        assert_eq!(policy.kind, ThinkingDisableKind::OpenRouterReasoning);
        assert!(policy.append_no_think);
    }

    #[test]
    fn custom_glm_uses_thinking_type() {
        let policy = ThinkingDisablePolicy::for_endpoint("https://gateway.example/v1", "glm-4.6");
        assert_eq!(policy.kind, ThinkingDisableKind::ThinkingType);
    }

    #[test]
    fn unknown_gpt_sends_nothing() {
        let policy = ThinkingDisablePolicy::for_endpoint("https://gateway.example/v1", "gpt-4o");
        assert_eq!(policy, ThinkingDisablePolicy::NONE);
    }

    #[test]
    fn no_think_suffix_is_idempotent() {
        assert_eq!(ensure_no_think_suffix("hello"), "hello\n/no_think");
        assert_eq!(
            ensure_no_think_suffix("hello\n/no_think"),
            "hello\n/no_think"
        );
    }
}
