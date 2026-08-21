---
version: unreleased
date: 2026-08-21
tdd: tdd/tdd-2026-08-21-llm-call-log-http-request.md
predecessor:
  - prd/prd-2026-08-14-ai-settings-notes.md
  - prd/prd-2026-08-15-settings-usage-overlay.md
  - prd/prd-2026-08-19-markup-diagnostics.md
  - prd/prd-2026-08-21-llm-extra-config.md
---

# LumenPDF — 调用日志完整 HTTP 请求 PRD

## 1. 产品结论

设置里的调用日志可以展开一次真实发出的 `/chat/completions` 请求：方法、地址、脱敏后的请求头，以及合并 Extra Config 之后的 JSON 正文。用来核对 thinking 字段、模型名和提示词，而不是只看用户原文。

## 2. 问题

调用日志原先只记用户输入和模型输出。实际 HTTP 体在 Rust 里拼装，设置页看不到 Extra Config 是否进了请求，排障只能猜。

## 3. 功能需求

### F1 — 展开完整 HTTP 请求

- 单词翻译、整句翻译、选区解释的调用详情中，在「请求内容」和「模型响应」之间提供「完整 HTTP 请求」。
- 默认只显示前几行预览；点击「展开完整请求」后显示全部，可复制。
- 内容为实际发出的那一次请求：`POST` 地址、`Authorization: Bearer ***`、`Content-Type`，以及 pretty-printed JSON 正文。
- JSON 中 Extra Config（含系统默认的关 thinking 字段）可见；`messages` 排在其它字段后面，避免长提示词把 Extra Config 挤出预览。
- 图片 `data:` URL 只保留 MIME 前缀和省略后的字节数，不写 base64。
- 不得出现 API Key 明文。
- 命中本地缓存时说明未发出 HTTP；LLM 失败后走兜底或完全失败时，仍展示那次 LLM 请求。
- 流式生成过程中的中间片段不反复写入完整请求；只在最终成功或失败时记录。
- 内部图片能力探测仍不进入用户调用日志。

## 4. 非目标

- 不记录 HTTP 响应原文（模型输出仍在「模型响应」）。
- 不把完整请求写入翻译缓存。
- 不在日志里提供单独的「重放请求」按钮。

## 5. 验收标准

1. 对百炼发出一次单词翻译后，展开完整 HTTP 请求能看到 `enable_thinking` 与当前 Extra Config 一致，且没有 API Key。
2. 带图的选区解释展开后，看不到图片 base64，只看到省略说明。
3. 同一原文第二次命中缓存时，详情写明未发出 HTTP。
4. LLM 失败并走兜底后，仍能展开那次失败的 LLM 请求。
5. 升级前保存的旧日志文件仍能打开，缺失字段视为没有 HTTP 记录。
