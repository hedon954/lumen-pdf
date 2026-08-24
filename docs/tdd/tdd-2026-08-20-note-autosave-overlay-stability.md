---
version: v1.0.26
date: 2026-08-20
prd: prd/prd-2026-08-20-note-autosave-overlay-stability.md
prev: tdd/tdd-2026-08-20-library-cover-translation-retry.md
---

# LumenPDF — 笔记自动保存与翻译浮窗位置稳定 TDD

## 1. 技术结论

笔记编辑是纯 Swift 表现层：复用现有 `updateNote` 与 `NoteTextList` 条目编码，不改 Rust schema。浮窗稳定通过锁定 origin 实现，而不是继续用「换边避让」对抗高度变化。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `AutoSavingNoteEditor.swift` | 多行输入、防抖、失焦/消失时 flush、「保存成功/失败」。 |
| `NoteAutoSavePolicy` | 纯函数：trim、空值跳过、与上次相同则不写。 |
| `NoteTextList.replacingItem` | 只替换目标下标，保持其余条目。 |
| `AppState.saveNoteItem` | 查当前 raw → 替换 → `ReaderPersistence.updateNote` → `refreshNotes`。 |
| `ReadingNotesPanel` / `NoteReviewPopoverView` / `NoteListView` | 接入编辑器；跳转按钮不再包住输入区。 |
| `ReadingOverlayWindow` | `lockedOrigin`：首次有效尺寸后固定左上角，其后只 clamp。 |
| `ReadingOverlayPlacementPolicy.place(_:keeping:)` | 保持原方向，即使增高后与选区重叠。 |

## 3. 自动保存

```text
按键 → 取消上一 Task → 450ms → textToSave(current, lastSaved)
  → nil：不写
  → 有值：onSave → 成功则 lastSaved = prepared，显示「保存成功」
```

`NoteTextList.storageString` 仍会 decode/encode 一遍，因此 `replacingItem` 必须返回可被 decode 的 JSON 数组。

## 4. 浮窗原点锁定

1. 首次 `recordMeasuredWindowSize` 且尚无手动 `customCenter` 时，按当时尺寸调用 `place`，写入 `lockedOrigin`。
2. 之后 `displayedOrigin` 只对锁定原点做容器 clamp，不再 `place(keeping:)`。
3. `resetID` 变化（新翻译会话）清空 `lockedOrigin`。
4. 用户拖动写入 `customCenter`，优先于锁定原点。

`place(_:keeping:)` 仍保留给其他调用方：保持原 placement 的几何，但不再因 overlap 改去完整搜索。这撤销了 v1.0.21 TDD 第 4 节「长高后换边」的窗口行为。

## 5. 验证

`NoteTextListTests`：

- 替换目标条目、未知下标、空文本拒绝写入
- `NoteAutoSavePolicy` 忽略未改动和空白

`ReadingOverlayPlacementTests`：

- `keeping: .below` 在内容变高后仍为 `.below`，origin 的顶边不变
- 锁定原点在仍放得下时不动，超出容器时只做最小 clamp

运行时必须在 macOS App 中确认：翻译完成不跳位；三处笔记编辑自动保存。编译不能代替这项验收。
