---
version: unreleased
date: 2026-08-26
prd: prd/prd-2026-08-26-annotation-undo-history.md
predecessor:
  - tdd/tdd-2026-03-25.md
  - tdd/tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md
---

# LumenPDF — 标注撤回历史 TDD

## 1. 技术结论

继续使用 `PDFView` 经 responder chain 取得的窗口级 `UndoManager`，不维护第二套自定义快捷键栈。`ReaderUndoHistoryPolicy` 将 `levelsOfUndo` 设为 50，并保留 `groupsByEvent = true`；自由标注的显式分组确保一次跨页事件只形成一个顶层历史项。依据 Apple 文档，`levelsOfUndo` 约束顶层组且 `0` 表示无限；`removeAllActions(withTarget:)` 可只移除指定 target 的 Undo/Redo 动作，因此文档切换不会误清文本编辑器的其他历史。

参考：[UndoManager](https://developer.apple.com/documentation/foundation/undomanager)、[levelsOfUndo](https://developer.apple.com/documentation/foundation/undomanager/levelsofundo)、[Undo 与响应链](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UndoArchitecture/)。

## 2. 模块边界

| 模块 | 职责 |
| --- | --- |
| `ReaderUndoHistoryPolicy` | 配置 50 个顶层组；按 target 清理 reader 动作。 |
| `PDFReaderView` | ⌘Z / ⇧⌘Z 只向 AppKit responder chain 转发，不直接选择某个 UndoManager。 |
| `PDFKitView.Coordinator` | 注册自由标注与笔记前后快照；跨页分组；文档切换和 teardown 清理自身 target。 |
| `NoteUndoInfo` | 保存笔记 ID、创建时间、正文、笔记文本和逐页几何，并与 `NoteEntry` 无损转换。 |
| `ReaderPersistence` / `BridgeService` | 把笔记历史快照交给单一 UniFFI 接口，不直接操作 SQLite。 |
| note use case / repository | 在一个 SQLite transaction 中删除当前快照并幂等恢复目标快照。 |

## 3. UndoManager 语义

```text
用户操作
  → 注册 current → previous 的 Undo 闭包
  → ⌘Z：原子应用 previous
       → Undo 执行期间注册 previous → current
       → UndoManager 自动把它放入 Redo 栈
  → ⇧⌘Z：原子应用 current，并重新注册反向 Undo
```

- 自由标注继续保存添加和移除的矩形快照；Undo/Redo 后立即刷新 `FreeMarkupStore`。
- 笔记新增：`current = [new]`，`previous = []`。
- 笔记合并：`current = [merged]`，`previous = [old...]`。
- 笔记删除：`current = []`，`previous = [deleted]`。
- 新的正常注册由 `UndoManager` 自动清空 Redo 分支，不手动复制栈。
- `setActionName` 在每次对称注册后设置，使系统菜单在 Undo 和 Redo 两侧保持同一动作名。

## 4. 生命周期与焦点

- `PDFView.undoManager` 实际来自所属窗口；只有 PDFView 挂到窗口后才可配置。
- `makeNSView` 的下一轮主线程和后续 `updateNSView` 都调用幂等配置；首次实际注册前再次配置作为兜底。
- 切换 `filePath` 前先落盘待保存的自由标注，再用 `removeAllActions(withTarget: coordinator)` 清掉旧 PDF 的 reader 动作。
- `dismantleNSView` 执行相同清理，避免 UndoManager 留下已释放 target 或持有旧页面快照。
- 快捷键通过 `NSApp.sendAction(undo:/redo:)` 从第一响应者开始路由。文本框获得焦点时由文本系统处理；PDF 是第一响应者时落到窗口 UndoManager 的标注动作。
- `applyHighlights` 期间继续 `disableUndoRegistration`，恢复已有标注不污染历史。

## 5. 笔记事务

`apply_note_history_snapshot(remove_ids, restore_notes)` 在一个 SQLite transaction 中：

1. 删除当前状态里的笔记 ID；
2. 用 `INSERT ... ON CONFLICT(id) DO UPDATE` 幂等恢复目标 `NoteEntry`；
3. 保留原 `id`、`created_at`、`page_markups` 和存储态笔记文本；
4. 事务成功后才更新 PDFKit 标注并刷新笔记列表。

若事务失败，PDFKit 不变更标注，也不注册逆向操作，并通过 responder 的 `presentError` 展示错误，避免 UI / SQLite 分叉。

## 6. 验证

- Rust：事务快照重复恢复不产生重复行，并保留 ID 与创建时间；`cargo fmt --check`、`cargo clippy -- -D warnings`、`cargo test`。
- Swift：
  - 容量为 50 且不少于 20；超出后丢弃最旧顶层组；
  - 清理 reader target 后保留其他窗口 target 的历史；
  - `NoteUndoInfo` 往返保留身份、时间、跨页几何和笔记存储文本；
  - 合并笔记保持多条用户笔记的列表边界；
  - 既有跨页标注与工作区搜索测试继续通过。
- 运行时：连续标注 20 次的 Undo/Redo；跨页单步分组；合并与删除笔记的 Undo/Redo；Undo 后新操作清 Redo；文本框焦点优先；切换 PDF 清 reader 历史；重开 PDF 检查持久化结果。

编译和单元测试不能替代快捷键、系统菜单、焦点与跨重启的一致性验收。
