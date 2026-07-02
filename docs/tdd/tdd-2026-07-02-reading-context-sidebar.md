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

## 7. 线程与架构约束

- 新增右栏 View 不直接调用 `BridgeService`。
- 数据读取走 `AppState.vocabulary` / `AppState.notes`。
- 数据刷新由 `AppState.refreshVocabulary()` / `AppState.refreshNotes()` 完成。
- UI 状态更新保持在 `@MainActor`。
- Rust domain / application / infrastructure 不变。

---

## 8. 测试策略

### 8.1 手动验证

1. 打开含单词和笔记的 PDF。
2. 确认右侧栏展示当前 PDF 的条目。
3. 切换「本页」，确认只显示当前页条目。
4. 点击单词卡片，确认 PDF 跳转到对应页并尽量定位到高亮附近。
5. 点击笔记卡片，确认 PDF 跳转到对应页并尽量定位到下划线附近。
6. 点击工具栏按钮隐藏 / 显示右栏。

### 8.2 程序检查

- `swiftc` 不直接适用完整 App，因为项目依赖 Xcode / PDFKit / UniFFI 生成物。
- 优先运行 Xcode build 或 `xcodebuild`。
- Rust 未改动时无需运行 `cargo test` 作为强制项，但可作为回归检查。

---

## 9. 后续优化

1. 加 `list_vocabulary_by_pdf` UniFFI API，避免全量加载词库。
2. 添加右栏卡片选中态，并在定位后保持当前选中项。
3. PDF 标注点击反向滚动右栏。
4. 用 `HSplitView` 支持用户拖拽调整右栏宽度。
5. 对 `pdf_path + page_index` 增加数据库索引。
