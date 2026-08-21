---
version: unreleased
date: 2026-08-21
tdd: tdd/tdd-2026-08-21-llm-json-repair.md
predecessor:
  - prd/prd-2026-03-22.md
  - prd/prd-2026-05-06-v104.md
  - prd/prd-2026-08-21-llm-disable-thinking.md
related:
  - prd/prd-2026-08-21-workspace-search.md
---

# LumenPDF — LLM JSON 修复 PRD

## 1. 产品结论

凡是要求模型返回 JSON 的调用（单词翻译、整句翻译），解析前必须先做 json repair。模型用 markdown 围栏包一层、漏逗号或少一个括号，不能因此整次翻译失败。

## 2. 问题

模型常把合法 JSON 包进 ` ```json ` 代码块，或带尾逗号、单引号、Python `None`、少写结束括号。原先只剥围栏，碰到其它小错误就会解析失败。

## 3. 功能需求

### F1 — JSON 模式都要 repair

- 单词翻译和整句翻译（流式与非流式）在**最终反序列化**前走 json repair。
- 流式展示只去掉围栏和前缀，不把半成品修成完整 JSON，避免未写完的字段被提前当成完成。
- AI 导读要求的是 Markdown 正文，不做 JSON repair。
- 接口信封（`choices` / SSE 帧）不是模型 JSON，不 repair。

### F2 — 常见失误仍能出结果

至少覆盖：markdown 围栏、前后废话、尾逗号、单引号、Python `True`/`False`/`None`、缺少最后一个 `}`。

## 4. 非目标

- 不自己写一套 JSON 修复器。
- 不把 MyMemory 兜底或本地缓存记录当模型 JSON 来修。

## 5. 验收标准

1. 响应是 ` ```json ` 包着的对象时，单词翻译仍能填入词条。
2. 对象少一个结束括号或带尾逗号时，仍能解析而不是报 JSON 错误。
3. 真正的空响应仍然报空，不编造内容。
