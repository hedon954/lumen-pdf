---
version: v1.0.25
date: 2026-08-20
tdd: tdd/tdd-2026-08-20-library-cover-translation-retry.md
predecessor:
  - prd/prd-2026-08-19-markup-diagnostics.md
  - prd/prd-2026-07-10-note-overlay-optimization.md
successor:
  - prd/prd-2026-08-20-note-autosave-overlay-stability.md
---

# LumenPDF — 文库封面与翻译重新生成 PRD

## 1. 产品结论

v1.0.25 让已打开的 PDF 更容易辨认，并对不满意或失败的翻译提供一键重新生成。

## 2. 功能需求

### F1 — 文库封面

- 「已打开的文件」列表为每个 PDF 显示首页封面缩略图。
- 文件名和阅读进度仍显示在封面右侧。
- 缩略图失败时退回占位，不得挡住打开文件。

### F2 — 翻译刷新

- 翻译浮窗在成功或失败后提供刷新按钮。
- 失败：重试当前请求。
- 成功：跳过本地缓存，重新生成解释。
- 重新生成期间保持同一浮窗会话，不新开一张卡。

## 3. 非目标

- 不生成除首页以外的多页预览。
- 不改变缓存写入规则：只有 LLM 成功才写入；刷新只是跳过读取。

## 4. 验收标准

1. 文库列表能通过封面区分不同 PDF。
2. 翻译成功后点刷新，内容更新且不沿用旧缓存。
3. 翻译失败后点刷新，会再次请求并可用成功结果覆盖失败。
