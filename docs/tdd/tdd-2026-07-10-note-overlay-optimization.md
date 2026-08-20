# LumenPDF — 阅读浮层与划线回顾优化 TDD

**版本**: v1.0.15 · **日期**: 2026-07-10

## 文档关系

- 对应 PRD：[`prd-2026-07-10-note-overlay-optimization.md`](../prd/prd-2026-07-10-note-overlay-optimization.md)
- 前序：[`tdd-2026-07-04-v1014-refactor-automation.md`](tdd-2026-07-04-v1014-refactor-automation.md)
- 后续：[`tdd-2026-07-13-v1016-reader-selection-overlays.md`](tdd-2026-07-13-v1016-reader-selection-overlays.md) · [浮窗位置稳定 TDD](tdd-2026-08-20-note-autosave-overlay-stability.md)
- 索引：[`docs/README.md`](../README.md)

## 1. 技术结论

本迭代仅调整 SwiftUI / PDFKit 阅读层，不修改 Rust、UniFFI、数据库 schema 或持久化格式。

外围窗口逻辑集中到泛型组件 `ReadingOverlayWindow`。翻译、添加/追加笔记、笔记回顾只提供各自的 header、content、footer；内容测量、自适应高度、80% 高度上限、滚动、避让、拖动、缩放、窗口边界和样式全部由公共外壳处理。

这次收敛替代了原先分散在 `TranslationBubble`、`UnderlineNoteDraftView` 和 `PDFReaderView` 中的多套窗口状态，避免后续只修复某一种浮层。

## 2. 影响范围

| 文件 / 模块 | 实际职责 |
| --- | --- |
| `LumenPDF/Reader/ReadingOverlayWindow.swift` | 公共窗口外壳：测量、自适应高度、滚动、定位、拖动、可选缩放、样式和关闭。 |
| `LumenPDF/Reader/PDFReaderModels.swift` | 选区/笔记锚点模型与纯定位策略；支持独立的水平、垂直安全边距。 |
| `LumenPDF/Reader/UnderlineNoteDraftView.swift` | 只提供笔记编辑 header/content/footer，不持有外围拖动和滚动实现。 |
| `LumenPDF/Views/TranslationBubble.swift` | 保留翻译内容、发音与保存动作；移除本地窗口、测量、拖动和缩放代码。 |
| `LumenPDF/Views/PDFReaderView.swift` | 组合三类浮层，传入阅读区域尺寸和锚点；管理笔记图标及回顾业务状态。 |
| `LumenPDF/Views/ReadingInspector/ReadingWorkspaceView.swift` | 实现“打开右侧笔记”：刷新数据、切换 `.notes`、显示 Inspector。 |
| `LumenPDF/LumenPDF.xcodeproj/project.pbxproj` | 将新公共窗口源文件加入 LumenPDF target。 |
| `LumenPDF/Info.plist` | 版本更新为 `1.0.15` / `15`。 |

## 3. 组件边界

### 3.1 公共配置

`ReadingOverlayWindowConfiguration` 提供外围行为参数：

```swift
struct ReadingOverlayWindowConfiguration {
    let width: CGFloat
    let initialContentHeight: CGFloat
    let minimumContentHeight: CGFloat
    let isResizable: Bool
    let minimumSize: CGSize
    let maximumSize: CGSize
    let dismissesOnBackgroundTap: Bool
    let showsFooter: Bool
}
```

- `initialContentHeight` 只用于首轮内容尚未完成测量时的稳定布局，不是固定高度。
- `minimumContentHeight` 防止加载态或输入态过度收缩。
- `isResizable` 当前只由翻译浮层启用。
- 业务视图不直接访问公共外壳的拖动、缩放或测量状态。

### 3.2 泛型内容槽位

```swift
struct ReadingOverlayWindow<Header: View, Content: View, Footer: View>: View {
    let anchorRect: CGRect
    let availableSize: CGSize
    let resetID: AnyHashable
    let configuration: ReadingOverlayWindowConfiguration
    let onDismiss: () -> Void

    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
}
```

公共外壳固定窗口骨架：

```text
header（固定、可拖动）
divider
content（高度自适应，超限滚动）
divider
footer（固定、可选）
```

## 4. 高度与滚动算法

### 4.1 高度约束

```swift
maximumWindowHeight = availableSize.height * 0.8
verticalSafeInset = availableSize.height * 0.1

maximumContentHeight = maximumWindowHeight
    - measuredHeaderHeight
    - measuredFooterHeight
    - dividerHeight

automaticContentHeight = min(
    max(measuredContentHeight, minimumContentHeight),
    maximumContentHeight
)
```

因此窗口总高度遵循：

```text
min(header + content + footer + dividers, availableHeight × 80%)
```

短内容按真实高度收缩；长内容达到 80% 后外层不再增高。高度上限作用于整个窗口，而不是只作用于正文。

### 4.2 稳定布局树与滚动结构

- 正文始终使用同一个 `ScrollView`，不会在自然 View 和 ScrollView 两套布局树之间切换。
- `onGeometryChange` 读取 ScrollView 内容的自然高度，viewport 高度使用 `automaticContentHeight`。
- 内容未超过 `maximumContentHeight` 时，viewport 随自然高度持续增高，因此外层窗口同步增高。
- 内容超过 `maximumContentHeight` 后，viewport 保持在上限，外层窗口停止增高，正文继续在同一个 ScrollView 内滚动。
- 用户手动缩放翻译窗口后，正文占用 header/footer 之外的剩余空间。
- header/footer 不进入 ScrollView，保证标题和主操作始终可见。
- `.scrollIndicators(.automatic)` 仅在内容实际溢出时呈现滚动反馈。
- 首次布局将 `ReadingOverlayPlacement` 写入窗口状态；后续内容测量只按该方向重新计算 origin 并 clamp，不再重新比较四个候选方向。

### 4.3 流式内容

翻译流式输出会持续改变 `measuredContentHeight`：

1. 未达到上限时，正文自然高度增大，ScrollView viewport 和窗口同步增高。
2. 达到上限后，viewport 与窗口高度保持不变。
3. 后续内容继续写入同一 ScrollView，通过滚轮或触控板查看。
4. 窗口保持加载态首次选定的避让方向，避免完成态因候选方向重评而横向跳位。

## 5. 定位、避让与边界

### 5.1 输入模型

```swift
struct ReadingOverlayPlacementInput: Equatable {
    let anchorRect: CGRect
    let overlaySize: CGSize
    let containerSize: CGSize
    let preferredGap: CGFloat
    let horizontalSafeInset: CGFloat
    let verticalSafeInset: CGFloat
}
```

保留接收单个 `safeInset` 的兼容初始化方法，由其同时填充水平和垂直边距。

### 5.2 候选算法

1. 生成 below、above、trailing、leading 四个候选 origin。
2. 使用独立的水平/垂直安全边距将候选 clamp 到阅读区域。
3. 计算候选窗口与 `anchorRect` 的交集面积。
4. 按 below → above → trailing → leading 选择第一个无重叠候选。
5. 全部重叠时选择交集面积最小的位置，并返回 `.leastOverlap`。

当窗口高度达到 80% 时：

```text
minY = 10% × availableHeight
maxY = availableHeight - 80% × availableHeight - 10% × availableHeight
     = minY
```

因此最大高度窗口自然位于上下各留 10% 的垂直区域内。

### 5.3 锚点来源

- 翻译：`TranslationBubbleRequest.selectionAnchorRect`。
- 添加/追加笔记：`UnderlineNoteDraft.anchorRect`；缺失时根据 `menuAnchor` 构造 fallback rect。
- 笔记回顾：`NoteAnchorPosition.anchorRect`。

`PDFReaderView` 将 `GeometryReader` 的阅读区域尺寸作为 `availableSize` 传给三类窗口，避免各浮层再建立不同坐标空间。

公共外壳监听 `availableSize` 变化：自动尺寸重新计算 80% 上限；手动缩放尺寸重新 clamp 到新的可用宽高，窗口中心也重新限制在安全区域内。

## 6. 拖动与缩放

### 6.1 标题栏拖动

公共 header 背景使用窄范围 AppKit capture view：

- `mouseDown` 记录 window location。
- `mouseDragged` 计算增量并更新 `customCenter`。
- 每次移动后调用公共 clamp，避免窗口离开可见区域。
- 新 `resetID` 到来时清空手动位置和测量状态。

正文和 footer 不绑定拖动，因此不会抢占文本选择、输入、滚动和按钮点击。

### 6.2 翻译窗口缩放

公共外壳按配置为四条边和四个角提供 resize capture：

- 宽度限制：业务 `minimumSize/maximumSize` 与可用宽度共同决定。
- 高度限制：业务最小尺寸与 `availableSize.height * 0.8` 共同决定。
- 从 leading/top 缩放时同步修正窗口中心，保持对侧边缘稳定。
- 缩放完成后的中心再次 clamp。

笔记编辑和笔记回顾当前 `isResizable = false`，但仍共享其他窗口行为。

## 7. 三类浮层接入

### 7.1 翻译浮层

`TranslationBubble` 删除以下私有实现：

- 独立的 center/offset/custom size 状态。
- 独立的内容高度测量和 ScrollView 分支。
- 独立的 AppKit drag/resize capture。
- 独立的 cursor 和 resize edge helper。

它只保留翻译渲染、加载态、错误态、发音、保存和删除逻辑，并通过 `showsFooter` 控制底部操作区。

`PDFReaderView` 统一管理层级和互斥：选择操作条、笔记图标、笔记编辑、笔记回顾和翻译窗口使用明确 zIndex；打开任一窗口型浮层时关闭其他窗口型浮层，避免点击穿透和窗口重叠。

### 7.2 添加/追加笔记

`UnderlineNoteDraftView` 只组织：

- header：标题和关闭按钮。
- content：原文预览和 `TextEditor`。
- footer：提示、取消、保存。

外围拖动、定位和滚动不再通过 `AnyGesture` 由 `PDFReaderView` 注入。

输入校验保持两层防线：

- `UnderlineNoteDraftView` 通过 `trimmedNoteText` 计算 `canSave`，空白内容禁用保存按钮及默认回车动作。
- `PDFReaderView` 的 `onSave` 再次 trim 并 guard，避免后续调用绕过 View 校验。

创建笔记的 `saveUnderlineNote` 只接受非空笔记；“取消笔记”改走独立的 `removeUnderlineNote`，不再复用空 `noteText` 触发删除。这样“划线”保持为独立 free annotation，“笔记”始终对应有实际内容的 `NoteEntry`。

### 7.3 笔记回顾

`NoteReviewPopoverView` 使用同一公共外壳展示原文和按创建时间排列的笔记。

“打开右侧笔记”回调交给 `ReadingWorkspaceView`：

```swift
appState.refreshNotes()
inspectorModel.mode = .notes
if !inspectorModel.isVisible {
    setInspectorVisible(true)
}
```

回调完成后，`PDFReaderView` 清除 `activeNoteReview`，关闭回顾浮层。

### 7.4 Reading Inspector 删除

`ReadingWordsPanel` 在单词卡右上角提供 destructive 垃圾桶按钮。删除顺序为：

1. `ReaderPersistence.deleteVocabulary(id:)` 删除词条。
2. `postRemoveHighlight` 移除 PDF 关联高亮。
3. `appState.refreshVocabulary()` 刷新 Inspector。

`ReadingInspectorNoteGroup` 保留聚合组内的全部 `sourceIds`。`ReadingNotesPanel` 删除卡片时逐条执行 `deleteNote` 和 `postRemoveUnderlineNote`，随后统一刷新笔记数据；因此同一选区的聚合卡片不会留下孤立划线或快捷图标。

## 8. 笔记图标与数据刷新

- `PDFKitView` 根据当前文档笔记的 `pageIndex/boundsStr` 计算 SwiftUI anchor。
- `PDFKitView.Coordinator` 递归定位 PDFKit 内部 `NSScrollView`，监听其 `NSClipView.boundsDidChangeNotification`；该通知覆盖拖动、惯性和程序化滚动。
- PDF 缩放通过 `PDFViewScaleChanged` 触发同一锚点重算；PDFKit 替换内部 scroll view 时重新挂载观察者。
- `PDFReaderView` 按页码与 bounds 对同一选区的笔记分组。
- `NoteAnchorOverlayView` 在原文旁绘制 `note.text` 按钮。
- 点击图标创建 `ActiveNoteReview`，回顾浮层消费已经排序的笔记数组。
- `.refreshNotesList` 通知触发 `appState.refreshNotes()`，保证保存、追加和删除后的入口状态更新。

## 9. 工程约束

- SwiftUI View 不直接调用 `BridgeService.shared`。
- 位置算法保持为 UI 无关的纯函数。
- 公共窗口负责外围行为，业务内容不得复制窗口状态。
- AppKit 仅用于 SwiftUI 原生手势难以稳定覆盖的 header drag 和 edge resize capture。
- 新源文件通过 `project.yml` 的 Reader sources 纳入工程，并运行 `make gen-project` 更新 Xcode project。

## 10. 验证

### 自动检查

```bash
git diff --check
xcodebuild \
  -project LumenPDF/LumenPDF.xcodeproj \
  -scheme LumenPDF \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

本迭代未修改 Rust，不要求额外运行 Rust 测试。项目当前没有 Swift XCTest target，因此定位算法仍以纯函数结构和人工场景验收为主。

### 人工验收

1. 短翻译、短笔记回顾：窗口随内容收缩。
2. 长翻译、长笔记回顾：最高 80%，上下各留 10%，正文可滚动到底。
3. 流式翻译：到达上限后窗口不继续增高。
4. 单行和多行选区：翻译与添加笔记默认避让选区。
5. 拖动到四边和四角：窗口仍保持可见。
6. 缩放翻译窗口：最大高度不超过 80%。
7. 点击笔记图标：打开回顾浮层。
8. 点击“打开右侧笔记”：Inspector 打开并切换到“笔记”。
9. 新建和追加笔记输入为空或仅有空白字符：保存按钮禁用，默认回车不提交，不产生笔记记录。
10. 将带笔记图标的划线滚出视口后再滚回：图标重新出现，位置仍跟随划线末端。
11. 删除右侧单词卡：卡片、高亮和词条数据同步消失。
12. 删除右侧笔记卡：聚合组内笔记、划线和快捷图标同步消失。

原生界面场景由用户实际验证，自动化只做代码格式与 macOS 编译检查。

## 11. 风险与后续

| 风险 | 当前处理 |
| --- | --- |
| `TextEditor` 自身滚动与公共 ScrollView 嵌套 | 保留 TextEditor 最小高度和焦点，人工覆盖长输入场景。 |
| 浮层内容测量在首次渲染时尚未完成 | 使用 `initialContentHeight` 提供首帧稳定尺寸，测量后自动收敛。 |
| PDF 缩放、旋转或双页模式导致锚点偏差 | 锚点继续使用 PDFKit 官方坐标转换；转换失败时跳过图标或采用 fallback。 |
| 浮层达到最大高度后与选区无法完全分离 | 四方向候选均失败时选择重叠面积最小的位置，用户仍可拖动。 |
| 后续新浮层再次复制外围逻辑 | 新的窗口型阅读浮层必须接入 `ReadingOverlayWindow`。 |
