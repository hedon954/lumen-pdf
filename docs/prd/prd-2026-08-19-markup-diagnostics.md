---
version: v1.0.24
date: 2026-08-19
tdd: tdd/tdd-2026-08-19-markup-diagnostics.md
predecessor:
  - prd/prd-2026-08-15-settings-usage-overlay.md
  - prd/prd-2026-07-16-reading-ai-input-selection.md
successor:
  - prd/prd-2026-08-20-library-cover-translation-retry.md
  - prd/prd-2026-08-21-selection-settings-feedback.md
  - prd/prd-2026-08-21-markup-interval-merge.md
  - prd/prd-2026-08-21-llm-call-log-http-request.md
  - prd/prd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
---

# LumenPDF — 跨页划线与失败诊断 PRD

## 1. 产品结论

v1.0.24 让跨页选区的划线/高亮落在每一页真正的正文上，并把 LLM 失败原因说清楚。AI 导读必须等上一条回复结束后才能追问。设置窗口可拖边缩放并记住大小。

## 2. 功能需求

### F1 — 跨页划线

- 跨页选区为选中的每一页分别落笔。
- 后续修订：逐页落笔同样适用于手写笔记、句子翻译保存和 AI 解释保存，且几何必须随笔记持久化，见 [prd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md](prd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md)。
- 页眉页脚按相邻页在相近位置重复出现的文字识别，页码允许递增。
- 不得仅因某行靠近页顶就丢掉正文。后续修订：同页小节标题若未被高亮、且其词组已出现在正文中，也不得进入翻译原文，见 [prd-2026-08-21-selection-settings-feedback.md](prd-2026-08-21-selection-settings-feedback.md)。

### F2 — 失败诊断

- LLM 空响应不能只显示 JSON `EOF`。
- 需区分空 body、流式协议不匹配、模型未真正生成，并引导到「设置 → 调用日志」查看原始响应。后续修订：同一详情也可展开实际发出的完整 HTTP 请求，见 [prd-2026-08-21-llm-call-log-http-request.md](prd-2026-08-21-llm-call-log-http-request.md)。
- PDF 文本层同一句话叠很多遍时，发给模型和写入日志前折叠成一句。

### F3 — 导追问串行

- 必须等上一条回复完成（成功或失败）才能继续发送。
- 空回复视为失败，避免连发没有回答。

### F4 — 设置窗口

- 支持拖动边角缩放，最小约 860×600，记住上次大小。

### F5 — 调用日志性能

- 列表减少重复日期格式化造成的卡顿；超长请求/响应先截断，需要时再展开。

## 3. 验收标准

1. 跨两页拖选一段落后，两页都有对应划线，且页码行不被当成正文划掉（除非用户真的选了它）。
2. 制造一次空响应后，气泡/导读给出可读原因而不是 `EOF`。
3. 上一条导读还在生成时，发送按钮不可用。
4. 设置窗口放大后关闭再开，尺寸保持。
