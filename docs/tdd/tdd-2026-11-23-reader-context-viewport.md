---
version: v1.0.35
date: 2026-11-23
prd: prd/prd-2026-11-23-reader-context-viewport.md
predecessor:
  - tdd/tdd-2026-03-22.md
  - tdd/tdd-2026-07-10-note-overlay-optimization.md
  - tdd/tdd-2026-08-05-viewport-restore-overlay-drag.md
  - tdd/tdd-2026-08-21-llm-extra-config.md
  - tdd/tdd-2026-09-01-native-translation-popover.md
successor:
  - tdd/tdd-2026-11-24-note-overlay-update.md
  - tdd/tdd-2026-11-25-notes-context-grammar.md
---

# LumenPDF — 划线入口、选词语境与阅读位置 TDD

## 1. 技术结论

笔记按钮按「一次连续划线」聚合，不再按 PDF 标注条数各放一个。选词语境优先使用页面行几何；`PDFPage.string` 的字符范围只作补充。阅读位置以最近一次稳定视口为准，关闭过程中往前跳的采集不能覆盖它。Extra Config 的当前行高亮要加上文本容器原点。目录高亮由纯函数选出唯一章节。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `PDFHighlightAnnotationFactory.makeUnderline` | 一次划线的全部行写入同一个 underline 标注的 QuadPoints。 |
| `NoteAnchorGrouping` | 把紧挨着的旧划线行合成一组，段落间隔则分开。 |
| `NoteAnchorCatalog` | 自由划线先分组，再各生成一个笔记入口。后续修订：空笔记和自由划线不再生成入口，跨页同一划线只留一个按钮，见 [tdd-2026-11-24-note-overlay-update.md](tdd-2026-11-24-note-overlay-update.md)。 |
| `ReadingSentenceContext` | 从可见行抽出包含选中词的句子；句子过短或从该词开头时带上相邻句。 |
| `PDFSelectionMarkupGeometry.contextSentence` | 从选区所在页收集行，交给上面的纯函数。 |
| `ReadingViewportCommit` | 决定新的视口采集能否替换已记住的位置；恢复页码优先用锚点页。 |
| `PDFKitView.Coordinator` | 滚动时立刻记住稳定视口；关闭、退出、拆掉视图时写出这份位置，而不是关闭瞬间的回跳。 |
| `JSONEditorLineHighlight` | 当前行矩形加上 `textContainerOrigin`，与文字和行号对齐。 |
| `ReaderViewportGeometry.outlineFocusPoint` | 目录用的阅读线：可见区域从上往下三分之一，与恢复用的顶边锚点分开。 |
| `OutlineDestinationPosition` / `OutlineActiveSection` | 书签起点与阅读线用同一套 PDF 页坐标比较，选已经到达的最后一条。 |

SwiftUI 视图仍不调用 `BridgeService`。本次不改 Rust、数据库或 UniFFI。

## 3. 关键规则

### 3.1 划线入口

新建下划线走 `makeUnderline(lineRects:)`，一笔一行数组对应一个标注。`NoteAnchorGrouping.sameStroke` 认为两行属于同一次划线的条件是：上方行的底边到下方行的顶边不超过较高行高的 0.85 倍，并且水平方向重叠，或左边缘相距不超过 28pt。目录和笔记按钮都消费分组后的矩形。

### 3.2 选词语境

`ReadingSentenceContext.extract` 按 PDF 纵坐标从上到下排列行，从与选区相交的行向两侧扩展，直到行距超过约一行。拼成段落后按句号切句。包含选中词的那一句如果词数不超过选中词数加 2，或句子的第一个词就是选中词，则带上前一句；过短时再带上后一句。结果超过 800 字时以选中词为中心截断。

`PDFPage.string` 路径仍保留。字符范围抽出的句子若比可见行结果更「瘦」（几乎只剩选中词），使用更完整的那一份。标题过滤如果把语境滤成只剩该词，同样退回过滤前的文本。后续修订：标题过滤不得删掉同一句的句首词，见 [tdd-2026-11-25-notes-context-grammar.md](tdd-2026-11-25-notes-context-grammar.md)。

### 3.3 阅读位置

`captureViewportState` 的 `pageIndex` 使用锚点页，不再单独相信可能滞后的 `PDFView.currentPage`。滚动中的视口立刻写入协调器的 `lastViewportState`，磁盘写入仍短延迟。

`ReadingViewportCommit.accepting`：

- 没有旧位置时接受新采集。
- 当前事件是滚轮、缩放、滑动、按键或滚动条拖动时，接受新采集，包括用户主动往回翻。
- 否则，新页码比旧页码至少小 2 页，或同一页锚点纵坐标跳动超过 240pt，保留旧位置。
- 其余前进、或滚动结束后 1 秒内的单页回移，接受新采集。

关闭、退出和视图拆除调用 `publishCommittedPage`。视图已经塌陷时采集返回空，已记住的位置仍然写出。恢复时 `restorePageIndex` 先取锚点页，再取视口页码，最后才用 SQLite 页码。

### 3.4 当前行高亮

`lineFragmentRect` 在文本容器坐标系里。绘制时加上 `textContainerOrigin`，高亮条才和字形、行号重合。光标移动时重绘这一条。

### 3.5 目录

任意 PDF 都用同一条规则，不按某本书的标题或页码分支。

书签起点是 `PDFDestination` 的页码和页坐标 y。`/XYZ` 用目的点的 y。没有垂直目标时 PDFKit 给出零点，这时起点改为该页 `cropBox.maxY`，也就是页首。目录比较的阅读位置不是视口顶边：顶边经常还停在上一节的末行。`outlineFocusPoint` 取可见区域从上往下三分之一处，再换成该点所在页的页坐标，由 `PDFKitView` 写入 `AppState.outlineReadingPosition`。关闭前记住的阅读锚点仍然是顶边，目录这条线不写进恢复数据。

一条书签已经到达：目的页更早，或者与阅读线同一页且起点 y 大于或等于阅读线的 y。已经到达的书签里，页码更大的在后；同一页上 y 更小的在后；页码和 y 都相同则大纲里更后的条目在后。目录行的外观保持浅色底和强调色文字。还没有测到阅读线时，只按页码比较，当前页上的书签都算已经到达。

翻译选区由 `TranslationSelectionEmphasisView` 盖在 PDF 上，每一行一个子视图。填充色是 `PDFHighlightAnnotationFactory.nativeHighlightColor`（预览同款系统黄），图层用 `multiplyBlendMode` 与底下的页面合成，所以白纸变黄、黑字不变。不写阴影，不写入 PDF 标注。点击穿透到 PDF。几何仍是逐行字框略向外扩。关闭浮窗后视图移除。后续修订：临时选区不再共用这支黄色，见 [tdd-2026-11-25-notes-context-grammar.md](tdd-2026-11-25-notes-context-grammar.md)。

## 4. 测试

- `ReadingViewportCommitTests`：关闭回跳不覆盖更新的页；用户主动回翻保留新位置；同一页大幅回跳保留原锚点；恢复页码优先锚点。
- `ReadingSentenceContextTests`：句中单词保留整句；孤立单词带上邻句；远离正文的标题不进入语境。
- `NoteAnchorCatalogTests` / `PDFMarkupAppearanceTests`：连续三行一个入口、一个标注；段落间隔仍是两组。
- `OutlineActiveSectionTests`：阅读线在下一页时选中上一页更低的书签；同一页上仍低于阅读线的书签不高亮；阅读线到达该书签时改选它；无垂直目标的目的点从页首算起。
- `ReaderViewportGeometryTests`：目录阅读线在可见区域从上往下三分之一，翻页坐标方向正确。

界面对齐、真实 PDF 上的笔记按钮和关闭再打开的页码需要在运行中的应用里看。单元测试不覆盖 PDFKit 关窗时的实际回跳。
