---
version: unreleased
date: 2026-09-01
prd: prd/prd-2026-09-01-native-translation-popover.md
predecessor:
  - tdd/tdd-2026-03-30-optimization.md
  - tdd/tdd-2026-05-06-v104.md
  - tdd/tdd-2026-07-16-reading-ai-input-selection.md
  - tdd/tdd-2026-08-09-selection-overlay-placement.md
  - tdd/tdd-2026-08-15-settings-usage-overlay.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
  - tdd/tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
---

# LumenPDF — 原生翻译预览样式 TDD

## 1. 技术结论

翻译不再用 `ReadingOverlayWindow` 手绘三角。根层 `GeometryReader` 只放一个全尺寸、不吃点击的定位 `NSView`（`isFlipped == false`），由 `TranslationNativePopover` 对选区调用 `NSPopover.show(relativeTo:of:preferredEdge:)`。系统弹出层负责喙、材质和阴影。`TranslationBubble` 只提供内容，不再自带卡片外壳、拖动手柄或缩放。流式在 JSON 闭合或 `finish_reason` / `[DONE]` 时结束读取；词典音标查询限时 1.5 秒。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `TranslationPopoverPresentation` | 语言标签、TTS 语言码、原文展示文本、强调色译文 / 拷贝文本。无 I/O。 |
| `TranslationPopoverLanguagePair` / `TranslationPopoverDetailSection` | 原生预览行与细节段的排版。 |
| `TranslationBubble` | 原文 / 译文对、失败卡、拆解、footer 动作；不直接调用 `BridgeService`，也不创建窗口。 |
| `TranslationPopoverGeometry` | 内容宽度、首选边、SwiftUI→AppKit 矩形、高度上限。无 I/O。 |
| `TranslationNativePopover` | 拥有一个 `NSPopover` + `NSHostingController`。`behavior = .transient`。在 `dismantleNSView` 和点外关闭的每条路径上关闭并断开 delegate。 |
| `TranslationPopoverLiveContent` | 同一弹出层实例上承接流式 `request` / `isLoading`，避免每次刷新重建 `AnyView` 丢掉内容状态。 |
| `AudioService` | 按传入的 `languageCode` 朗读原文或译文。 |
| `ReadingOverlayWindow` | 只服务笔记和其它阅读浮层；翻译不再打开 `showsAnchorPointer`。 |
| `stream_has_terminal_payload` | JSON 已闭合、`finish_reason` 或 `[DONE]` 时停止 SSE。 |
| `TranslationDomainService` | 词典音标 lookup 1.5 秒超时。 |

## 3. 弹出层生命周期

- 定位视图铺满阅读根层，`hitTest` 返回 `nil`，避免挡住 PDF 和选区操作栏。
- 选区矩形是 SwiftUI 顶原点；展示前用 `viewHeight - maxY` 转成未翻转 AppKit 坐标。
- 首选边：左侧放得下用 `.minX`（弹出层在左、箭头在右），否则 `.maxX`，再否则上 / 下。同一次 `resetID` 锁定该边，流式变高只改 `contentSize`，不换边。
- 点外关闭走 `popoverDidClose` → `onDismiss`。关闭按钮先清 model，再 `dismantle`。关闭后禁止在同一实例上再次 `show`，避免 `layout` 把已关的弹出层拉回来。
- 宿主视图背景透明，让系统弹出层材质透出来；内容不再铺 `regularMaterial` 卡片。
- 这是系统弹出层，不是独立 `NSPanel`。

## 4. 内容映射

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
- 强调色译文非空后隐藏转圈；footer 仍等 `isLoading == false` 再出现，避免保存半成品。
- SSE 在根 JSON 闭合后停止，即使网关继续推思考 token。
- 音标请求与 LLM 并行，但 `tokio::time::timeout(1.5s)`，超时保留 LLM 音标。

## 5. 验证

- Swift：`TranslationPopoverPresentationTests` 覆盖语言标签、单词 / 句子强调色译文选择、拷贝载荷和转圈消失条件；`TranslationNativePopoverTests` 覆盖左侧优先、贴左缘改右侧、坐标翻转和尺寸上限。笔记浮层的 `ReadingOverlayPlacementTests` 保持原默认顺序。
- Rust：`json_root_object_closed` / `stream_has_terminal_payload`；词典音标超时后保留 LLM 音标。`cargo test`。
- 运行时（需 macOS app）：弹出层带系统三角箭头对准选区；浅色 / 深色下能看到材质和阴影；译文写出后不再转圈；保存与 AI 解释仍可用。本环境无法启动 macOS 应用，视觉与交互验收未在运行中的 app 完成。
