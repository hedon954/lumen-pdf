---
version: v1.0.36
date: 2026-11-24
prd: prd/prd-2026-11-24-note-overlay-update.md
predecessor:
  - tdd/tdd-2026-09-01-native-translation-popover.md
  - tdd/tdd-2026-09-10-reader-open-note-popover.md
  - tdd/tdd-2026-10-13-app-update.md
  - tdd/tdd-2026-11-23-reader-context-viewport.md
---

# 笔记入口、翻译浮窗与检查更新

## 边界

| 模块 | 职责 |
| --- | --- |
| `NoteAnchorCatalog` | 过滤空笔记、按重叠几何分组，跨页同一划线只产出一个入口，并放到最后一页可见行 |
| `ReadingOverlayPanelHost` | 用无边框子 `NSPanel` 承载阅读浮窗，允许拖出主窗口；点击其他应用不关闭 |
| `WindowOutsideClickMonitor` | 只把本应用、且不在浮窗面板上的点击当作点外 |
| `FreeHighlightQuery` / `TranslationBubble` | footer 高亮开关查询并切换自由高亮 |
| `AppUpdateCenter` / `AppUpdateSheet` | 手动检查立即出面板；发布说明走 `MarkdownText` |
| `AppUpdateSwapScript` | 脱离后的助手等 pid 退出再 `mv` + `ditto` + `open` |

SwiftUI 视图仍不调用 `BridgeService`。本次不改 Rust、数据库或 UniFFI。

## 关键规则

### 笔记按钮

`NoteTextList.decode` 为空则不算有内容。`savedNotes` 把重叠的笔记收成一组，一组一个 `NoteAnchorRequest`，`pageMarkups` 保留整段几何。`includingUnderlines` 不再为 `__fu` 自由划线补入口，只把已有入口放到当前可见页的最后一页。

打开回顾时按 `noteId` 或几何重叠收集同一划线上的全部笔记，不再要求 `pageIndex` 与 `boundsStr` 逐字相同。

### 浮窗面板

`ContentView` 根层 `GeometryReader` 只放一个不可命中的附着视图，真正的翻译 / 笔记卡片画在子面板里。面板 `hasShadow = false`，卡片也不再加 SwiftUI 投影。`hidesOnDeactivate = false`，`canBecomeKey = true` 以便笔记输入。`updateNSView` 时附着视图可能还没有 `window`；翻译浮窗会因加载状态再次更新，笔记草稿不会。因此把最近一次内容存下来，在 `viewDidMoveToWindow` 和下一个 runloop 再呈现，避免点「笔记」后面板永远不出现。拖动手柄用屏幕鼠标坐标移动面板，不再用 `deltaX`/`deltaY`（后者在翻转坐标系里会反向）。初次位置仍用原来的放置策略，相对阅读窗口计算后再换成屏幕坐标。阅读浮窗的 `showsAnchorPointer` 为 false，不画指向选区的三角。

点外关闭去掉 `didResignActive`。本地点击监视把 `LumenPDF.ReadingOverlayPanel` 视为内部，并推迟到下一个 runloop 再安装，避免打开浮窗的那次点击立刻把它关掉。滚动或缩放 PDF 仍由现有 `onTranslationViewportChanged` 关闭翻译。

### 原地更新

正在运行的 bundle 不能直接覆盖。助手用 `bash -c 'nohup … &'` 脱离，避免 `Process` 子进程随 App 退出被收走。应用先发 `saveReadingPositionNow` 再 `terminate`，两秒后若还在就 `exit(0)`。脚本最多等 120 秒；60 秒发 SIGTERM，90 秒发 SIGKILL。旧进程消失后再替换并 `open`，避免 Launch Services 激活仍在跑的旧实例。

## 验证

- `NoteAnchorCatalogTests`：空笔记 / 自由划线无入口；跨页只留一个入口并随可见页移动；不相邻划线仍分开。
- `AppUpdatePolicyTests`：swap 脚本先等进程退出再替换再打开，并含 TERM/KILL。
- 运行中的 App 验收：拖出窗口且方向与鼠标一致、点其他应用不关、点正文才关、操作栏「笔记」弹出输入框、footer 高亮、检查更新面板与 Markdown、从 `/Applications` 确认替换。编译不能替代这些交互。
