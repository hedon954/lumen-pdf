---
version: v1.0.29
date: 2026-08-25
prd: prd/prd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
predecessor:
  - tdd/tdd-2026-03-31-v103.md
  - tdd/tdd-2026-08-19-markup-diagnostics.md
  - tdd/tdd-2026-08-21-workspace-search.md
  - tdd/tdd-2026-08-21-markup-interval-merge.md
successor:
  - tdd/tdd-2026-08-26-annotation-undo-history.md
  - tdd/tdd-2026-09-01-native-translation-popover.md
---

# LumenPDF — 阅读浮层快捷入口与跨页笔记划线 TDD

## 1. 技术结论

搜索仍留在 `ContentView` 的 SwiftUI 根层。搜索呈现时只对底层内容施加 `4pt` 显式失焦，再由遮罩提供明暗分离；不使用固定大半径的系统材质覆盖整窗，以保留正文与侧栏的可辨识层级。翻译快捷入口只转交既有 `ReadingInspectorModel.startGuide`。标注几何以 `PDFPageMarkup` 为单一载荷：自由标注和笔记标注共享事件编码与 PDFKit 目标解析，笔记额外把逐页矩形 JSON 持久化到 SQLite，以覆盖重启恢复。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `WorkspaceSearchOverlay` | 根层使用低透明明暗遮罩；搜索控件和结果卡片使用实体材质与自适应 tint。 |
| `TranslationBubble` | 成功 footer 发出 `onExplain`，不直接持有 Inspector 或服务。后续修订：footer 左侧增加「拷贝译文」，见 [tdd-2026-09-01-native-translation-popover.md](tdd-2026-09-01-native-translation-popover.md)。 |
| `ContentView` | 从 `TranslationBubbleRequest` 还原 `PDFSelectionContext`，关闭翻译浮窗并启动既有导读。 |
| `PDFSelectionMarkupGeometry` / `PDFPageMarkupCodec` | 生成逐页正文矩形；把页码与 `boundsStr` 编解码为稳定 JSON；旧数据回退到单页字段。 |
| `ReaderEventBus` | 自由标注与笔记标注共用 `pageMarkupUserInfo`，同时发出 `pageIndexes` / `boundsStrs`。 |
| `PDFKitView` | 两种标注共用 `annotationTargets`；笔记添加、删除、撤销、重做和恢复遍历全部目标页。后续修订：统一前后快照、50 条顶层历史与原子笔记恢复见 [tdd-2026-08-26-annotation-undo-history.md](tdd-2026-08-26-annotation-undo-history.md)。 |
| `UnderlineNoteMergePolicy` | 在每个页面内继续委托 `TextLineMarkupMerge` 做覆盖、重叠和并集。 |
| Rust note entity / repository / migration | `notes.page_markups TEXT NOT NULL DEFAULT ''`，UniFFI 暴露 `page_markups`，迁移幂等且保留旧行。 |

SwiftUI View 只发送闭包或普通值；数据库与桥接仍由 service / persistence 层调用。

## 3. 数据与流程

```text
PDFSelection
  → PDFSelectionMarkupGeometry.make
  → [PDFPageMarkup]
       ├─ 自由高亮/划线 → ReaderEventBus → PDFKitView.annotationTargets
       └─ 笔记/翻译保存/AI 保存
            → PDFPageMarkupCodec JSON
            → notes.page_markups
            → ReaderEventBus → PDFKitView.annotationTargets
```

- `page_index` 与 `bounds_str` 继续保存主页面，兼容列表、搜索和跳转。
- `page_markups` 保存全部页面的逐行矩形，不保存重复的用户笔记正文。
- 读取时优先解码 `page_markups`；空值或坏值回退到主页面字段。
- 删除按 `noteId` 扫描 PDF 全部页面，避免调用方还要持有跨页范围。
- 笔记部分重叠合并先按页面分组，再在页内运行 `TextLineMarkupMerge`；不允许跨页比较 CGRect。

## 4. 迁移与兼容

`migration.rs` 用 `PRAGMA table_info(notes)` 守卫 `ALTER TABLE`，新增列默认空字符串。迁移可重复运行，旧笔记行数、正文、笔记、页码和矩形不得改变。UniFFI 重新生成 Swift 绑定；不新增 runtime 或第二份存储。

## 5. 验证

- Rust：`cargo fmt --check`、`cargo test domain`、`cargo test migration`、`cargo test`。
- Swift：`TextLineMarkupMergeTests` 覆盖跨页 codec round-trip、旧单页回退、跨页覆盖与合并；运行完整 XCTest。
- 构建：重新生成 Xcode 工程与 UniFFI 后执行 Debug build。
- 运行时：
  - 搜索浮窗在浅色/深色下的背景模糊和文字对比；
  - 翻译成功后按钮位置、点击、翻译浮窗关闭与 Inspector 导读选区一致；
  - 跨两页添加笔记、删除、撤销/重做、关闭 PDF 后重开、退出应用后重开；
  - 跨页选择靠近左右栏时的浮层位置，滚动/缩放/移动/缩放窗口后交互仍正常。

编译只证明代码可构建，不能替代以上视觉和交互验收。
