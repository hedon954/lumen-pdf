# LumenPDF — 笔记浮层与划线回顾优化 TDD

**版本**: v1.0.15 · **日期**: 2026-07-10

对应 PRD：`docs/prd/prd-2026-07-10-note-overlay-optimization.md`

## 1. 技术结论

本迭代只调整 Swift / PDFKit 阅读层交互，不需要 Rust、UniFFI 或数据库迁移。核心做法是抽出一个通用的阅读浮层定位与拖动模型，让「添加笔记」「笔记回顾」「长内容解释」共用同一套避让、clamp 和滚动约束；同时在 PDFKit overlay 层为 note underline 绘制轻量可点击图标。

## 2. 影响范围

| 文件 / 模块 | 调整方向 |
| --- | --- |
| `LumenPDF/Reader/UnderlineNoteDraftView.swift` | 添加可滚动内容区、固定底部按钮、支持外部传入拖动 handle。 |
| `LumenPDF/Reader/PDFReaderView.swift` | 管理笔记草稿浮层位置、回顾浮层状态、与 PDFKit 坐标转换。 |
| `LumenPDF/Reader/PDFKitView.swift` | 暴露 note underline 的页面 rect / window rect，刷新图标 overlay。 |
| `LumenPDF/Reader/ReaderEventBus.swift` | 复用现有笔记增删事件，必要时新增打开笔记回顾事件。 |
| `LumenPDF/Views/ReadingInspector/*` | 如存在长内容浮层或导读内容截断，补充 ScrollView / maxHeight 约束。 |
| 新增 `LumenPDF/Reader/ReadingOverlayPlacement.swift` | 纯函数：候选位置、避让选区、窗口 clamp。 |
| 新增 `LumenPDF/Reader/DraggableReadingOverlay.swift` | 通用 SwiftUI 容器：定位、拖动、边界限制。 |
| 新增 `LumenPDF/Reader/NoteAnchorOverlayView.swift` | 绘制已有笔记图标并处理点击。 |
| 新增 `LumenPDF/Reader/NoteReviewPopoverView.swift` | 展示已有笔记内容，支持滚动与拖动。 |

## 3. 设计原则

1. **Views 不直接访问 BridgeService**：新增回顾浮层只能消费上层传入的 `NoteEntry` / view model 数据。
2. **PDFKit 坐标转换集中处理**：PDF page rect → PDFView bounds → SwiftUI overlay 坐标的逻辑放在 coordinator 或小型 helper 中，避免散落在多个 View。
3. **定位算法纯函数化**：避让、候选点和 clamp 逻辑不依赖 SwiftUI，可写单元测试。
4. **不修改数据库模型**：图标完全由现有 note underline 数据和 annotation bounds 派生。
5. **渐进增强**：若个别 PDF 坐标无法转换，图标可跳过该条笔记，但不能影响阅读和笔记保存。

## 4. 浮层定位模型

### 4.1 数据结构

```swift
struct ReadingOverlayPlacementInput: Equatable {
    let anchorRect: CGRect
    let overlaySize: CGSize
    let containerSize: CGSize
    let preferredGap: CGFloat
    let safeInset: CGFloat
}

struct ReadingOverlayPlacementResult: Equatable {
    let origin: CGPoint
    let placement: ReadingOverlayPlacement
}

enum ReadingOverlayPlacement: Equatable {
    case below
    case above
    case trailing
    case leading
    case leastOverlap
}
```

### 4.2 算法

1. 生成候选位置：below、above、trailing、leading。
2. 对每个候选位置执行 container clamp。
3. 计算候选浮层 rect 与 `anchorRect` 的交集面积。
4. 优先选择交集面积为 0 的候选，并按 below → above → trailing → leading 排序。
5. 如果所有候选都会遮挡选区，选择交集面积最小的候选。
6. 返回 origin 和 placement 类型。

### 4.3 边界处理

- `containerSize` 为空时使用居中 fallback。
- `overlaySize` 大于可用区域时，origin clamp 到 safeInset，尺寸由外层 maxHeight / maxWidth 限制。
- 窗口 resize 后重新 clamp 当前手动位置；不重新套用默认候选，避免用户拖动位置跳变。

## 5. 通用可拖动浮层

新增 `DraggableReadingOverlay`：

```swift
struct DraggableReadingOverlay<Content: View>: View {
    let initialAnchorRect: CGRect
    let containerSize: CGSize
    let overlaySize: CGSize
    let onDismiss: () -> Void
    @ViewBuilder let content: (_ dragHandle: AnyView) -> Content
}
```

建议实现为：

- 父级使用 `GeometryReader` 获取阅读区域尺寸。
- `@State` 保存 `origin`、`hasManualPosition`、`dragStartOrigin`。
- 标题栏通过 `DragGesture(minimumDistance: 1)` 更新 origin。
- 每次更新 origin 都调用 `clampedOrigin`。
- `content` 内部明确将标题栏作为 drag handle，避免 TextEditor / ScrollView 抢手势。

如果 SwiftUI 泛型 drag handle 复杂，也可先实现为固定容器：

```swift
DraggableReadingOverlay(title: ..., icon: ..., anchorRect: ...) {
    scrollableBody
} footer: {
    actions
}
```

## 6. 添加笔记浮层改造

### 6.1 状态来源

`UnderlineNoteDraft` 已包含选区文本、页码和 bounds 信息。实现时需要确保上层可以得到选区在阅读 overlay 坐标系下的 `anchorRect`：

- 优先从当前 PDF selection 获取 line rects 并转换。
- 如果只有 `boundsStr`，解析为 PDF page rect 后转换。
- 转换失败时使用 PDFReader 可见区域中心偏上 fallback。

### 6.2 视图结构

`UnderlineNoteDraftView` 改为：

```swift
VStack(spacing: 0) {
    draggableHeader
    ScrollView {
        selectedTextPreview
        TextEditor(...)
    }
    .frame(maxHeight: computedMaxBodyHeight)
    footerActions
}
```

注意：

- TextEditor 保持固定最小高度，例如 74pt。
- 原文预览超过 3–4 行时可在 ScrollView 内完整查看。
- 底部按钮固定，不进入 ScrollView。

## 7. 长内容解释 / 导读滚动

需要检查两类 UI：

1. 如果长解释仍使用浮层展示：给浮层 body 加 `ScrollView`，外层设置 `maxHeight = min(620, windowHeight * 0.7)`。
2. 如果长解释已迁入 `ReadingGuidePanel`：确保 panel 自身是可滚动列表，并且流式输出时只在用户位于底部时自动跟随。

推荐抽出：

```swift
struct ReadingOverlayScrollableBody<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
}
```

所有浮层正文复用它，避免再次出现内容截断。

## 8. 已有笔记图标 overlay

### 8.1 Anchor 模型

```swift
struct NoteAnchor: Identifiable, Equatable {
    let id: String
    let noteId: String
    let pageIndex: Int
    let bounds: CGRect
    let displayPoint: CGPoint
    let notes: [NoteEntry]
}
```

`displayPoint` 计算规则：

- 多行 underline：取最后一行 rect 的 trailing-middle。
- 单行 underline：取 rect.maxX + 6, rect.midY。
- clamp 到 PDFView 可见区域，避免跑出页面边界。

### 8.2 数据来源

- `appState.notes` 按 `pdfPath` 过滤当前文档。
- 使用 `boundsStr` 转换到当前 PDFView overlay 坐标。
- 对同一 `boundsStr` 或高度重叠的 note 进行分组，避免多个图标重叠。
- 监听以下变化刷新 anchors：
  - 当前 PDF 切换。
  - PDFView 缩放 / 滚动 / 页面变化。
  - note add / delete / update 事件。
  - Inspector 显示 / 隐藏导致布局变化。

### 8.3 图标视图

`NoteAnchorOverlayView`：

- 使用 `ZStack(alignment: .topLeading)` 按 `displayPoint` 放置图标按钮。
- Button 使用 `.buttonStyle(.plain)`。
- hover 时显示圆角背景和 tooltip。
- 点击设置 `activeNoteAnchor`，打开 `NoteReviewPopoverView`。

## 9. 笔记回顾浮层

`NoteReviewPopoverView` 内容：

```swift
VStack(spacing: 0) {
    header // note.text + "笔记" + close
    ScrollView {
        originalText
        ForEach(notes) { note in
            noteContent
            createdAt
        }
    }
    footer // "打开右侧笔记" / "关闭"
}
```

- 使用同一 `DraggableReadingOverlay`。
- body 最大高度遵循窗口 70%。
- `打开右侧笔记` 通过 `ReadingInspectorModel.mode = .notes` 和 `isVisible = true` 实现；定位到具体卡片可作为后续增强。

## 10. 测试计划

### 10.1 单元测试

新增 `ReadingOverlayPlacementTests`：

- below 有空间时选择 below，且不遮挡 anchor。
- below 无空间、above 有空间时选择 above。
- 上下都不足时选择 leastOverlap。
- overlay 大于容器时 origin 被 safeInset clamp。
- 手动拖动位置在窗口 resize 后仍被 clamp 到可见区域。

### 10.2 手工验证

1. 选择单行文本 → 添加笔记 → 默认浮层不遮挡选区。
2. 选择多行文本 → 添加笔记 → 默认浮层不遮挡整体选区主体。
3. 拖动浮层到四个角落 → 浮层不会完全跑出窗口。
4. 输入超长笔记和长原文 → 浮层内部可滚动，底部按钮固定。
5. 保存笔记 → 原文旁出现 note 图标。
6. 点击 note 图标 → 弹出笔记回顾浮层。
7. 多条笔记同一选区 → 单个图标打开后展示多条内容。
8. AI 解释 / 导读超长 → 内容可滚动到底部。
9. 缩放 PDF、切换页、打开 / 关闭 Inspector → 图标位置刷新且不崩溃。

### 10.3 回归检查

- `xcodebuild` 编译 LumenPDF target。
- 如本地存在 Swift 测试 target，运行新增 placement tests。
- Rust 层未改动，本迭代不要求 `cargo test` 作为阻塞项；发布前仍可跑全量检查。

## 11. 风险与对策

| 风险 | 对策 |
| --- | --- |
| PDFKit 坐标转换在不同缩放 / rotation 下偏移 | 使用 PDFView 官方 convert API，手工覆盖缩放、滚动、双页模式。 |
| 图标过多影响阅读 | 对同一选区分组，默认尺寸小，hover 才增强。 |
| ScrollView 与 PDFView 滚动冲突 | 浮层内容区优先消费滚动事件，必要时使用 NSViewRepresentable 限制事件透传。 |
| 拖动手势与 TextEditor 冲突 | 仅 header 绑定 DragGesture，正文不绑定拖动。 |
| 旧笔记 boundsStr 缺失或异常 | 转换失败时跳过图标，不影响笔记列表和划线恢复。 |
