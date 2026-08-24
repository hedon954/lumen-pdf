---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-llm-json-repair.md
related:
  - tdd/tdd-2026-08-21-workspace-search.md
---

# LumenPDF — LLM JSON 修复 TDD

## 1. 技术结论

使用现成的 `jsonrepair-rs`（Jos de Jong `jsonrepair` 的 Rust 移植，与 Python `json_repair` 同类），不要再只靠手写剥围栏。所有模型 JSON 的最终反序列化都经 `parse_model_json`。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `model_json.rs` | `parse_model_json`：先严格 serde，失败则 `jsonrepair` 再解析；若修成数组则取第一个 object。 |
| `streaming_json_view` | 流式抽取前去掉围栏和前缀，从第一个 `{` 起扫描；**不** jsonrepair，以免半成品被提前闭合。 |
| `LlmTranslator` 单词/句子路径 | 唯一调用点。导读 Markdown 不走这里。 |

## 3. 解析顺序

```text
空字符串 → 空响应错误
serde_json 直接成功 → 返回
jsonrepair(raw) → serde；若结果是数组则取第一个 object
仍失败 → 保留旧的剥围栏 / 取 `{...}` 回退
```

流式增量抽取走 `streaming_json_view`，等字段自己闭合；流结束后的权威结果才 jsonrepair。

## 4. 验证

`model_json` 单测：

- ` ```json ` 围栏
- 围栏外还有一句废话
- 尾逗号 + 单引号
- Python `None`
- 缺少最后一个 `}`
- 空响应仍报空
- 流式 view 遇到未写完的对象时仍保持未闭合

本环境未对真实模型联调。运行时须确认原先因围栏失败的翻译能出结果。
