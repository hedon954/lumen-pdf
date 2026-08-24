---
version: unreleased
date: 2026-08-24
tdd: tdd/tdd-2026-08-24-codebase-simplification.md
related:
  - prd/prd-2026-08-24-llm-provider-other.md
---

# LumenPDF — 内部去重与结构收缩 PRD

## 1. 产品结论

阅读、翻译、笔记、单词、设置与调用日志的用户可感知行为不变。本迭代删掉平行实现和未走的桥接，让下一次改 Extra Config 默认值、翻译入口或笔记导出只落在一处。

## 2. 问题

复杂度来自必须保持同步的双份规则，以及已经没人走的 API：Extra Config 的 host/模型启发式在 Swift 设置页和 Rust 请求侧各写一份；非流式翻译、按 id 取单词、Rust 笔记导出仍占着 UniFFI。辅助函数复制会让下次改动同时改好几处。

## 3. 用户可感知行为

无变化。打开 PDF、划线笔记、翻译浮窗、设置保存、调用日志状态展示仍按既有规则工作。

- Extra Config 为空时，设置页仍显示当前服务商的关 thinking 默认值；请求仍合并同一套默认。用户写了 JSON 对象（含 `{}`）则按原样使用。
- 单词/句子翻译仍走流式；笔记列表导出仍是 Swift 拼出的 Markdown。

## 4. 非目标

- 不拆 `PDFKitView`、不重写视口恢复。拆文件本身不减少重复，回归面最大。
- 不把 `ReaderPersistence` 并入 `BridgeService`。Views 不得直接调用 Bridge 是项目约束。
- 不取消 application 用例层。那是 DDD 分层约束，不是这次要砍的平行逻辑。
- 不统一 URL 身份（`canonicalBaseURLKey` 与 `LLMEndpointIdentity`）：Keychain 与历史别名语义不同。
- 不改笔记锚点分组 key 与 Inspector 分组 key：那会改变阅读页合并行为。

## 5. 验收标准

- 笔记删除仍会去掉对应下划线；单词删除仍会去掉对应高亮。
- 从笔记列表或单词本跳转到原文，仍先打开对应文档再定位页码。
- Extra Config 为空时，设置页与实际请求使用同一套服务商默认；用户写了 JSON 对象则按原样使用。
- 设置页提示词校验仍同时检查 User Prompt 与 System Prompt。
- 笔记导出内容与导出前一致；翻译仍边生成边显示。
