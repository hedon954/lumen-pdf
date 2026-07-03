# LumenPDF — 阅读上下文右栏 TDD

**版本**: v1.0.12 · **日期**: 2026-07-02

对应 PRD：`docs/prd/prd-2026-07-02-reading-context-sidebar.md`

---

## 1. 技术目标

在不改 Rust 数据结构、不新增数据库迁移的前提下，在 SwiftUI 阅读页中加入右侧上下文栏，展示当前 PDF 的单词与笔记，并复用 / 扩展现有 PDFKit 定位能力。

---

## 2. 现有基础

### 2.1 Swift AppState

`AppState` 已维护：

- `selectedDocument`
- `vocabulary`
- `notes`
- `currentPageIndex`
- `refreshVocabulary()`
- `refreshNotes()`

因此右栏可以作为只读视图消费 AppState 数据，不需要直接访问 Rust bridge。

### 2.2 现有跳页能力

`VocabularyListView` 和 `NoteListView` 已通过 `.jumpToPage` 通知实现来源页跳转。PDFReader Coordinator 已监听该通知，并调用 `PDFView.go(to:)`。

### 2.3 现有位置数据

- `VocabularyEntry.selectionBounds` 保存单词选区 bounds。
- `NoteEntry.boundsStr` 保存笔记选区 bounds。
- PDFReader 已使用这些 bounds 恢复高亮和下划线。

---

## 3. 方案概览

本迭代新增 / 修改：

| 模块 | 变更 |
| --- | --- |
| `docs/prd/prd-2026-07-02-reading-context-sidebar.md` | 新增需求文档 |
| `docs/tdd/tdd-2026-07-02-reading-context-sidebar.md` | 新增技术文档 |
| `LumenPDF/Views/ReadingContextSidebarView.swift` | 新增阅读上下文右栏 |
| `LumenPDF/Views/ContentView.swift` | 阅读 Tab 中组合 PDFReader 与右栏；新增右栏显隐按钮 |
| `LumenPDF/Views/PDFReaderView.swift` | 新增 bounds 级定位通知与处理逻辑 |
| `LumenPDF/App/AppState.swift` | 切换文档时刷新单词 / 笔记数据 |

---

## 4. 数据模型

Swift-only 聚合模型：

```swift
private struct ReadingContextItem: Identifiable {
    enum Kind { case vocabulary, note }

    let id: String
    let kind: Kind
    let pageIndex: UInt32
    let pdfPath: String
    let boundsStr: String
    let title: String
    let subtitle: String
    let detail: String
    let createdAt: Int64
}
```

转换规则：

- `VocabularyEntry` → `ReadingContextItem(kind: .vocabulary, boundsStr: selectionBounds)`
- `NoteEntry` → `ReadingContextItem(kind: .note, boundsStr: boundsStr)`

排序：

```swift
items.sorted {
    if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
    return $0.createdAt > $1.createdAt
}
```

---

## 5. SwiftUI 布局

`ContentView` 的 detail 区保持 PDFReader 保活策略，但在 reader 模式下将 PDFReader 包进 `HStack`：

```swift
HStack(spacing: 0) {
    PDFReaderView(document: doc)
        .id(doc.id)

    if showReadingContextSidebar {
        Divider()
        ReadingContextSidebarView()
            .frame(width: 320)
    }
}
```

显示条件：

- `activeTab == .reader`
- `selectedDocument != nil`
- `showReadingContextSidebar == true`

右栏显隐状态用 `@AppStorage` 持久化。

右栏不再提供全部 / 范围筛选：`ReadingContextMode` 只有 `.vocabulary` 和 `.note`，`onChange(appState.currentPageIndex)` 自动滚动到当前页或后续最近条目。用户手动滚动右栏时，页分组 `onAppear` 会发送 `.jumpToPage`，让 PDF 同步到右栏所在页；程序化滚动用 `isProgrammaticScroll` 抑制反向跳转，避免循环。

右栏显隐通过 `toggleReadingContextSidebarPreservingViewport()` 完成：先发送 `.saveReadingPositionNow` 刷新 AppState 中的当前页和 normalized offset，再切换右栏，最后发送 `.restoreReadingViewport` 给 PDFKit coordinator，在布局变化后恢复页码和页内滚动位置。

---

## 6. 定位通知

新增通知：

```swift
extension Notification.Name {
    static let jumpToSelectionBounds = Notification.Name("jumpToSelectionBounds")
}
```

`userInfo`：

| key | type | 说明 |
| --- | --- | --- |
| `pageIndex` | `Int` | 0-based 页码 |
| `filePath` | `String` | PDF 路径 |
| `boundsStr` | `String` | 选区矩形串 |
| `itemId` | `String` | 单词 / 笔记 ID |
| `kind` | `String` | `vocabulary` 或 `note` |

处理流程：

1. 校验 `filePath == currentFilePath`；
2. 找到目标 `PDFPage`；
3. `pdfView.go(to: page)`；
4. 如果 bounds 可解析，则计算 union rect；
5. 用 `pdfView.convert(_:from:)` 转为 view 坐标；
6. 通过 enclosing scroll view 滚动到目标区域；
7. 临时添加半透明 focus annotation，短暂展示后移除。

如果 bounds 为空或解析失败，降级为纯跳页。

---


## 7. 普通划线与笔记输入框

`PDFReaderView` 同时保留普通划线和笔记划线两条路径。用户点击选区菜单「划线」时，通过 `.addFreeAnnotation` 直接写入普通下划线，不创建 draft，也不调用 `BridgeService.saveNote`。用户点击「笔记」时，才创建 `UnderlineNoteDraft`，暂不立即保存。

`UnderlineNoteDraftView` 负责：

- 展示选中文本预览；
- 提供 `TextEditor` 输入用户自己的想法 / 理解；
- 支持「取消」直接关闭；
- 支持「保存」后把 trim 后的 note text 传回 `saveUnderlineNote(word:noteText:boundsStr:page:)`。

笔记文本使用 `NoteTextList` 以 JSON `[String]` 形式存入现有 `notes.note` TEXT 字段：

- 旧纯文本 note 会按单元素 list 兼容读取；
- 新建笔记把输入保存为一条 list item；
- 合并旧笔记时把旧 list 与本次输入 append，避免丢失已有理解；
- 展示、编辑、导出时再解码为多条笔记。

保存路径继续复用原笔记合并算法。普通「划线」只影响自由下划线；「笔记」才写入 notes 表并添加 note-linked 下划线。完全相同选区不再只承担删除语义：选区菜单会显示「添加笔记」用于向现有 note list append 新条目，同时保留「取消笔记」用于删除该笔记及其关联下划线。

## 8. 笔记划线合并算法

`PDFReaderView.saveUnderlineNote` 在保存笔记前读取当前 PDF 的同页笔记，并按 bounds 关系分流：

1. `boundsStr` 完全一致：删除已有 note，并发送 `.removeUnderlineNote`。
2. 新 rects 被任一已有 note 的 rects 完全覆盖：直接返回，不写 DB、不改 PDF annotation。
3. 新 rects 与已有 note rects 有面积交集：删除参与合并的旧 notes，创建一条包含旧 rects + 新 rects 的新 note，并通过 `.addUnderlineNote` 的 `deletedNoteIds` / `deletedNotesInfo` 让 PDFKit 移除旧下划线、绘制扩展后的下划线；undo 使用这些 payload 恢复旧 notes。
4. 无交集：创建独立 note。

合并 rects 时只合并同一文本行上相交/相邻的矩形，跨行选区仍保持 pipe-separated per-line bounds，避免把行间空白也画成下划线区域。


## 9. AI 解释多轮追问

解释气泡复用 `TranslationBubbleRequest` 承载临时对话状态：

- `explanationTurns`: 已完成的问答轮次，用于 UI 展示「前文追问」。
- `activeExplanationQuestion`: 当前正在生成 / 已生成答案对应的问题。
- `explanationSummary`: 传给后续 LLM 请求的本地压缩上下文。

`TranslationBubble` 在解释结果下方展示 follow-up 输入框；用户继续追问时调用原有 `onAskExplanation` 回调，不关闭气泡、不要求重新选择 PDF 原文。

`PDFReaderView.requestExplanation` 在发起下一轮前读取当前 `translationRequest`：

1. 将当前已完成回答追加到 `explanationTurns`。
2. 保留最近 10 轮完整问答。
3. 将更早轮次压缩为短 digest，并把对话摘要截断到固定长度；原始选中文案和原始上下文始终单独传入，不参与压缩。
4. 把「当前问题 + 压缩上下文」拼入现有 `focus` 参数，复用 `BridgeService.explainSelectionStreaming` / Rust UniFFI 接口。

该实现不新增数据库表，不持久化聊天记录；关闭气泡后上下文释放。

---

## 10. 线程与架构约束

- 新增右栏 View 不直接调用 `BridgeService`。
- 数据读取走 `AppState.vocabulary` / `AppState.notes`。
- 数据刷新由 `AppState.refreshVocabulary()` / `AppState.refreshNotes()` 完成。
- UI 状态更新保持在 `@MainActor`。
- Rust domain / application / infrastructure 不变。

---

## 11. 测试策略

### 11.1 手动验证

1. 打开含单词和笔记的 PDF。
2. 确认右侧栏展示当前 PDF 的条目。
3. 滚动 PDF，确认右侧栏跟随到当前页附近条目。
4. 点击「划线」，确认直接添加普通下划线且不弹出输入框。
5. 点击「笔记」，填写理解并保存，确认笔记页和右栏都展示该理解。
6. 对完全相同选区点击「添加笔记」，确认追加为 note list 的新条目。
7. 对完全相同选区点击「取消笔记」，确认删除旧笔记及其关联下划线。
8. 对已有笔记的子区域点击「笔记」并保存，确认不新增、不改动。
9. 对一半旧选区一半新区点击「笔记」并保存，确认旧笔记扩展为一条合并笔记。
10. 点击单词卡片，确认 PDF 跳转到对应页并尽量定位到高亮附近。
11. 点击笔记卡片，确认 PDF 跳转到对应页并尽量定位到下划线附近。
12. 点击工具栏按钮隐藏 / 显示右栏。
13. 点击「解释」并完成首轮生成后，在解释下方继续追问，确认前文问答仍展示且新回答能承接上下文。
14. 连续追问 5 轮以上，确认较早上下文被压缩，不会无限增长。

### 11.2 程序检查

- `swiftc` 不直接适用完整 App，因为项目依赖 Xcode / PDFKit / UniFFI 生成物。
- 优先运行 Xcode build 或 `xcodebuild`。
- Rust 未改动时无需运行 `cargo test` 作为强制项，但可作为回归检查。

---

## 12. 后续优化

1. 加 `list_vocabulary_by_pdf` UniFFI API，避免全量加载词库。
2. 添加右栏卡片选中态，并在定位后保持当前选中项。
3. PDF 标注点击反向滚动右栏。
4. 用 `HSplitView` 支持用户拖拽调整右栏宽度。
5. 对 `pdf_path + page_index` 增加数据库索引。
