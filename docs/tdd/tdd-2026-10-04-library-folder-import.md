---
version: unreleased
date: 2026-10-04
prd: prd/prd-2026-10-04-library-folder-import.md
predecessor:
  - tdd/tdd-2026-03-22.md
---

# 从文件夹导入 PDF

## 边界

- 选择与入库留在 Swift。不新增 Rust 接口。新文件沿用 `upsertPdfDocument`；已在 `library` 中的路径不调用 upsert，因此 `opened_at` 和阅读位置保持不变。
- `LibraryFolderImporter.importablePDFs` 决定哪些条目可加入：普通文件、扩展名 `pdf`（忽略大小写）、非符号链接、非目录，并按路径去重后排序。`isNested` 的条目只在 `includingSubfolders` 为真时加入。未勾选时用 `contentsOfDirectory` 只读当前层；勾选后才递归，并使用 `skipsHiddenFiles` 与 `skipsPackageDescendants`。
- 枚举和 bookmark 创建放在后台，且发生在文件夹 `startAccessingSecurityScopedResource()` 仍有效时。bookmark 选项与单文件打开相同，键仍为 `bm_<path>`。已在文库中的路径不重新写 bookmark。
- `AppState` 在入库时再次用当前文库过滤。成功插入后才保存 bookmark，并只 `refreshLibrary()` 一次。不修改 `selectedDocument`。有新文件时，`ReaderToast` 带撤回闭包；后出现的提示用 id 避免被上一条的定时器清掉。撤回只对本次路径调用 `deletePdfDocument`。
- 清空先经 `NSAlert` 确认，再对当前文库逐条 `deletePdfDocument`，并取消当前文档。该删除不触碰笔记表和单词表。`openLibraryDocument` 在文库中找不到路径时改走 `openPDF`，从而把文件加回文库。
- 入口：工具栏与文库弹层共用 `LibraryAddMenu`；空状态和「文件」菜单分别调用 `openFilePicker` / `openFolderPicker`。文件夹面板用 accessory checkbox，默认关闭。弹层标题为「文库」，非空时提供「清空」。

## 验证

- `LibraryFolderImportTests` 覆盖可导入文件的筛选、大小写扩展名、重复路径、符号链接、目录、默认排除子文件夹，以及已存在路径不进入插入列表。
- 文件夹选择、导入后的当前文档、文库排序和打开新文件，需要在运行中的 App 里验收。单元测试不能代替这次交互。
