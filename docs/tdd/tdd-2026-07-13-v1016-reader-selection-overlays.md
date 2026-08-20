---
version: v1.0.16
date: 2026-07-13
prd: prd/prd-2026-07-13-v1016-reader-selection-overlays.md
predecessor:
  - tdd/tdd-2026-07-10-note-overlay-optimization.md
successor:
  - tdd/tdd-2026-08-05-viewport-restore-overlay-drag.md
---

# LumenPDF — 阅读选择控件与窗口延续性优化 TDD

## 1. 技术结论

本迭代仅调整 SwiftUI / PDFKit 阅读层，不修改 Rust、UniFFI、数据库 schema 或持久化格式。

笔记按钮位置由 UI 无关的纯策略计算。选择操作栏则恢复单一 SwiftUI 所有权：`PDFReaderView` 负责生成选区信息和根坐标锚点，`ContentView` 持有唯一展示状态，并在整个 `NavigationSplitView` 之上渲染操作栏。

操作栏不使用 `NSPanel`。AppKit 只保留一个窄桥接，用于观察主窗口内鼠标按下事件；监听器与操作栏视图实例共同创建和销毁。

主窗口使用系统 frame autosave 名称作为事实来源，并兼容已有 `main_window_frame` 数据。窗口挂载视图通过 `viewDidMoveToWindow` 获取真实 `NSWindow`，在下一轮主线程恢复 frame，随后才开始监听 resize、move、close 和 terminate。稳定布局状态通过 `UserDefaults` 分别持久化，瞬时浮层不恢复。

## 2. 根因

旧方案试图通过独立面板突破阅读列裁切，但同时引入第二套：

- 窗口与坐标空间。
- 激活状态和焦点。
- 内外部点击事件路由。
- attach、update、dismiss 和 teardown 生命周期。

PDF 缩放会更新 PDFKit 内部视图和选区状态，但独立面板及其事件监听不一定同步销毁，因此不同局部修复分别造成操作栏不显示、阴影异常、多个实例残留，以及缩放后外部点击无法关闭。

根因不是单个 `zIndex` 或关闭条件错误，而是窗口内上下文控件被错误拆成了第二个窗口所有权边界。

窗口恢复问题同样来自所有权和时序不完整：旧逻辑只监听 `didEndLiveResize`，无法覆盖窗口缩放按钮和其他非拖拽 resize；异步背景视图不保证在 SwiftUI 首轮窗口布局之后恢复；左侧目录只有临时 `@State` 和固定 ideal width，退出后必然丢失。进一步地，文档、页码和单一纵向 offset 不是完整的 PDF 阅读现场；PDFKit 的自动/手动缩放模式、缩放比例和横向平移如果没有统一保存，重开后仍会看到不同大小和不同区域的正文。

## 3. 影响范围

| 文件 / 模块 | 职责 |
| --- | --- |
| `LumenPDF/Reader/PDFReaderModels.swift` | `NoteAnchorPlacementPolicy` 纯定位策略与结果模型。 |
| `LumenPDF/Reader/ReadingRestorationState.swift` | 完整、可版本化的阅读现场结构，旧偏好迁移以及唯一持久化管理器。 |
| `LumenPDF/Reader/PDFKitView.swift` | 收集笔记按钮锚点，并按文档保存、恢复 PDFKit 缩放模式、比例与横纵视口偏移。 |
| `LumenPDF/Reader/SelectionActionBar.swift` | 操作栏状态、根层渲染、窗口边界限制和外部点击监听。 |
| `LumenPDF/Views/PDFReaderView.swift` | 将选区局部坐标转换为根坐标，并转发具体业务动作。 |
| `LumenPDF/Views/ReadingInspector/ReadingWorkspaceView.swift` | 向阅读器传递根层操作栏模型，并在文档切换时清理状态。 |
| `LumenPDF/Views/ContentView.swift` | 持有唯一操作栏模型，在整个 split view 之上渲染。 |
| `LumenPDF/App/LumenPDFApp.swift` | 在真实窗口挂载后恢复 frame，完整观察保存时机，并处理多显示器可见区域。 |
| `LumenPDF/App/AppState.swift` | 持久化并恢复主功能页，隔离 UI 测试启动参数。 |
| `LumenPDF/Views/ReadingInspector/ReadingInspectorModel.swift` | 继续持久化右侧 Inspector 显示状态、宽度和模式。 |
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

## 8. 窗口与布局恢复

### 8.1 主窗口挂载与恢复顺序

`WindowFramePersistence.WindowAttachmentView` 在 `viewDidMoveToWindow` 中上报真实 `NSWindow`。Coordinator 切换窗口时先清理旧观察者，再在下一轮主线程执行：

1. 设置 `LumenPDFMainWindow` frame autosave name。
2. 显式调用 `setFrameUsingName` 恢复系统 autosave 数据。
3. 系统数据不存在时读取旧版 `main_window_frame`，完成兼容迁移。
4. 使用当前 `NSScreen.visibleFrame` 修正位置和尺寸。
5. 恢复完成后注册窗口事件，防止首轮布局把默认 frame 提前覆盖到持久化数据。

### 8.2 保存覆盖面

Coordinator 观察：

- `NSWindow.didResizeNotification`：覆盖手动拖拽、缩放按钮和程序化 resize。
- `NSWindow.didMoveNotification`：保存窗口位置。
- `NSWindow.didExitFullScreenNotification`：退出全屏后保存普通窗口 frame。
- `NSWindow.willCloseNotification` 与 `NSApplication.willTerminateNotification`：补齐关闭和退出路径。
- `NSWindow.willMiniaturizeNotification`：在窗口隐藏前保存普通 frame，并冻结左右栏宽度写入。
- `NSWindow.didDeminiaturizeNotification`：窗口重新显示后进入布局恢复阶段，重新应用保存的分隔线位置，稳定后再开放宽度采集。

全屏期间不把全屏 frame 写入普通窗口记录。观察 token 由 Coordinator 持有，并在窗口切换、view dismantle 和 deinit 时移除。

### 8.3 多显示器约束

`MainWindowFramePolicy` 选择与保存 frame 相交面积最大的当前显示器；完全不相交时回退到主显示器。窗口尺寸限制在目标 `visibleFrame` 内，origin 同时 clamp，确保断开外接显示器后仍能看到完整窗口。

### 8.4 稳定布局状态

`ReadingRestorationState` 是稳定阅读现场的唯一持久化结构，包含：

- 主窗口 frame。
- 左侧目录显示状态和实际宽度。
- 右侧 Inspector 显示状态、实际宽度和模式。
- 主功能页与最后打开的文档。
- 以文件路径隔离的 PDF 页码、`autoScales`、`scaleFactor`、归一化横向偏移和归一化纵向偏移。

`ReadingRestorationStore` 统一加载、校验、修改和编码整个结构。`ContentView`、`ReadingInspectorModel`、窗口 bridge 和 PDFKit coordinator 只向它报告稳定状态变化，不再直接维护各自的窗口/布局 `UserDefaults` 键。首次读取新结构时，从旧键和旧 PDF viewport 数据完成一次兼容迁移。

### 8.5 PDF 视口恢复顺序

PDFKit 在文档赋值、窗口 frame 恢复和内部 scroll view 布局期间可能多次重算页面尺寸，因此不能只调用一次 `go(to:)`。恢复流程为：

1. 读取目标文档的完整视口状态；旧数据缺失时保留现有页码与纵向 offset fallback。
2. 先恢复自动缩放模式，或关闭 `autoScales` 后限制并设置手动 `scaleFactor`。
3. 跳转到保存页码，再按布局后的 document bounds 恢复归一化横纵偏移。
4. 在后续主线程布局阶段重复校准偏移，最后解除恢复锁并重新启用滚动持久化。

缩放、滚动、最小化、显式保存和应用退出都会刷新完整视口。恢复期间产生的 PDFKit 中间通知不得覆盖持久化状态。

### 8.6 分栏宽度恢复锁

SwiftUI 的 `GeometryReader` 会在首轮窗口和 split view 尚未稳定时上报临时宽度；如果恢复锁忽略了这次回调，解锁后尺寸未变化又不会再次触发。前一种情况会覆盖正确值，后一种情况会让宽度永远停留在默认值。

`ReadingRestorationStore.isRestoringLayout` 为真时：

1. 左侧 `NavigationSplitView` 暂时收敛到已保存宽度，`SplitPaneWidthObserver` 负责读取并恢复其原生 pane。
2. 右侧 Inspector 的 frame 与自有 divider 直接绑定 `ReadingInspectorModel.width`；拖拽修改的就是持久化状态，不再经过几何测量。
3. 主窗口 frame 应用并等待 split view 布局稳定后，窗口 coordinator 结束恢复阶段。
4. 两侧恢复正常 min/max 约束和用户拖拽，后续真实宽度变化再写回统一状态。

SwiftUI preference 在恢复锁期间可能只上报一次；如果该值被正确忽略，解锁后尺寸未变化便不会再次触发，从而让持久化宽度永远停留在默认值。进一步验证发现，`HSplitView` 内的观察视图还可能只能读到 Inspector 内容的最小宽度 `300`，而不是用户移动后的 divider 位置。右栏因此改成显式 frame + divider binding，消除私有层级探测；左栏保留窄原生观察器。窗口最小化、关闭与退出期间 store 继续保持恢复锁，避免隐藏动画和 teardown 布局污染最后一次可见快照。

### 8.7 Keychain 与签名闭环

`KeychainService` 只读写 `com.LumenPDF.app` 的 data-protection 条目，并禁止查询过程弹出认证 UI。旧 `reinstall-stable` / file-based 条目仅作为无 UI 的一次性迁移来源；迁移成功后删除，失败则等待用户在设置页重新输入。

`package-dmg.sh` 默认使用 ad-hoc，或接受显式指定的签名身份。最终 bundle 先签 `liblumen_pdf_core.dylib`，再以同一身份和 `LumenPDF.entitlements` 签主应用，不使用 `codesign --deep` 代替签名顺序。签名后同时执行 strict verification 与 sandbox entitlement 检查。

Release workflow 复用默认 ad-hoc 打包路径，不因缺少签名身份阻塞发布。

## 9. 工程约束

- 窗口内上下文控件优先提升到共同 SwiftUI 祖先，不使用 `NSPanel` 绕过 split view 裁切。
- 位置算法保持为 UI 无关纯函数。
- AppKit 事件监听必须有明确所有者，并在 dismantle 路径确定移除。
- 操作栏只有一个状态源；不得在 `PDFReaderView` 再保留并行的显示状态。
- 编译成功不等于交互验收；无法运行原生 UI 时必须明确说明未完成运行时验证。
- 只恢复稳定、用户主动调整的阅读布局，包括每个 PDF 的缩放与平移视口；不恢复选择操作栏、翻译或笔记编辑等瞬时 UI。
- 稳定阅读现场只能由 `ReadingRestorationStore` 持久化；禁止重新增加组件私有的窗口或分栏偏好键。
- 窗口恢复必须覆盖非 live resize、应用退出和多显示器变化，不能只验证拖拽窗口边缘这一条路径。

## 10. 验证

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
7. 调整主窗口位置和大小后退出并重开，检查 frame 恢复。
8. 使用绿色缩放按钮或系统窗口平铺改变尺寸后退出，检查非 live resize 也被保存。
9. 调整并隐藏左右栏后退出，检查显示状态、宽度和 Inspector 模式恢复。
10. 切换主功能页，并对 PDF 手动缩放、横向平移和纵向滚动后退出，检查主标签、文档、缩放比例与可见区域恢复。
11. 在外接显示器保存窗口后断开显示器，检查重开窗口完整落在当前可见区域。
12. 从已有版本直接升级，检查旧窗口、分栏和 PDF 视口偏好迁移到统一状态后仍保持一致。
13. 分别调整左右栏宽度，最小化后从 Dock 恢复，检查两个 divider 仍位于最小化前的位置。

## 11. 风险与后续

| 风险 | 当前处理 |
| --- | --- |
| PDF 页面正文行提取增加锚点计算成本 | 同一轮计算按页缓存正文行矩形。 |
| 密集文本中不存在完全无遮挡位置 | 使用末字右上方 fallback，并限制在阅读区域内。 |
| 操作栏显示期间缩放导致原锚点过时 | 当前会话保持位置，下一次窗口内点击统一关闭；新选区生成新根坐标。 |
| SwiftUI 首轮布局覆盖已恢复 frame | 等待真实窗口挂载后的下一轮主线程恢复，再注册保存观察者。 |
| PDFKit 文档或窗口布局覆盖已恢复视口 | 按缩放、页码、横纵偏移的顺序恢复，并在内部布局完成后分阶段校准。 |
| 首轮 Geometry 测量覆盖已保存栏宽 | 恢复阶段把两侧栏锁定到保存宽度并禁止测量写回，布局稳定后再解除。 |
| 外接显示器断开导致窗口不可见 | 按当前屏幕交集选择目标屏幕并把完整 frame 限制到 `visibleFrame`。 |
| UI 测试改变上次主功能页 | 测试参数覆盖期间关闭主标签偏好写入。 |
| 后续重新引入窗口级 workaround | `CLAUDE.md` 固化展示边界和运行时验收门槛。 |
