---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-llm-disable-thinking.md
prev: tdd/tdd-2026-08-20-llm-settings-persistence.md
next: tdd/tdd-2026-08-21-llm-extra-config.md
related:
  - tdd/tdd-2026-08-21-workspace-search.md
---

# LumenPDF — LLM 关闭 thinking TDD

## 1. 技术结论

所有 `POST /chat/completions` 都从 `LlmTranslator::chat_request` 构造。关闭 thinking 的字段由 `ThinkingDisableKind::for_endpoint` 生成 Extra Config 默认 JSON，经 `resolve_extra_config` 合并。这是基础设施层的请求形状，不是 domain 规则。后续修订：字段只出现在 Extra Config，不再写入 `ChatRequest`，也不追加 `/no_think`，见 [tdd-2026-08-21-llm-extra-config.md](tdd-2026-08-21-llm-extra-config.md)。

先前把三条扩展一起发出去，百炼等网关若因未知字段 400，重试会连 `enable_thinking` 一并剥掉，Qwen 就关不掉 thinking。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `thinking_control.rs` | 根据 Base URL host 与模型名生成默认 Extra Config JSON。后续修订：不再追加 `/no_think`，见 [tdd-2026-08-21-llm-extra-config.md](tdd-2026-08-21-llm-extra-config.md)。 |
| `LlmTranslator::chat_request` | 单词 / 句子 / 导读 / 图片探测共用的请求构造。 |
| `send_chat_request` / `stream_completion` | 400 且报未知字段时，去掉这些扩展（以及 `stream_options`）再试一次。 |

## 3. 映射

| 判定 | Extra Config | `/no_think` |
| --- | --- | --- |
| host 含 `dashscope` / `bailian` / `alibaba-inc.com` / `aliyuncs.com` / `idealab` | `enable_thinking: false` | 否（后续修订，见 [tdd-2026-08-21-llm-extra-config.md](tdd-2026-08-21-llm-extra-config.md)） |
| host 含 `siliconflow` | `enable_thinking: false` | 否 |
| host 含 `openrouter.ai` | `reasoning.enabled: false` | 否 |
| DeepSeek / 智谱 / 火山 | `thinking.type: disabled` | 否 |
| OpenAI / Gemini | 不带 | 否 |
| 其它 URL + Qwen 系 | `chat_template_kwargs.enable_thinking: false` | 否 |
| 其它 URL + GLM / DeepSeek 模型名 | `thinking.type: disabled` | 否 |
| 其它 | 不带 | 否 |

Qwen 系：模型名含 `qwen` / `qwq`，或等于 `coder-model`。`enable_thinking: false` 必须写出，不能因为是 false 而省略。`GET /models` 不带这些字段。

## 4. 验证

`thinking_control` / `llm_translator` 单测：

- 百炼 / IdeaLab Qwen：Extra Config 默认只有 `enable_thinking`，消息不含 `/no_think`
- OpenAI：无扩展字段
- 自建 Qwen：只有 `chat_template_kwargs`
- DeepSeek：`thinking.type: disabled`
- OpenRouter：`reasoning.enabled: false`
- `without_vendor_extensions` 后这些字段不再出现
- 400 + unrecognized `enable_thinking` 视为可重试

本环境无法对真实百炼/OpenAI 网关做联调。运行时须确认 Qwen 不再先推理再回答。

后续修订：期望 JSON 的模型输出经 `parse_model_json` / `jsonrepair-rs` 再反序列化，见 [tdd-2026-08-21-llm-json-repair.md](tdd-2026-08-21-llm-json-repair.md)。
