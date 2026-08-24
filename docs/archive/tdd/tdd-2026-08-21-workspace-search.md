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
| `WorkspaceSearchOverlay` | 窗口居中的大胶囊输入，下方是带文字的类别开关。 |
| `WorkspaceSearchOpener` | 切到阅读页、打开 PDF、跳页/选区、必要时打开 Inspector。 |
| `PDFKitView` `highlightSearchQuery` | 在目标页用 `page.string` 定位后点亮匹配。 |

## 3. 索引

弹出浮层时只为默认类别建索引，不在每次按键时重读 PDF，也不在打开搜索时扫描全文。

- **笔记**（默认）：`content` + `NoteTextList.decode(note)`；`kind = .note`。
- **划线**（默认）：当前 `kitDocument` 上 `FreeMarkupStore` 各项，按 `boundsStr` 取出 `PDFPage.selection` 文本；没有文本则跳过。
- **单词**（按需）：词条、音标、翻译、释义为短查询字段；语境解释、词源、例句仅当查询不少于 4 个字符。
- **原文**（按需）：当前 PDF 每页 `page.string`，按段落合并成不超过约 480 字的块。
- **AI**（按需）：当前 `ExplanationSession` 中非空、非错误消息。

`WorkspaceSearchController` 按类别缓存已加载记录；点开「原文」才调用 `page.string`。

`WorkspaceSearchRecord` 只含 `String` / `Int` 字段，测试可直接构造。

## 4. 匹配

```text
normalize(query) 长度 < 2 → []
tokens = 空白拆分
记录须属于 enabledKinds；空集合视为默认（笔记+划线）
短查询（< 4）只搜 title + primaryHaystack
每个 token 都出现在选用字段中
分数：标题精确/前缀 > 标题包含 > 正文包含；原文按块长度轻微降权
最多 40 条
摘要取匹配附近约 96 字
查询输入防抖约 80ms
```

默认启用 `.note` 与 `.underline`。点击开关加载对应类别；至少保留一类开启。

## 5. 呈现与跳转

- `LumenPDFApp` 在 `.commands` 注册「查找…」⌘F，经 `ReaderEventBus.presentWorkspaceSearch` 通知 `ContentView`。
- 浮层在窗口正中：独占一行的扁平胶囊搜索条（高度约 52pt、最大宽度约 720pt），下方居中是「笔记 / 划线 / 单词 / 原文 / AI」文字开关；结果列表再叠在开关下方。
- 打开结果：`activeTab = .reader`，必要时 `selectedDocument` 切到 `pdfPath`，延迟后 `jumpToSelectionBounds` 或 `jumpToPage`。
- 单词 / 笔记 / AI 打开对应 Inspector 模式；原文另外 `highlightSearchQuery`。
- 搜索态是瞬时的，不写入 `ReadingRestorationStore`。

## 6. 验证

`WorkspaceSearchMatcherTests`：

- 空查询与单字符查询无结果
- 默认类别为笔记与划线
- 短查询不匹配单词例句
- 笔记命中用户笔记与原文
- 单词命中释义；较长查询可命中词源
- 类别过滤排除其他类
- 多词 AND、大小写不敏感
- 标题命中排在正文命中之前
- 摘要截取匹配附近文本
- 分页原文切块后仍能命中

运行时须在 macOS App 中确认：⌘F 在窗口中央弹出较大的扁平搜索条并可立即输入；类别开关在搜索条下方居中；默认结果不含单词/原文；打开原文后才变慢可接受；Return 跳转；Esc / 点外侧关闭。本环境无法运行 macOS UI，编译不能代替这项验收。
