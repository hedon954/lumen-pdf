---
version: unreleased
date: 2026-09-01
prd: prd/prd-2026-09-01-native-translation-popover.md
predecessor:
  - tdd/tdd-2026-03-30-optimization.md
  - tdd/tdd-2026-05-06-v104.md
  - tdd/tdd-2026-07-16-reading-ai-input-selection.md
  - tdd/tdd-2026-08-09-selection-overlay-placement.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
  - tdd/tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
---

# LumenPDF — 原生翻译预览样式 TDD

## 1. 技术结论

继续使用根层 `ReadingOverlayWindow` 承载翻译浮窗，不新增 AppKit 弹出层。翻译浮窗打开 `showsAnchorPointer`，定位顺序改为左、右、上、下。卡片仍用系统 `RoundedRectangle`；箭头是单独的三角，画在朝向选区的 padding 里，不把整张卡片 clip 成自定义 Path（那会抠掉四个角）。流式在 JSON 闭合或 `finish_reason` / `[DONE]` 时结束读取；词典音标查询限时 1.5 秒。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `TranslationPopoverPresentation` | 语言标签、TTS 语言码、原文展示文本、强调色译文 / 拷贝文本。无 I/O。 |
| `TranslationPopoverLanguagePair` / `TranslationPopoverDetailSection` | 原生预览行与细节段的排版。 |
| `TranslationBubble` | 组装 overlay、失败卡、拆解、footer 动作；不直接调用 `BridgeService`。 |
| `AudioService` | 按传入的 `languageCode` 朗读原文或译文。 |
| `ReadingOverlayWindow` | 材质、圆角、拖动、缩放、首次定位锁定；翻译使用气泡外形与 Look Up 定位顺序。 |
| `ReadingOverlayPointerGeometry` / `ReadingOverlayArrowShape` | 箭头尺寸、padding、沿边缘对准选区；三角只画在指向边。 |
| `stream_has_terminal_payload` | JSON 已闭合、`finish_reason` 或 `[DONE]` 时停止 SSE。 |
| `TranslationDomainService` | 词典音标 lookup 1.5 秒超时。 |

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
- 卡片用系统圆角；箭头单独画在指向边的 padding 里。不要用自定义 Path clip 整张卡片。
- 强调色译文非空后隐藏转圈；footer 仍等 `isLoading == false` 再出现，避免保存半成品。
- SSE 在根 JSON 闭合后停止，即使网关继续推思考 token。
- 音标请求与 LLM 并行，但 `tokio::time::timeout(1.5s)`，超时保留 LLM 音标。

## 4. 验证

- Swift：`TranslationPopoverPresentationTests` 覆盖语言标签、单词 / 句子强调色译文选择、拷贝载荷和转圈消失条件；`ReadingOverlayPlacementTests` 覆盖 Look Up 左侧优先、箭头占位和沿边缘对准选区。
- Rust：`json_root_object_closed` / `stream_has_terminal_payload`；词典音标超时后保留 LLM 音标。`cargo test`。
- 运行时（需 macOS app）：单词浮窗以一体气泡箭头指向选区；译文写出后不再转圈；保存与 AI 解释仍可用。本环境无法启动 macOS 应用，视觉与交互验收未在运行中的 app 完成。
