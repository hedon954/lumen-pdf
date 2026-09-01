---
version: v1.0.31
date: 2026-09-01
prd: prd/prd-2026-09-01-native-translation-popover.md
predecessor:
  - tdd/tdd-2026-03-30-optimization.md
  - tdd/tdd-2026-05-06-v104.md
  - tdd/tdd-2026-07-10-note-overlay-optimization.md
  - tdd/tdd-2026-07-16-reading-ai-input-selection.md
  - tdd/tdd-2026-08-05-viewport-restore-overlay-drag.md
  - tdd/tdd-2026-08-09-selection-overlay-placement.md
  - tdd/tdd-2026-08-15-settings-usage-overlay.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
  - tdd/tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
---

# LumenPDF — Look Up 式翻译浮窗 TDD

## 1. 技术结论

翻译内容与浮层状态仍由 SwiftUI 和 `TranslationOverlayModel` 持有，展示复用主阅读层中的 `ReadingOverlayWindow`。该容器负责 Look Up 式圆角、阴影、选区箭头、点外关闭、窗口内拖拽、自动高度和边界约束；`opaqueChrome` 使用完全不透明的系统文本背景，不使用会透出 PDF 的材质背景。`PDFKitView.Coordinator` 在翻译请求存在期间重建真实 `PDFSelection`，并用不参与持久化、不可命中的 `NSView` 按逐行几何绘制黄色强调和轻阴影；关闭、换文档和 teardown 都确定性清理。浮窗宽度、初始内容高度、实测扩展、滚动和 80% 高度上限复用 `main` 参数。流式在 JSON 闭合或 `finish_reason` / `[DONE]` 时结束读取；词典音标查询限时 1.5 秒。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `TranslationPopoverPresentation` | 目标语言标签、TTS 语言码、原文展示文本、强调色译文 / 拷贝文本。无 I/O。 |
| `TranslationPopoverLanguagePair` / `TranslationPopoverDetailSection` | 原生预览行与细节段的排版。 |
| `TranslationBubble` | 组装 `ReadingOverlayWindow`、四按钮 header、可滚动内容、失败卡、拆解和 footer 动作；不直接调用 `BridgeService`。 |
| `ContentView` | 根层 GeometryReader 把 `selectionAnchorRect` 转成 overlay 局部，并直接展示 `TranslationBubble`。 |
| `ReaderRootCoordinateSpace.localRect` | 扣除 overlay frame 原点；与操作栏共用。 |
| `TranslationPopoverGeometry` | 与 `main` 一致的宽度和初始高度参数。无 I/O。 |
| `TranslationHeaderControlMetrics` | 统一四个 header 控件的数量、尺寸与间距。 |
| `AudioService` | 按传入的 `languageCode` 朗读原文或译文。 |
| `ReadingOverlayWindow` / `ReadingOverlayMoveHandle` | 锚定箭头、自动布局、实色 chrome、点外关闭、拖拽与边界约束。 |
| `PDFKitView.Coordinator` / `TranslationSelectionEmphasisView` | 保留真实 currentSelection；按 page markup 绘制临时黄色强调与阴影；滚动、缩放、关闭和 teardown 时清理。 |
| `stream_has_terminal_payload` | JSON 已闭合、`finish_reason` 或 `[DONE]` 时停止 SSE。 |
| `TranslationDomainService` | 词典音标 lookup 1.5 秒超时。 |

## 3. 内容映射

```text
单词
  header ← result.word ?? request.word + 同行音标；右侧是拖拽 / 播放 / 刷新 / 关闭
  译文对 ← contextTranslation
  细节   ← 语境解释、词源、通用释义、原文语境 + contextSentenceTranslation

句子
  header ← request.word；右侧是拖拽 / 播放 / 刷新 / 关闭
  译文对 ← contextSentenceTranslation，空则 contextTranslation
  细节   ← 解释、拆解
```

- header 不渲染原文语言标签；目标语言标签来自 `@AppStorage("target_language")`，默认「简体中文」→「中文 (普通话，简体)」。
- 「拷贝译文」写入 `NSPasteboard` 的强调色译文，不复制解释或拆解。
- 加载中若尚无 `result`，仍渲染原文对，译文对显示进度。
- `ContentView` 的 GeometryReader 必须调用 `ReaderRootCoordinateSpace.localRect`，再把最小 1pt 的选区矩形交给 `ReadingOverlayWindow`；容器根据可用空间选择左右、上下位置并绘制指向选区的箭头。
- `TranslationBubble` 的单词 / 句子宽度起点分别是 380 / 560pt，按字符数乘 4.2 扩展，最低 340pt、最高 760pt；初始内容高度分别为 120 / 160pt，失败态 248pt；`ReadingOverlayWindow` 实测内容展开后把整体高度限制为阅读窗口的 80%，超出部分滚动。
- 翻译浮窗配置 `opaqueChrome: true`、`isResizable: false`、`dismissesOnBackgroundTap: true`、`showsAnchorPointer: true`。圆角卡片和箭头都填充 `NSColor.textBackgroundColor`，确保内容 alpha 为 1。
- header 外层使用顶部对齐的 `HStack`：左侧原文允许垂直扩展，句子按剩余宽度自然换行且不设 `lineLimit`；单词与音标仍在首行基线对齐的内层 `HStack` 同行显示。右侧固定为拖拽、播放、刷新、关闭四个 28pt 控件，间距 4pt；按钮组固定在右上。刷新在加载态禁用但不移除，避免按钮组跳动。
- `ReadingOverlayMoveHandle` 从 `ReadingOverlayWindow` 的环境闭包接收增量；拖动只更新容器内部的 `customCenter`，并通过现有 clamp 约束在阅读区域内，不在 `TranslationBubble` 或 `ContentView` 创建第二份位置状态。
- `TranslationSelectionEmphasisView` 只读 `TranslationSelectionEmphasis(id, filePath, pageMarkups)`；每条 line rect 水平外扩 1.5pt、垂直外扩 0.75pt，使用 system yellow 和 2.5pt 轻阴影。该 view 不接收鼠标，不创建 `PDFAnnotation`，不会进入标注持久化或 Undo。
- `PDFKitView.Coordinator` 收到 clip-view bounds 或 `PDFViewScaleChanged` 后，若翻译选区仍活跃，先同步清理 `currentSelection` 与强调 view，再在下一主线程循环调用 `onTranslationViewportChanged` 关闭 popover，防止 SwiftUI 更新周期内发布状态并避免箭头停在旧坐标。
- 强调色译文非空后隐藏转圈；footer 仍等 `isLoading == false` 再出现，避免保存半成品。
- SSE 在根 JSON 闭合后停止，即使网关继续推思考 token。
- 音标请求与 LLM 并行，但 `tokio::time::timeout(1.5s)`，超时保留 LLM 音标。

## 4. 验证

- Swift：`TranslationPopoverPresentationTests` 覆盖语言标签、单词 / 句子强调色译文选择、拷贝载荷和转圈消失条件；`TranslationPopoverGeometryTests` 覆盖 `main` 宽高参数、四控件尺寸 / 间距和高亮外扩几何；`ReadingOverlayPlacementTests` 覆盖锚定、指针、拖拽后的边界约束和 80% 上限。
- Rust：`json_root_object_closed` / `stream_has_terminal_payload`；词典音标超时后保留 LLM 音标。`cargo test`。
- 运行时（需 macOS app）：单词与跨行句子均出现黄色轻阴影强调；箭头指向选区；浮窗内容不透出或模糊后方 PDF；单词与音标同行；长句原文完整换行且四按钮保持右上；四按钮等大、同行、小间距、右对齐；拖拽首个按钮确实移动浮窗。浅色/深色、左右边缘、窗口移动/缩放、点内/点外均需实际操作确认。滚动或缩放 PDF 时浮窗与临时强调必须一起关闭。
