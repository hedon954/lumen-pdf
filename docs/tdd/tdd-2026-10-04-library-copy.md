---
version: v1.0.35
date: 2026-10-04
prd: prd/prd-2026-10-04-library-copy.md
predecessor:
  - tdd/tdd-2026-10-04-library-folder-import.md
  - tdd/tdd-2026-10-04-reading-log.md
---

# 书库副本

## 边界

- `domain/library/service.rs` 只放纯规则：书库文件名（只取最后一段，去掉路径分隔符和开头的点，保证 `.pdf` 结尾）、`<id>/<文件名>` 相对路径、id 不能逃出书库、路径是否已在书库里。
- `infrastructure/library_store.rs` 负责文件：`sha256` 流式计算；`copy_in` 用 `fs::copy`（macOS 上会先尝试 `fclonefileat` 克隆）写到同目录的 `.copy.partial`，校验哈希后再改名；目标已存在且哈希一致时直接复用；`remove` 删除 `Library/<id>/`。原文件只读。
- 表结构（`migration.rs`，幂等）：`pdf_documents` 增加 `content_hash`、`original_path` 和哈希索引；`notes`、`vocabulary_entries` 增加 `document_id`。两个 `AFTER INSERT` 触发器按 `pdf_path` 给新行填 `document_id`。`PdfDocument` 增加 `original_path`。
- 迁移（`infrastructure/db/library.rs`，`initialize` 在建表后调用，失败不阻止启动）：
  1. 找出 `file_path` 不在书库里的书。有原文件存在且旁边还没有 `data.db.before-library-*` 时，先用 `VACUUM INTO` 写 `data.db.before-library-<时间>`。备份只做一次，就是迁移前的状态；复制一直失败的书不会让每次启动都多一份备份。
  2. 在事务外逐本复制进书库。原文件不在算 missing，复制或校验失败算 failed，都保持原路径。
  3. 一个事务里改写每本已复制书的 `pdf_documents.file_path`（条件带旧路径）、`content_hash`、`original_path`，以及 `notes` / `vocabulary_entries` 的 `pdf_path` 和 `document_id`，再按路径给其余行补 `document_id`。
  - 第 2 步后崩溃：数据库没变，重跑时 `copy_in` 按哈希复用已有副本。提交后重跑：已在书库里的书不会被选中，不会重复复制或改写。不会再做第二份备份。
  - `initialize` 把结果（copied / missing / failed，或整体出错的原因）存起来，`library_migration_summary()` 交给 Swift；`BridgeService` 初始化后用 `Logger(subsystem: "com.LumenPDF.app", category: "library")` 写进系统日志。
- 导入 `import_pdf_document`（`SqlitePdfDocumentRepo::import`）：
  - 路径已在书库里：只更新打开时间。
  - 文库里有同一原路径的旧书（迁移时原文件不在）：补做复制并改写，`is_new = false`。
  - 有相同 `content_hash` 的书：复用，`is_new = false`。
  - 否则新建 id，复制后在一个事务里插入，并把 `pdf_path` 等于原路径且没有 `document_id` 的笔记和单词接回新副本。插入失败时删除副本。
  - 只有知道页数（大于 0）时才更新 `total_pages`。
- 删除 `delete_pdf_document`：一个事务里把这本书的笔记和单词指回 `original_path` 并清空 `document_id`，再删文档行；提交后删除书库目录。
- Swift：`openPDF` 和文件夹导入改用 `importPdfDocument`，打开返回的副本。文件夹导入把 `is_new = false` 计入「已在文库中」，撤回按副本路径移出。已在文库中的判断、恢复上次打开的文档和从笔记打开都同时认副本路径和 `originalPath`。文库列表对文件不存在的书显示「找不到文件」。清空文库的确认文案说明副本会删除。

## 验证

- `domain/library/service.rs`：文件名清洗、相对路径、id 安全、书库路径判断。
- `library_store.rs`（临时目录）：复制一致且原文件不变、复用已有副本、哈希不符时不留文件、删除只删这一本。
- `db/library.rs`（临时数据库和假文件）：迁移后笔记、单词、划线、进度不变且链接到副本，备份里是旧路径；原文件缺失的书留下、其余照常迁移；提交前崩溃后重跑既不重复复制也不重复改写，只有第一份备份；复制一直失败时重复启动也只有一份备份；表结构和触发器重复执行无副作用。
- `pdf_document_repo.rs`（临时数据库和假文件）：导入复制且原文件不变；同内容改名复用；同名不同内容是新书；移除删除副本、笔记指回原文件、重新导入后接回；旧书原文件回来后补做复制。
- Swift 测试：在 XCTest 宿主里（有 `XCTestConfigurationFilePath`）`AppDataDirectory` 返回临时目录（可用 `LUMENPDF_TEST_DATA_DIR` 指定，正常启动时忽略），宿主只起一个空 App，不建 `AppState`、不初始化数据库，测试碰不到真实文库。`AppDataDirectoryTests` 覆盖这一点。
- Swift 端的导入、列表标记和迁移后的真实数据需要在运行中的 App 里验收；开发时没有对真实数据运行迁移。
