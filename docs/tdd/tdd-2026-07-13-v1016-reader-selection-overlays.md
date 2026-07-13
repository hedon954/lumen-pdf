# LumenPDF — 阅读选择控件优化 TDD

**版本**: v1.0.16 · **日期**: 2026-07-13

对应 PRD：`docs/prd/prd-2026-07-13-v1016-reader-selection-overlays.md`

## 1. 技术结论

本迭代仅调整 SwiftUI / PDFKit 阅读层，不修改 Rust、UniFFI、数据库 schema 或持久化格式。

笔记按钮位置由 UI 无关的纯策略计算。选择操作栏则恢复单一 SwiftUI 所有权：`PDFReaderView` 负责生成选区信息和根坐标锚点，`ContentView` 持有唯一展示状态，并在整个 `NavigationSplitView` 之上渲染操作栏。

操作栏不使用 `NSPanel`。AppKit 只保留一个窄桥接，用于观察主窗口内鼠标按下事件；监听器与操作栏视图实例共同创建和销毁。

## 2. 根因

旧方案试图通过独立面板突破阅读列裁切，但同时引入第二套：

- 窗口与坐标空间。
- 激活状态和焦点。
- 内外部点击事件路由。
- attach、update、dismiss 和 teardown 生命周期。

PDF 缩放会更新 PDFKit 内部视图和选区状态，但独立面板及其事件监听不一定同步销毁，因此不同局部修复分别造成操作栏不显示、阴影异常、多个实例残留，以及缩放后外部点击无法关闭。

根因不是单个 `zIndex` 或关闭条件错误，而是窗口内上下文控件被错误拆成了第二个窗口所有权边界。

## 3. 影响范围

| 文件 / 模块 | 职责 |
| --- | --- |
| `LumenPDF/Reader/PDFReaderModels.swift` | `NoteAnchorPlacementPolicy` 纯定位策略与结果模型。 |
| `LumenPDF/Reader/PDFKitView.swift` | 收集划线矩形和页面正文行矩形，生成笔记按钮锚点。 |
| `LumenPDF/Reader/SelectionActionBar.swift` | 操作栏状态、根层渲染、窗口边界限制和外部点击监听。 |
| `LumenPDF/Views/PDFReaderView.swift` | 将选区局部坐标转换为根坐标，并转发具体业务动作。 |
| `LumenPDF/Views/ReadingInspector/ReadingWorkspaceView.swift` | 向阅读器传递根层操作栏模型，并在文档切换时清理状态。 |
| `LumenPDF/Views/ContentView.swift` | 持有唯一操作栏模型，在整个 split view 之上渲染。 |
| `LumenPDF/LumenPDF.xcodeproj/project.pbxproj` | 将新源文件加入应用 target。 |
| `LumenPDF/Info.plist` | 启动 v1.0.16，版本更新为 `1.0.16` / `16`。 |
| `CLAUDE.md` | 固化 SwiftUI/AppKit 展示边界与 UI 运行时验收约束。 |

## 4. 笔记按钮定位

### 4.1 输入

```swift
NoteAnchorPlacementPolicy.place(
    lineRects: [CGRect],
    textRects: [CGRect],
    containerRect: CGRect,
    buttonSize: CGFloat,
    gap: CGFloat
)
```

- `lineRects`：当前划线的单行矩形，按阅读顺序排列。
- `textRects`：当前页所有正文行矩形；同页的多条笔记复用缓存结果。
- `containerRect`：当前 PDF 阅读区域，预留最小边界间距。

### 4.2 候选与约束

策略依次评估：

1. 最后一行右侧。
2. 整体选区上方。
3. 整体选区下方。
4. 第一行左侧。

候选按钮矩形必须被 `containerRect` 完整包含，且不得与任一 `textRects` 相交。第一个满足条件的候选即为结果。

### 4.3 fallback

当选择位于密集段落中间、四个候选都与正文相交或超出边界时，将按钮中心放到最后一行末端右侧并向上偏移，使按钮尽量进入两行之间。最后再按按钮半径限制到阅读区域内。

## 5. 操作栏所有权

### 5.1 状态流

```text
PDFKitView 产生选区
    ↓
PDFReaderView 保存业务所需 SelectionInfo
并把局部 anchor 转换为阅读窗口根坐标
    ↓
SelectionActionBarModel 保存唯一 presentation 和临时动作闭包
    ↓
ContentView 在 NavigationSplitView 根层 overlay 中渲染
```

`SelectionActionBarPresentation` 只包含会话 ID、根坐标锚点和是否已有笔记。新 `present` 调用替换旧 presentation，因此不会出现多实例。

### 5.2 坐标与边界

- `ContentView` 声明命名根坐标空间。
- `PDFReaderView` 读取自身在根坐标空间中的 frame，把 PDFKit 返回的局部锚点转换为根坐标。
- `SelectionActionBarOverlay` 测量操作栏实际尺寸后，将中心点限制在整个窗口可见区域，而不是 PDF 阅读列内。
- 操作栏位于 `NavigationSplitView` 根层 overlay，因此自然高于左右侧栏。

### 5.3 动作生命周期

`SelectionActionBarModel.perform` 先清除 presentation 和动作闭包，再执行临时业务闭包。这样翻译、解释或笔记编辑打开其他浮层时，不会留下旧操作栏。

文档切换、主功能页切换以及应用失去激活状态都会显式调用 `dismiss()`。

## 6. 外部点击监听

`WindowOutsideClickMonitor` 是操作栏背景中的透明 `NSViewRepresentable`：

- 通过 `NSEvent.addLocalMonitorForEvents` 观察当前应用的左右键按下事件。
- 将窗口坐标转换到操作栏背景 view，判断点击是否落在操作栏实际 bounds 内。
- 内部点击原样放行；外部点击异步调用 `dismiss()`，同时返回原事件，不吞掉 PDF、目录或 Inspector 的点击。
- `PassthroughView.hitTest` 返回 `nil`，桥接 view 本身不抢占 SwiftUI 按钮点击。
- `dismantleNSView` 确定移除本地事件监听器。

监听器属于根层操作栏，而不是 PDFKit 的 document view 或 scroll view，因此 PDF 缩放、滚动或内部视图替换不会中断关闭语义。

## 7. 视觉

操作栏使用 `regularMaterial`、Capsule 细描边和固定内容尺寸，不添加 shadow。透明区域只由主窗口 SwiftUI 合成，不存在独立面板的矩形投影或底色。

## 8. 工程约束

- 窗口内上下文控件优先提升到共同 SwiftUI 祖先，不使用 `NSPanel` 绕过 split view 裁切。
- 位置算法保持为 UI 无关纯函数。
- AppKit 事件监听必须有明确所有者，并在 dismantle 路径确定移除。
- 操作栏只有一个状态源；不得在 `PDFReaderView` 再保留并行的显示状态。
- 编译成功不等于交互验收；无法运行原生 UI 时必须明确说明未完成运行时验证。

## 9. 验证

### 自动检查

```bash
git diff --check
make gen-project
xcodebuild \
  -project LumenPDF/LumenPDF.xcodeproj \
  -scheme LumenPDF \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

本迭代未修改 Rust。仓库没有 Swift XCTest target，因此原生 PDFKit 交互由用户人工验收。

### 人工验收

1. 在段尾、段首、页边和密集句中间创建笔记，检查按钮空白避让和 fallback。
2. 在左右侧栏边缘选择文本，检查操作栏完整显示且无阴影。
3. 点击 PDF、左侧目录、右侧 Inspector 和工具栏，检查操作栏关闭且原点击继续生效。
4. 操作栏出现后缩放或滚动 PDF，再点击其他区域，检查操作栏仍关闭。
5. 连续选择两段文本，检查始终只有一个操作栏且按钮作用于最新选区。
6. 切换文档、切换主功能页和停用应用，检查操作栏被清理。

## 10. 风险与后续

| 风险 | 当前处理 |
| --- | --- |
| PDF 页面正文行提取增加锚点计算成本 | 同一轮计算按页缓存正文行矩形。 |
| 密集文本中不存在完全无遮挡位置 | 使用末字右上方 fallback，并限制在阅读区域内。 |
| 操作栏显示期间缩放导致原锚点过时 | 当前会话保持位置，下一次窗口内点击统一关闭；新选区生成新根坐标。 |
| 后续重新引入窗口级 workaround | `CLAUDE.md` 固化展示边界和运行时验收门槛。 |
