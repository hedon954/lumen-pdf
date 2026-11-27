---
version: v1.0.39
date: 2026-11-27
prd: prd/prd-2026-11-27-library-shelves.md
successor:
  - tdd/tdd-2026-11-27-library-tabs.md
predecessor:
  - tdd/tdd-2026-10-04-library-folder-import.md
  - tdd/tdd-2026-10-04-library-copy.md
---

# 书架

## 边界

书架树的规则在 `domain/shelf/service.rs`，不做 I/O。`shelves` 表和 `pdf_documents.shelf_id`、`position` 由 `migration.rs` 幂等补上。根不是一行：`parent_id` 和 `shelf_id` 为空就是文库根。同一层的书架和 PDF 按 `position` 排在一起。

`SqliteShelfRepo` 负责读写。删除时按 `document_id` 或路径删掉这些书的笔记和单词行，再删书库副本。`delete_pdf_document` 仍只移出文库并保留笔记和单词，导入撤回走这条。

Swift 的 `LibraryShelfPage` 画当前层。`AppState.browsingLibrary` 只活在这次运行里，不进窗口恢复。后续修订：文库标签、目录收起和封面时间见 [tdd-2026-11-27-library-tabs.md](tdd-2026-11-27-library-tabs.md)。文件夹导入先在 `LibraryFolderImporter` 里组成目录树，再逐层建书架。

## 测试

- 空名字拒绝；书架不能移入自己或子孙；子树包含嵌套书架。
- 删除集合只留下所属文档在集合里的笔记和单词行。
- 迁移可重复执行，已有的书 `shelf_id` 为空、`position` 为 0。
- 文件夹扫描把子目录收成嵌套书架；不包含子文件夹时子目录里的 PDF 不进入。
