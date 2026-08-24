---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-llm-extra-config.md
predecessor:
  - tdd/tdd-2026-07-16-llm-configuration-discovery.md
  - tdd/tdd-2026-08-20-llm-settings-persistence.md
  - tdd/tdd-2026-08-21-llm-disable-thinking.md
successor:
  - tdd/tdd-2026-08-24-codebase-simplification.md
related:
  - tdd/tdd-2026-08-21-llm-call-log-http-request.md
---

# LumenPDF — LLM Extra Config 与 API Key 入口 TDD

## 1. 技术结论

关闭 thinking 的字段来自 Extra Config，不再写入 `ChatRequest`。空 Extra Config 在发送前由 `resolve_extra_config` / `LLMSettingsStore.effectiveExtraConfig` 填入 `ThinkingDisableKind` 对应 JSON；已保存的对象（含 `{}`）原样使用。Swift 设置页用同一套 host/模型规则显示默认值。后续修订：默认 JSON 只在 Rust `thinking_control` 计算，经 UniFFI `default_extra_config` 给设置页展示，Swift 不再复制 host/模型启发式，见 [tdd-2026-08-24-codebase-simplification.md](tdd-2026-08-24-codebase-simplification.md)。`JSONEditorView` 做语法着色与回车缩进；`LLMExtraConfig.prettyPrinted` 只由工具栏画笔触发。不追加 `/no_think`。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `LLMSettingsPage` | 官方申请链接放在表单外右下角（`safeAreaInset`），不插入表单行。 |
| `LLMConfigurationSection` | Extra Config 编辑器放在模型字段下方，与服务商同一节。 |
| `LLMThinkingExtraConfig` | Swift 侧同一套默认 JSON，供设置页展示。后续修订：改为对 UniFFI `default_extra_config` 做 pretty-print，不再实现 host/模型规则，见 [tdd-2026-08-24-codebase-simplification.md](tdd-2026-08-24-codebase-simplification.md)。 |
| `LLMSettingsStore` | `llm_extra_config_by_base_url` 存用户值；空则 `effectiveExtraConfig` 返回默认。 |
| `LLMExtraConfig` | 校验、手动格式化、JSON 相等比较。 |
| `JSONAutoIndenter` / `JSONEditorView` | 回车缩进、闭合括号出缩进、行号、语法着色；失焦不重排。 |
| `extra_config.rs` | 深度合并；忽略 `messages` / `stream` / `stream_options`。 |
| `LlmTranslator::chat_json` | 空 Extra Config 先 resolve 再合并。 |

## 3. 默认 Extra Config

| 判定 | Extra Config |
| --- | --- |
| host 含 `dashscope` / `bailian` / `alibaba-inc.com` / `aliyuncs.com` / `idealab` / `siliconflow` | `{"enable_thinking": false}` |
| host 含 `openrouter.ai` | `{"reasoning": {"enabled": false}}` |
| DeepSeek / 智谱 / 火山 | `{"thinking": {"type": "disabled"}}` |
| OpenAI / Gemini | 空 |
| 其它 URL + Qwen 系 | `{"chat_template_kwargs": {"enable_thinking": false}}` |
| 其它 URL + GLM / DeepSeek 模型名 | `{"thinking": {"type": "disabled"}}` |
| 其它 | 空 |

空字符串 = 未修改 = 用上表。`{}` = 用户关掉默认字段。400 重试只剥 `stream_options`，然后仍合并 Extra Config（含默认或用户值）。

## 4. 验证

- `thinking_control`：各服务商默认 JSON；空 resolve 到默认；`{}` 与用户 JSON 原样保留
- `llm_translator`：空 Extra Config 的百炼/IdeaLab 请求带 `enable_thinking: false`，消息无 `/no_think`
- `LLMThinkingExtraConfig` / `LLMSettingsStore`：未修改用默认，已保存用用户值。后续修订：默认值断言只留在 `thinking_control`；Swift 启发式测试删除，见 [tdd-2026-08-24-codebase-simplification.md](tdd-2026-08-24-codebase-simplification.md)。
- `JSONSyntaxHighlighter`：键、字符串、数字、关键字着色
- `JSONAutoIndenter`：`{|}` 回车插入缩进空行；字符串里的括号不影响层级
- `LLMExtraConfig`：手动格式化、非法 JSON / 数组 / `messages` 不能过校验

本环境无法运行 macOS 设置页。运行时须确认 Extra Config 回车自动缩进、失焦不整段重排、画笔才格式化，官方 API Key 链接在表单外右下角，以及保存后的请求体与编辑器内容一致。
