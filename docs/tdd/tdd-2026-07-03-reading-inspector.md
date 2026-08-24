---
version: v1.0.13
date: 2026-07-03
prd: prd/prd-2026-07-03-reading-inspector.md
prev: tdd/tdd-2026-07-02-reading-context-sidebar.md
next: tdd/tdd-2026-07-04-v1014-refactor-automation.md
---

# LumenPDF — 阅读 Inspector TDD

## 1. 技术结论

本迭代把 AI 导读从 `TranslationBubble` 的长期悬浮聊天窗口迁入右侧 `ReadingInspectorView`。PDFReader 继续负责 PDFKit 显示、选区和标注；Inspector 负责阅读辅助 UI、导读消息流、保存 AI 回复和当前 PDF 笔记展示。

目标不是一次性重写全部 PDFReader，而是先建立稳定边界，再逐步把已有逻辑迁出超大 View。

## 2. 新模块

| 模块 | 职责 |
| --- | --- |
| `ReadingInspectorView.swift` | 右侧 Inspector 容器、模式切换、宽度和显示状态。 |
| `ReadingContextPanel.swift` | 当前 PDF 的单词和笔记摘要。 |
| `ReadingGuidePanel.swift` | 当前选区导读、追问、流式消息、保存控制。 |
| `ReadingNotesPanel.swift` | 当前 PDF 笔记列表，按页码和选区分组。 |
| `ReadingInspectorModel.swift` | Inspector 模式、当前选区、导读会话和保存状态。 |
| `ExplanationSession.swift` | 导读消息、摘要、loading/error、已保存 note ID。 |
| `PDFSelectionContext.swift` | 选区文本、上下文、页码、bounds、PDF 路径。 |

已有模块保留但收窄职责：

| 模块 | 调整 |
| --- | --- |
| `TranslationBubble.swift` | 只保留翻译结果、轻量保存和错误展示；不再承载多轮导读聊天。 |
| `PDFReaderView.swift` | 触发选区动作和 PDFKit 定位；把导读状态交给 Inspector model。 |
| `ReadingContextSidebarView.swift` | 迁移 / 拆分为 Inspector 的上下文和笔记 panel。 |

## 3. 布局方案

阅读页使用稳定三栏布局：

```swift
HStack(spacing: 0) {
    outlineSidebar
    PDFReaderView(document: document)
    if inspectorModel.isVisible {
        Divider()
        ReadingInspectorView(model: inspectorModel)
            .frame(width: inspectorModel.width)
    }
}
```

宽度调整优先使用 macOS 原生 split 体验：

- 可选方案 A：`HSplitView` 承载 PDFReader 和 Inspector。
- 可选方案 B：自定义窄 `NSSplitViewRepresentable`，由 AppKit 管理 resize cursor。

不再用覆盖在浮窗右下角的透明 resize hot zone 作为主要缩放方式。

## 4. Inspector 状态

```swift
@MainActor
final class ReadingInspectorModel: ObservableObject {
    @Published var isVisible: Bool
    @Published var width: CGFloat
    @Published var mode: ReadingInspectorMode
    @Published var selection: PDFSelectionContext?
    @Published var guideSession: ExplanationSession?
}

enum ReadingInspectorMode: String, CaseIterable {
    case context
    case guide
    case notes
}
```

持久化：

- `isVisible` 用 `@AppStorage("show_reading_inspector")`。
- `width` 用 `@AppStorage("reading_inspector_width")`，读取时 clamp 到 300–460。
- `mode` 可持久化，但打开「解释」时强制切换到 `.guide`。

## 5. 选区模型

```swift
struct PDFSelectionContext: Identifiable, Equatable {
    let id: UUID
    let pdfPath: String
    let pdfName: String
    let pageIndex: Int
    let selectedText: String
    let surroundingText: String
    let bounds: CGRect
    let boundsStr: String
}
```

来源：

- `PDFReaderView` 在选区菜单生成时创建 `PDFSelectionContext`。
- 点击「解释」时调用 `inspectorModel.startGuide(selection:)`。
- 点击「笔记」仍走现有笔记 draft，不进入导读会话。

## 6. 导读会话

```swift
struct ExplanationSession: Identifiable, Equatable {
    let id: UUID
    let selection: PDFSelectionContext
    var messages: [ExplanationMessage]
    var summary: String
    var isLoading: Bool
    var errorMessage: String?
    var savedNoteIdsByMessageId: [UUID: String]
}
```

消息：

```swift
struct ExplanationMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id: UUID
    let role: Role
    var content: String
}
```

提交流程：

1. `ReadingGuidePanel` 调用 `model.submitGuideQuestion(_:)`。
2. Model 追加 user message 和空 assistant message。
3. Model 调用 `BridgeService.explainSelectionStreaming`。
4. partial 回调只更新最后一条 assistant message。
5. 完成后设置 `isLoading = false` 并重新聚焦输入框。
6. 失败时保留历史消息并显示短错误状态。

上下文压缩沿用现有策略：

- 最近 20 条消息完整保留。
- 更早消息压缩为短 digest。
- 原始选中文案和 surrounding text 始终单独传入。

## 7. 导读滚动

`ReadingGuidePanel` 使用一套专用滚动观察器：

- `ScrollViewReader` 负责滚到底部。
- `NSScrollView` observer 判断 `isNearBottom`。
- 用户在底部时，流式输出持续跟随。
- 用户向上滚动后，停止自动跟随。
- 新问题提交时恢复跟随到底部。

该逻辑只存在于 `ReadingGuidePanel`，不再放在通用翻译气泡里。

## 8. 保存 AI 回复

保存单条回复：

```swift
func saveAssistantMessage(_ message: ExplanationMessage) async -> String?
```

保存逻辑：

- `content = session.selection.selectedText`
- `note = message.content`
- `boundsStr = session.selection.boundsStr`
- `pageIndex = session.selection.pageIndex`
- 保存成功后发送 `.addUnderlineNote`
- 更新 `savedNoteIdsByMessageId`
- 刷新 `AppState.notes`

删除已保存回复：

- 遍历 `savedNoteIdsByMessageId.values`
- 调用 `BridgeService.deleteNote(id:)`
- 发送 `.removeUnderlineNote`
- 清空保存映射并刷新 notes

按钮规则：

- 每条 assistant message 提供「保存」或「已保存」状态。
- 底部无已保存消息时显示「保存全部」。
- 已有保存消息时显示「已保存到笔记」和删除按钮。

## 9. 上下文 Panel

`ReadingContextPanel` 读取：

- `AppState.vocabulary`
- `AppState.notes`
- `AppState.currentPageIndex`
- `AppState.selectedDocument`

职责：

- 当前 PDF 本地过滤。
- 按当前页附近排序。
- 展示紧凑摘要，不做复杂编辑。
- 点击条目发送 `.jumpToSelectionBounds`。

该 panel 不直接调用 `BridgeService`。

## 10. 笔记 Panel

`ReadingNotesPanel` 复用当前 `NoteTextList` 和 `NoteSelectionKey` 思路：

- 按 `pdfPath + pageIndex + boundsStr + content` 分组。
- 每条 note item 保留独立创建时间。
- Markdown 使用 `MarkdownText`。
- 默认收起，展开后展示完整内容。
- 点击卡片跳转原文。

编辑仍保留在 `NoteListView`，Inspector 只提供查看和跳转。

## 11. PDFReader 边界

`PDFReaderView` 保留：

- PDFKit document 加载；
- 选区识别；
- 选区菜单；
- PDF annotation 添加 / 删除；
- PDF viewport 保存 / 恢复；
- bounds 定位。

`PDFReaderView` 移出或委托：

- 多轮导读消息状态；
- 导读保存状态；
- 导读滚动和输入焦点；
- Inspector 模式切换；
- 右侧列表展示状态。

拆分顺序：

1. 先新增 Inspector model 和 panels。
2. 将「解释」动作接到 Inspector guide。
3. 保留旧 TranslationBubble 翻译路径。
4. 删除 TranslationBubble 中解释聊天分支。
5. 再逐步抽出 annotation / note selection service。

## 12. 代码设计原则

本迭代的代码目标是简单、可理解、可维护、可迭代。SOLID 作为约束使用，不作为制造抽象的理由。

- **单一职责**：View 只负责布局和用户事件转发；状态编排放进 model；PDFKit 操作放进 coordinator / controller；持久化和 LLM 调用放进 service。
- **开放封闭**：新增 Inspector panel 时通过明确的 model 状态和小组件扩展，不回到 `PDFReaderView` 或 `TranslationBubble` 里继续追加分支。
- **里氏替换**：只有存在真实替代实现时才引入 protocol；不要为了“看起来架构化”而创建空协议。
- **接口隔离**：每个组件只接收自己需要的数据和回调，避免传入整个 `AppState` 或巨型 request。
- **依赖倒置**：新 SwiftUI View 不直接调用 `BridgeService.shared`；需要副作用时通过 model / service 方法或窄闭包注入。
- **KISS**：优先使用 SwiftUI / AppKit 原生能力；能用 `HSplitView` 解决的交互，不自定义透明 hit zone。
- **无冗余**：同一段逻辑只保留一个来源；笔记分组、Markdown 渲染、AI 回复保存等共享逻辑应抽到明确 helper / service。
- **小文件边界**：新增文件以 300–500 行为软上限；超过时先检查职责是否混杂。
- **可测试**：纯逻辑优先放在无 UI 依赖的类型中，例如 note 分组、消息压缩、保存状态计算。
- **渐进迁移**：先迁移导读路径，再拆 PDF annotation 和 note selection；每一步都保持可编译、可回退。

## 13. 视觉实现约束

- Inspector 宽度不小于 300pt。
- Header 高度控制在 44–52pt。
- 内容区域统一 12pt 外边距，列表间距 8–10pt。
- 卡片圆角 8pt，边框使用 `separator` / 低透明 primary。
- 不在卡片内再放大卡片。
- 输入框使用系统 text background，focused 状态只做细描边。
- 使用 SF Symbols / systemImage，不手写复杂图标。
- 删除按钮必须有足够点击区域，不与 resize handle 重叠。
- 空状态文案短句即可，不放长说明。

## 14. 验证

手动验证：

1. 打开 PDF 后，Inspector 可显示 / 隐藏。
2. 拖动 split handle 时 cursor 正确，PDF 不跳页。
3. 点击「解释」后，Inspector 切换到导读模式。
4. 导读首问、追问、流式输出都在右栏完成。
5. 用户在底部时流式输出跟随；向上滚动后不强制到底。
6. AI 回复可单条保存、全部保存、删除已保存回复。
7. 保存后的 AI 回复出现在笔记 panel 中。
8. 上下文和笔记 panel 点击条目能跳回原文。
9. 右栏文字对比度清晰，窄宽度下无重叠和关键截断。
10. 翻译仍可快速使用，不被导读迁移破坏。

程序检查：

```bash
xcodebuild -project LumenPDF/LumenPDF.xcodeproj -scheme LumenPDF -configuration Debug -destination 'platform=macOS' build
```

## 15. 后续工程整理

1. 抽 `PDFAnnotationController` 管理 PDF 标注。
2. 抽 `UnderlineNoteService` 管理选区合并和 note 保存。
3. 抽 `PDFViewportController` 管理页码和滚动恢复。
4. 为 `NoteTextList` 增加纯 Swift 单元测试。
5. 为导读会话增加 ViewModel 单元测试。
