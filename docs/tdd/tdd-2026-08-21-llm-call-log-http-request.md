---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-llm-call-log-http-request.md
predecessor:
  - tdd/tdd-2026-08-14-ai-settings-notes.md
  - tdd/tdd-2026-08-15-settings-usage-overlay.md
  - tdd/tdd-2026-08-19-markup-diagnostics.md
  - tdd/tdd-2026-08-21-llm-extra-config.md
---

# LumenPDF — 调用日志完整 HTTP 请求 TDD

## 1. 技术结论

完整 HTTP dump 在 Rust 发出 `/chat/completions` 时格式化，经 `TranslationResult.http_request` 或 `LumenError` 带回 Swift。调用日志只在 `finish` / `fail` 写入。缓存 JSON 使用 `serde(skip)`，避免把请求体和密钥痕迹写进 SQLite。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `http_request_log.rs` | 脱敏 `data:` URL、把 `messages` 挪到 JSON 末尾、写 `Authorization: Bearer ***`。 |
| `LlmTranslator` | `send_chat_request` / `stream_completion` 用实际发出的 payload（含 400 重试后的那一版）生成 dump。 |
| `TranslationResult.http_request` | UniFFI 运行时字段；不进翻译缓存。 |
| `LumenError::LlmApiError` / `SerializationError` | 失败路径携带同一 dump，供兜底结果和 `failAudit`。 |
| `LLMCallLogStore` | `httpRequest` 可缺省解码旧日志；单独截断上限 48000 字符。 |
| `LLMCallLogDetail` | 「完整 HTTP 请求」默认预览，按需展开。 |

## 3. 关键行为

- dump 不含 API Key。Bearer 头恒为 `***`。
- 400 因未知可选字段而重试时，日志记录重试后真正发出的 body。
- 流式 `on_progress` 部分结果不带 dump。
- `complete_llm_result` 写入缓存前清空 `http_request`；`complete_fallback_result` / `complete_failure_result` 保留 LLM dump。
- 旧 `llm-call-log.json` 没有 `httpRequest` 时按空字符串处理，整文件不得解码失败。

## 4. 验证

- `http_request_log`：Extra Config 出现在 `messages` 之前；data URL 被省略；全文无真实 Bearer
- `translation::entity`：缓存序列化不含 `http_request`
- `translation::service`：LLM 失败走兜底时 dump 仍在
- `LLMCallLogStoreTests`：finish 后重载保留 dump；去掉该字段的旧文件仍能打开

本环境无法打开 macOS 调用日志页。运行时须确认展开后的 JSON 与设置里 Extra Config 一致，且缓存命中条目写明未发 HTTP。
