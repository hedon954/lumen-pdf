---
version: unreleased
date: 2026-09-01
prd: prd/prd-2026-09-01-native-translation-popover.md
predecessor:
  - tdd/tdd-2026-03-30-optimization.md
  - tdd/tdd-2026-05-06-v104.md
  - tdd/tdd-2026-07-16-reading-ai-input-selection.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
  - tdd/tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
---

# LumenPDF — 原生翻译预览样式 TDD

## 1. 技术结论

继续使用根层 `ReadingOverlayWindow` 承载翻译浮窗，不新增 AppKit 弹出层。视觉对齐放在内容编排：把原文 / 译文收成系统翻译预览式的语言对，其余字段作为同一滚动区里的细节段。字段选择、流式更新和保存回调仍由现有 `TranslationBubbleRequest` / `TranslationOverlayModel` 驱动。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `TranslationPopoverPresentation` | 语言标签、TTS 语言码、原文展示文本、强调色译文 / 拷贝文本。无 I/O。 |
| `TranslationPopoverLanguagePair` / `PopoverDetailSection` | 原生预览行与细节段的排版。 |
| `TranslationBubble` | 组装 overlay、失败卡、拆解、footer 动作；不直接调用 `BridgeService`。 |
| `AudioService` | 按传入的 `languageCode` 朗读原文或译文。 |
| `ReadingOverlayWindow` | 材质、圆角、拖动、缩放、首次定位锁定；本迭代不改定位策略。 |

## 3. 内容映射

```text
单词
  原文对 ← result.word ?? request.word，音标在原文下
  译文对 ← contextTranslation
  细节   ← 语境解释、词源、通用释义、原文语境 + contextSentenceTranslation

句子
  原文对 ← request.word
  译文对 ← contextSentenceTranslation，空则 contextTranslation
  细节   ← 解释、拆解
```

- 语言标签来自 `@AppStorage("target_language")`，默认「简体中文」→「中文 (普通话，简体)」。
- 「拷贝译文」写入 `NSPasteboard` 的强调色译文，不复制解释或拆解。
- 加载中若尚无 `result`，仍渲染原文对，译文对显示进度。

## 4. 验证

- Swift：`TranslationPopoverPresentationTests` 覆盖语言标签、单词 / 句子强调色译文选择和拷贝载荷。
- 不改 Rust 翻译链路；`cargo test` 作为回归。
- 运行时（需 macOS app）：单词与句子成功态、流式、兜底「基础翻译」、失败重试、拷贝、原文 / 译文朗读、保存与 AI 解释、浅色 / 深色、拖动与点外关闭。本环境无法启动 macOS 应用，视觉与交互验收未在运行中的 app 完成。
