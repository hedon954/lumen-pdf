---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-workspace-search.md
predecessor:
  - tdd/tdd-2026-03-22.md
  - tdd/tdd-2026-07-03-reading-inspector.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
---

# LumenPDF — 工作区搜索 TDD

## 1. 技术结论

工作区搜索是纯 Swift 表现层：用普通结构体做索引与匹配，不新增 UniFFI 或 SQLite 表。浮层挂在 `ContentView` 的 `NavigationSplitView` 上，避免被分栏裁切。跳转复用 `ReaderEventBus`；原文命中额外发一次页内文本点亮。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `WorkspaceSearchKind` / `WorkspaceSearchRecord` | 五类结果与可测试的普通记录，不依赖 UniFFI。 |
| `WorkspaceSearchCatalog` | 把笔记、单词、划线文本、分页原文、导读消息编成记录。 |
| `WorkspaceSearchMatcher` | 空查询、类别过滤、大小写折叠、多词 AND、打分与摘要。 |
| `WorkspaceSearchController` | 弹出/关闭、查询、启用类别、当前高亮项。 |
| `WorkspaceSearchOverlay` | Spotlight 风格胶囊输入与圆形类别按钮。 |
| `WorkspaceSearchOpener` | 切到阅读页、打开 PDF、跳页/选区、必要时打开 Inspector。 |
| `PDFKitView` `highlightSearchQuery` | 在目标页用 `page.string` 定位后点亮匹配。 |

## 3. 索引

弹出浮层时重建一次目录，不在每次按键时重读 PDF。

- **笔记**：`content` + `NoteTextList.decode(note)`；`kind = .note`。
- **单词**：词条及翻译/解释/词源/例句字段；`kind = .word`。
- **划线**：当前 `kitDocument` 上 `FreeMarkupStore` 各项，按 `boundsStr` 取出 `PDFPage.selection` 文本；没有文本则跳过。
- **原文**：当前 PDF 每页 `page.string`，按段落合并成不超过约 480 字的块。
- **AI 解释**：当前 `ExplanationSession` 中非空、非错误消息。

`WorkspaceSearchRecord` 只含 `String` / `Int` 字段，测试可直接构造。

## 4. 匹配

```text
normalize(query) 为空 → []
tokens = 空白拆分
记录须属于 enabledKinds
每个 token 都出现在 normalize(title + haystack) 中
分数：标题前缀 > 标题包含 > 正文包含；同类再按页码、标题稳定排序
最多 40 条
摘要取匹配附近约 96 字
```

未点选任何类别时视为全部开启；至少保留一类。

## 5. 呈现与跳转

- `LumenPDFApp` 在 `.commands` 注册「查找…」⌘F，经 `ReaderEventBus.presentWorkspaceSearch` 通知 `ContentView`。
- 浮层使用 `.ultraThinMaterial`、胶囊搜索条、直径 36 的圆形类别按钮；结果列表叠在搜索条下方。
- 打开结果：`activeTab = .reader`，必要时 `selectedDocument` 切到 `pdfPath`，延迟后 `jumpToSelectionBounds` 或 `jumpToPage`。
- 单词 / 笔记 / AI 打开对应 Inspector 模式；原文另外 `highlightSearchQuery`。
- 搜索态是瞬时的，不写入 `ReadingRestorationStore`。

## 6. 验证

`WorkspaceSearchMatcherTests`：

- 空查询无结果
- 笔记命中用户笔记与原文
- 单词命中释义与词源
- 类别过滤排除其他类
- 多词 AND、大小写不敏感
- 标题命中排在正文命中之前
- 摘要截取匹配附近文本
- 分页原文切块后仍能命中

运行时须在 macOS App 中确认：⌘F 弹出与聚焦、五类都能命中、圆形过滤、Return 跳转、Esc / 点外侧关闭、深浅色外观。本环境无法运行 macOS UI，编译不能代替这项验收。
