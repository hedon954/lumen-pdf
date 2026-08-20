# LumenPDF — 文库封面与翻译重新生成 TDD

**版本**: v1.0.25 · **日期**: 2026-08-20

## 文档关系

- 对应 PRD：[`prd-2026-08-20-library-cover-translation-retry.md`](../prd/prd-2026-08-20-library-cover-translation-retry.md)
- 前序：[v1.0.24 TDD](tdd-2026-08-19-markup-diagnostics.md)
- 后续：[笔记自动保存与浮窗稳定 TDD](tdd-2026-08-20-note-autosave-overlay-stability.md)
- 索引：[`docs/README.md`](../README.md)

## 1. 技术结论

封面缩略图在 Swift 侧用 PDFKit 渲染首页并缓存；不把位图写入 Rust/SQLite。翻译刷新复用现有 `TranslationOverlayModel` 会话，通过 `skipCache` 绕过 SQLite 翻译缓存。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `PDFCoverThumbnailView.swift` / `PDFCoverThumbnailCache.swift` | 首页渲染、磁盘/内存缓存、失败占位。 |
| `PDFCoverThumbnailGeometry` | 缩略图目标尺寸与裁切，保持列表行高稳定。 |
| `TranslationOverlayModel` | `retry` / `beginRetry`：清空结果、保持 `request.id`、进入 loading。 |
| `TranslationBubble` | 成功或失败后显示刷新按钮；loading 时禁用。 |
| Bridge `translate` | 成功刷新时 `skipCache: true`。 |

## 3. 关键行为

- 封面缓存 key 使用文件路径 + 修改时间，避免替换 PDF 后仍显示旧图。
- `beginRetry` 不得创建新的 `request.id`，否则浮窗 `resetID` 会重置位置。
- 失败重试与成功重新生成共用同一刷新入口，文案分别为「重试」和「重新生成」。

## 4. 验证

- `PDFCoverThumbnailGeometryTests`
- `TranslationOverlayModelTests`（present / fail / retry 保持同一 id）
- 文库封面与刷新后的缓存跳过需在运行中的 App 验收
