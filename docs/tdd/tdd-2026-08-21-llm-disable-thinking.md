---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-llm-disable-thinking.md
predecessor:
  - tdd/tdd-2026-03-22.md
  - tdd/tdd-2026-07-16-llm-configuration-discovery.md
  - tdd/tdd-2026-08-20-llm-settings-persistence.md
related:
  - tdd/tdd-2026-08-21-workspace-search.md
---

# LumenPDF — LLM 关闭 thinking TDD

## 1. 技术结论

所有 `POST /chat/completions` 都从 `LlmTranslator::chat_request` 构造，统一带上关闭 thinking 的字段。这是基础设施层的请求形状，不是 domain 规则。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `LlmTranslator::chat_request` | 单词 / 句子 / 导读 / 图片探测共用的请求构造。 |
| `ChatRequest` | 序列化 `enable_thinking: false`、`chat_template_kwargs.enable_thinking: false`、`thinking.type: disabled`。 |
| `send_chat_request` / `stream_completion` | 400 且报未知字段时，去掉这些扩展（以及 `stream_options`）再试一次。 |

三个字段覆盖常见网关：百炼 / 硅基流动用 `enable_thinking`；vLLM / SGLang 用 `chat_template_kwargs`；智谱 / DeepSeek 用 `thinking.type`。

## 3. 请求形状

```text
{
  "model": "...",
  "messages": [...],
  "enable_thinking": false,
  "chat_template_kwargs": { "enable_thinking": false },
  "thinking": { "type": "disabled" }
}
```

`enable_thinking: false` 必须写出，不能因为是 false 而省略。`GET /models` 不带这些字段。

## 4. 验证

`llm_translator` 单测：

- 单词、句子、导读请求都带上述三个关闭字段
- `without_vendor_extensions` 后这些字段不再出现
- 400 + unrecognized `enable_thinking` 视为可重试

本环境无法对真实百炼/OpenAI 网关做联调。运行时须确认思考模型不再先推理再回答。
