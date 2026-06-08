# Plan: 原生风格 PDF 高亮

**日期**: 2026-06-08  
**版本目标**: v1.0.7  
**状态**: v1.0.7 修订中（二次修复）

## 问题

保存单词到单词本或手动高亮时，LumenPDF 创建的标注与 macOS Preview / PDFKit 原生高亮视觉和结构不一致。重新打开 PDF 后，取消高亮需要操作两次。

### 根因

1. **结构差异**：当前对每个文本行分别创建一个 `.highlight` 标注（`bounds` 矩形），未设置 `quadrilateralPoints`；原生高亮使用 **单个标注 + 多组 QuadPoints**。
2. **颜色差异**：当前使用 `systemYellow.withAlphaComponent(0.5)`；原生高亮为不透明黄色，由 PDFKit 负责混合渲染。
3. **重复恢复**：词汇高亮同时写入 PDF 文件，并在文档加载时从 SQLite 再次注入（`applyHighlights`），去重仅检查 `userName`，重开后可能叠两层。
4. **幽灵 Undo**：恢复标注时未 `disableUndoRegistration`，`page.addAnnotation` 会污染撤销栈。

## 目标

- 手动高亮、单词本高亮均使用与 macOS 一致的原生高亮结构（QuadPoints + 标准黄色）。
- 重开 PDF 后，同一选区只需一次取消即可移除高亮。
- 保持现有 `boundsStr` 存储格式不变（管道分隔 per-line rect），向后兼容旧数据。

## 方案

### 1. 新增 `PDFHighlightAnnotationFactory`

集中处理原生高亮创建：

- 输入：`[CGRect]`（per-line rects，页面坐标）
- 输出：单个 `PDFAnnotation`（`.highlight`）
- 设置：
  - `bounds` = 所有 line rects 的 union
  - `quadrilateralPoints` = 每组 4 点（Z 字形，相对 bounds origin）
  - `color` = `NSColor(srgbRed: 1, green: 0.97, blue: 0, alpha: 1)`（与 Preview 默认黄一致）
  - `markupType` = `.highlight`（如可用）

提供 `lineRects(from:)` 从已有标注反推行矩形，供 Toggle / Undo 使用。

### 2. 改造标注创建路径

| 路径 | 改动 |
|------|------|
| `addFreeAnnotation`（高亮） | 单行/多行合并为一个原生高亮标注 |
| `addVocabAnnotation` | 同上 |
| `addFreeAnnotation`（划线） | 不变 |
| `addUnderlineNote` | 不变 |

### 3. 修复重开重复高亮

`applyHighlights` 改造：

- 调用前 `undoManager.disableUndoRegistration()`，结束后 `enableUndoRegistration()`
- 去重条件：`userName == entryId` **或** `contents == "vocab:{entryId}"`
- 恢复模式（`isRestore: true`）不触发 `triggerAnnotationSave`
- 加载后调用 `AnnotationPersistenceService.loadAnnotations` 关联 DB

`removeHighlight` 同步支持按 `contents` 匹配删除。

### 4. Undo 快照升级

`FreeAnnotationSnapshot` 存储 `lineRects`（从 quad points 或 bounds 推导），Undo/Redo 通过 factory 重建原生高亮。

## 验证

1. `xcodebuild` Debug 编译通过
2. 手动验证清单：
   - [ ] 手动高亮视觉接近 Preview 黄色高亮
   - [ ] 保存单词到单词本后高亮样式一致
   - [ ] 保存 → 关闭重开 → 取消高亮一次即可移除
   - [ ] Cmd+Z 撤销/重做仍正常

## v1.0.7 二次修复（2026-06-08 晚）

v1.0.7 首次实现未解决用户反馈的三点问题，根因：

1. **样式仍块状**：仅用 `boundsStr` 矩形合成 QuadPoints，未走 `PDFSelection` / `page.selection(for:)` 真实字形范围；颜色/QuadPoints 未按 PDF 规范写入 page-space `/QuadPoints`。
2. **无法取消**：Toggle 只匹配 `userName == __fh`，PDF 写回后 `userName` 丢失；未做 `contents` 与精确 rect 匹配。
3. **自由高亮重启消失**：2s 防抖保存 + 退出未 flush + 可能 URL 不一致导致 `write` 失败。

### 二次修复要点

- `PDFHighlightAnnotationFactory` 重写：优先 `PDFSelection` → `selectionsByLine()` → page-space `PDFAnnotationKey.quadPoints`
- `Coordinator` 缓存 `lastMarkupSelection`，高亮按钮点击后仍可用 live selection
- Toggle：先精确匹配 line rects，再 fallback 相交判断；匹配 `contents == free:highlight`
- 持久化：`triggerAnnotationSave(immediate:)` + `flushAnnotationsToDisk()` + `appWillTerminate` 同步 write
- 记录 `documentSaveURL` 与加载时 URL 一致

## 不在本次范围

- 划线（underline）样式对齐 Preview（蓝色 `__fu` / 红色 note 划线）
- 旧 PDF 中已存在的多层历史高亮自动合并（用户手动清除一次即可）
