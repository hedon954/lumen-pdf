---
version: v1.0.20
date: 2026-08-05
prd: prd/prd-2026-08-05-viewport-restore-overlay-drag.md
prev: tdd/tdd-2026-07-13-v1016-reader-selection-overlays.md
next: tdd/tdd-2026-08-09-selection-overlay-placement.md
---

# LumenPDF — 阅读位置恢复与浮窗拖动 TDD

## 1. 技术结论

本迭代仅调整 Swift 阅读层，不修改 Rust、UniFFI、数据库 schema。

阅读位置的权威富状态仍在 `ReadingRestorationStore`（UserDefaults `reading_restoration_state_v1`）。本次在 `PDFViewport` 中增加可选页坐标锚点，并把滚动换算抽成纯几何类型 `ReaderViewportGeometry`，避免把“相对文档高度的比例”当作跨布局稳定的坐标。

窗口型浮层继续复用 `ReadingOverlayWindow`。本次修正其放置与命中测试模型，并新增 `ReadingOverlayMoveHandle` 作为唯一显式拖动手柄，修复关闭按钮与点外关闭被吞掉的问题。

## 2. 影响范围

| 文件 / 模块 | 职责 |
| --- | --- |
| `LumenPDF/Reader/ReadingRestorationState.swift` | `PDFViewport.PageAnchor`；旧数据兼容；无效锚点清洗。 |
| `LumenPDF/Reader/PDFReaderModels.swift` | `ReaderViewportGeometry`：可视左上角 ↔ clip view 原点。 |
| `LumenPDF/Reader/PDFKitView.swift` | 采集/恢复锚点；布局稳定前重试；主动滚动与显式导航结束恢复。 |
| `LumenPDF/Reader/ReadingOverlayWindow.swift` | `offset` 放置、点外关闭、移动手柄环境值、缩放热区避开标题栏。 |
| `LumenPDF/Views/TranslationBubble.swift` | 四向箭头改为 `ReadingOverlayMoveHandle`。 |
| `LumenPDF/Reader/UnderlineNoteDraftView.swift` | 笔记草稿标题栏加入移动手柄。 |
| `LumenPDF/Views/PDFReaderView.swift` | 笔记回顾浮层标题栏加入移动手柄。 |
| `LumenPDF/Tests/ReaderViewportGeometryTests.swift` | 纯几何与 `PDFViewport` Codable 兼容测试。 |

## 3. 阅读位置：数据模型

### 3.1 页锚点

```swift
struct PDFViewport: Codable, Equatable {
    struct PageAnchor: Codable, Equatable {
        var pageIndex: Int
        var x: Double
        var y: Double
    }

    var pageIndex: Int?
    var autoScales: Bool
    var scaleFactor: Double
    var horizontalOffset: Double
    var verticalOffset: Double
    var anchor: PageAnchor?
}
```

- `anchor` 表示视口左上角在某一页坐标系中的点；与当前 `scaleFactor` / 文档总高度无关。
- `horizontalOffset` / `verticalOffset` 继续保留，供升级前已保存、尚无锚点的视口回退。
- `version` 保持为 `1`；新增可选字段，不触发整包迁移或清空。

### 3.2 几何换算

`ReaderViewportGeometry` 负责：

1. 从 `documentVisibleRect` 得到文档坐标系下的可视左上角（区分 flipped / unflipped）。
2. 从该左上角反算 clip view origin，并钳制在可滚动范围内。
3. 从归一化比例换算 origin（仅兼容路径）。

单元测试必须覆盖：回环、文档变高后锚点不漂移、比例路径会漂移、非有限值兜底。

## 4. 阅读位置：采集与恢复

### 4.1 采集

`PDFKitView.Coordinator.captureViewportState`：

1. 若可视区域或文档高度已塌陷（关窗/退出过程），返回 `nil`，保留上一次稳定采集。
2. 继续写入归一化偏移与缩放。
3. 通过 `pdfView.page(for:nearest:)` 将可视左上角转为 `PageAnchor`。

### 4.2 恢复时序

文档赋值后：

1. 立即应用缩放，并 `go(to:)` 目标页。
2. 以锚点优先、比例回退的方式对齐滚动。
3. 在 `0.05 / 0.15 / 0.3 / 0.5 / 0.8s` 重试，`1.1s` 收尾；总超时 `2.0s`。
4. 恢复期间若收到 `PDFViewScaleChanged`，合并调度一次重新对齐。
5. `willStartLiveScroll` 或目录/页码/笔记定位等显式导航时，调用 `cancelPendingViewportRestore()` / `finishViewportRestore`，停止继续纠正。

### 4.3 与既有双存储的关系

- UserDefaults 中的 `PDFViewport`（含锚点）是精确定位的主来源。
- SQLite `last_page` / `last_scroll_offset` 仍由 `onPageChange` 更新，用作无富视口时的回退，以及 TOC 预高亮。

## 5. 浮层：放置、拖动与关闭

### 5.1 放置与命中测试

禁止对铺满父视图的 `.position` 子视图再挂空的 `.onTapGesture {}`：这会吞掉阅读区内所有点击。

正确模型：

```text
ZStack(alignment: .topLeading)
  ├─ Color.clear（可选，点外关闭）
  └─ window.offset(origin)   // 命中区域 = 卡片视觉边界
```

### 5.2 移动手柄

```swift
struct ReadingOverlayMoveHandle: View {
    @Environment(\.readingOverlayMove) private var move
    // AppKit ReadingOverlayDragCapture 作为命中目标
}
```

- `ReadingOverlayWindow` 通过 environment 注入 `moveWindow`。
- 业务浮层只在 header 放置 `ReadingOverlayMoveHandle()`，不自行实现拖动状态。
- 手柄是前景命中目标，不是标题栏 `background`，因此按住图标即可拖动。

### 5.3 关闭与缩放热区

- 点外关闭只绑定背景透明层。
- 关闭按钮位于 header，不再被标题栏背景拖动层或顶部缩放热区覆盖。
- 缩放 overlay 增加 `padding(.top, measuredHeaderHeight - hitThickness)`，把边缘/角落热区限制在标题栏以下。

## 6. 兼容性

| 场景 | 行为 |
| --- | --- |
| 旧 `PDFViewport` JSON 无 `anchor` | 正常解码，`anchor == nil`，恢复走比例回退。 |
| 新版本写入带 `anchor` | 后续恢复优先锚点。 |
| 无效锚点（负页码 / NaN） | `sanitized` 时清除，不丢弃整个视口。 |
| 无 UserDefaults 视口 | 继续用 SQLite 页码 + 纵向 scrollOffset。 |

## 7. 验证

### 7.1 自动化

```bash
# Xcode
xcodebuild test -project LumenPDF/LumenPDF.xcodeproj -scheme LumenPDF \
  -destination 'platform=macOS' -only-testing:LumenPDFTests/ReaderViewportGeometryTests
```

覆盖点：flipped/unflipped 回环、锚点抗文档增高、比例漂移、钳制、旧 JSON 解码、锚点往返。

### 7.2 运行时（必需）

1. 文档中部退出重开：可见文本一致；缩放与横向位置正确。
2. 改变窗口/侧栏宽度后退出重开：仍回到同一段文字附近。
3. 最小化再还原：不跳到文档开头。
4. 翻译浮层：按住四向箭头可拖；`×` 可关；点外可关；朗读/保存可用。
5. 笔记草稿与笔记回顾：手柄可拖；关闭按钮可用。

仅编译通过不能视为本迭代验收完成。
