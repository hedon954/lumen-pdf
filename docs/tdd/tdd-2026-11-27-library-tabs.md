---
version: v1.0.40
date: 2026-11-27
prd: prd/prd-2026-11-27-library-tabs.md
predecessor:
  - tdd/tdd-2026-11-27-library-shelves.md
---

# 文库与阅读切换

## 边界

顶部四个标签里，只有「阅读」「单词」「笔记」写入原来的 `activeTab`。`browsingLibrary` 仍只活在这次运行里。`showsLibraryShelf` 为真时阅读区画书架，PDF 视图留在下面但不接收点击。

文库把左侧目录的 `NavigationSplitView` 显示成只剩详情。这次赋值不调用 `updateOutlineVisibility`，宽度观察者在书架显示时也不写宽度。离开文库后，绑定再读已保存的可见性和宽度。

点当前这本书只关掉书架，不重新指定 `selectedDocument`，避免用书架上的旧页码重载 PDF。点另一本才换文档，由文档的 `lastPage` 和 `lastScrollOffset` 恢复。

阅读计时把书架视为不在阅读页：`activeTab == .reader` 且 `showsLibraryShelf` 时不上报阅读在前台。

封面视图只画按格子比例缩好的首页图，不填底、不描格子边。书名在封面下，页码和阅读时间在书名下一行，时间靠右。时间来自 `opened_at`。保存阅读位置时一并写下当前时间，所以这一行的时间是最近一次记下进度的时刻。展示格式在 `ShelfReadStamp`：本地日历的今天、昨天、今年和更早。

`SqliteShelfRepo::page` 不按 `position` 排。PDF 用 `opened_at`，书架用子树里最晚的 `opened_at`，空书架用 `created_at`。数值大的在前，相同再按名字。

## 运行时

- 保存阅读位置的同一条更新写下 `opened_at`。回到文库时重新读取，和页码排在同一行。
- 书架显示期间不写目录的可见性和宽度。离开文库后，目录按进入之前保存的状态出现。
