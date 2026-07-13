# LumenPDF — 阅读上下文与 AI 导读 TDD

**版本**: v1.0.12 · **日期**: 2026-07-03

对应 PRD：`docs/prd/prd-2026-07-02-reading-context-sidebar.md`

## 1. 技术结论

本次改动限定在 Swift / SwiftUI / PDFKit 层完成，不新增 Rust 数据结构和数据库迁移。右栏读取 `AppState` 中的全量单词与笔记后在本地过滤；笔记多条内容复用现有 `notes.note` TEXT 字段；AI 导读多轮状态只保存在当前 `TranslationBubbleRequest` 生命周期内。

## 2. 变更模块

| 模块 | 结论 |
| --- | --- |
| `ContentView.swift` | 在阅读页组合 PDFReader 和右栏，提供右栏显隐按钮，并在显隐切换时保留 PDF viewport。 |
| `ReadingContextSidebarView.swift` | 新增当前 PDF 的单词 / 笔记右栏，支持页码分组、滚动联动、选区定位、笔记分组和展开收起。 |
| `PDFReaderView.swift` | 拆分普通划线与笔记路径；支持笔记追加、选区合并、多轮解释、AI 回复保存为笔记、bounds 定位和 viewport 恢复。 |
| `TranslationBubble.swift` | 提供 AI 导读聊天窗口、Markdown 渲染、流式滚动锚定、输入框自动聚焦、逐条保存、删除已保存回复、拖动和缩放。 |
| `NoteTextList.swift` | 用 JSON `[String]` 兼容存储多条笔记，并兼容旧纯文本数据。 |
| `NoteListView.swift` | 管理页按多条笔记渲染 Markdown，并用多段文本编辑。 |
| `BridgeService.swift` | 包装 `listNotesByPdf` 等 UniFFI API。 |
| `KeychainService.swift` | 使用重装稳定的 Keychain service 读取 / 迁移 API Key，避免本地重装后反复授权。 |

## 3. 数据结构

### 3.1 右栏条目

```swift
private struct ReadingContextItem: Identifiable {
    enum Kind { case vocabulary, note }

    let id: String
    let sourceId: String
    let kind: Kind
    let pageIndex: UInt32
    let pdfPath: String
    let boundsStr: String
    let title: String
    let subtitle: String
    let detail: String
    let noteMarkdownItems: [ReadingContextNoteItem]
    let createdAt: Int64
}
```

- 单词条目由 `VocabularyEntry` 映射，使用 `selectionBounds` 做定位。
- 笔记条目由 `NoteEntry` 按 `pdfPath + pageIndex + boundsStr + content` 分组。
- 分组后的笔记条目保留同一选区下的每条 markdown 内容和各自创建时间。
- 排序规则：页码升序，同页内创建时间降序，再按稳定 ID 排序。

### 3.2 笔记内容

`NoteTextList` 负责所有笔记文本的读写：

- `decode(_:)` 兼容 JSON array、JSON string、旧纯文本和嵌套转义字符串。
- `encode(_:)` 将非空内容写成 JSON `[String]`。
- `appending(_:to:)` 用于向已有笔记追加内容。
- `editText(_:)` 在编辑页把多条笔记展开为用空行分隔的文本。
- `markdown(_:)` 用于多条笔记的 Markdown 展示。

## 4. 阅读上下文右栏

`ReadingContextSidebarView` 直接消费 `AppState.vocabulary` 和 `AppState.notes`：

- `mode == .vocabulary` 时过滤当前 PDF 的单词。
- `mode == .note` 时过滤当前 PDF 的笔记并按选区分组。
- `ScrollViewReader` 根据 `appState.currentPageIndex` 自动滚动到当前页或之后最近页。
- 页分组 `onAppear` 在用户手动滚动时发送 `.jumpToPage`，程序化滚动通过 `isProgrammaticScroll` 抑制反向跳转。
- 点击卡片发送 `.jumpToSelectionBounds`，并附带 `pageIndex`、`filePath`、`boundsStr`、`itemId`、`kind`。

右栏显隐由 `ContentView.toggleReadingContextSidebarPreservingViewport()` 处理：

1. 发送 `.saveReadingPositionNow`；
2. 切换 `showReadingContextSidebar`；
3. 发送 `.restoreReadingViewport`；
4. PDFKit coordinator 在布局变化后恢复页码和 normalized offset。

## 5. PDF 选区定位

新增通知：

```swift
extension Notification.Name {
    static let jumpToSelectionBounds = Notification.Name("jumpToSelectionBounds")
}
```

PDFKit coordinator 处理流程：

1. 校验通知中的 `filePath` 是否为当前 PDF；
2. 跳到 `pageIndex` 对应页面；
3. 解析 `boundsStr`，计算选区 union rect；
4. 将 PDF page rect 转换为 `PDFView` 坐标；
5. 滚动 enclosing scroll view，使目标区域进入视口；
6. 添加短暂 focus annotation；
7. bounds 为空或解析失败时降级为纯跳页。

## 6. 划线与笔记

普通划线路径：

- 选区菜单「划线」直接发送 `.addFreeAnnotation`。
- 不创建 `UnderlineNoteDraft`。
- 不写 `notes` 表。

笔记路径：

- 选区菜单「笔记」创建 `UnderlineNoteDraft`。
- `UnderlineNoteDraftView` 展示选中文本和 `TextEditor`。
- 保存时调用 `saveUnderlineNote(word:noteText:boundsStr:page:)`。
- 完整选中已有笔记划线时，菜单提供「添加笔记」和「取消笔记」。

合并规则：

- 已有完全相同选区：追加笔记文本或删除该笔记，由菜单动作决定。
- 新选区被已有笔记完全覆盖：不创建重复 note。
- 新选区与已有笔记部分重叠：删除参与合并的旧 notes，创建包含旧 rects 和新 rects 的新 note。
- 无重叠：创建独立 note。
- 合并 rects 时只合并同一文本行上相交或相邻的矩形。

PDF annotation 同步：

- 新增笔记发送 `.addUnderlineNote`。
- 删除笔记发送 `.removeUnderlineNote`。
- 合并笔记通过 `.addUnderlineNote` 携带 `deletedNoteIds` 和 `deletedNotesInfo`，用于移除旧下划线和支持 undo。

## 7. AI 导读窗口

### 7.1 对话状态

`TranslationBubbleRequest` 新增：

- `explanationMessages: [ExplanationMessage]`
- `explanationSummary: String`

`PDFReaderView.requestExplanation` 在每轮提交时：

1. 读取当前 `translationRequest` 的历史消息。
2. 追加 user message 和空 assistant message。
3. 流式返回时只更新最后一条 assistant message。
4. 保留最近 20 条完整消息。
5. 将更早消息压缩为 digest，并把总上下文限制在固定长度。
6. 原始选中文案和原始上下文始终单独传入，不参与压缩。

### 7.2 滚动与焦点

`TranslationBubble` 使用 `ScrollViewReader` 和 `ExplanationScrollObserver`：

- `ExplanationScrollObserver` 读取底层 `NSScrollView` 的 `isNearBottom` 与 `hasOverflow`。
- 用户位于底部或内容未溢出时，流式输出保持滚动到底部。
- 用户向上滚动后，`explanationShouldFollowStream` 变为 false，后续 token 不强制滚动。
- 新消息追加、内容高度变化、loading 结束时只在允许跟随时滚动。
- 解释输入框在进入解释界面和回答完成后通过 `@FocusState` 自动聚焦。

### 7.3 拖动与缩放

- `AppKitDragCapture` 负责窗口拖动。
- `AppKitResizeCapture` 负责边缘和右下角缩放。
- resize 热区覆盖在最终 card frame 上，避免和 SwiftUI frame 顺序错位。
- 底部和右侧热区为 footer 控件留出空间，删除按钮不会被 resize layer 截获。
- `NSTrackingArea` + cursor rect 共同保证 hover 时显示 resize cursor。

### 7.4 Markdown 渲染

`MarkdownText` 使用 `StructuredText(markdown:)`：

- AI assistant 消息用 Markdown 渲染。
- 笔记页和右栏笔记用 Markdown 渲染。
- 文本选择保持启用。

## 8. 保存 AI 回复到笔记

`TranslationBubble` 通过 `savedExplanationEntryIds: [String: String]` 记录 message ID 到 note ID 的映射。

- 单条 assistant 消息未保存时显示「保存这条」。
- 已保存消息显示「已保存」。
- 底部无已保存消息时显示「保存所有AI回复」。
- 底部存在已保存消息时显示「已保存到笔记」和删除按钮。
- 删除按钮遍历所有已保存 note ID，调用 `BridgeService.deleteNote(id:)`，再触发父级刷新。

`PDFReaderView.saveExplanationMessageToNote` 使用当前选区创建 note：

- `content = request.word`
- `note = assistant message content`
- `boundsStr = request.boundsStr`
- 保存后发送 `.addUnderlineNote`
- 刷新 `AppState.notes`

保存后的多条 AI 回复会被右栏的 `NoteSelectionKey` 归为同一选区卡片，并以独立时间条目展示。

## 9. Keychain

`KeychainService` 只维护 `com.LumenPDF.app` 的 data-protection Keychain 条目，并使用 `kSecAttrAccessibleWhenUnlocked`。应用自身的稳定签名 designated requirement 决定升级后的身份延续，不再通过 file-based Keychain ACL 模拟“跨重装稳定”。

读取时先访问正式 data-protection 条目；仅在不弹认证 UI 的前提下尝试读取旧 `com.LumenPDF.app.reinstall-stable` 和旧 file-based 条目。能直接读取时迁移到正式条目并删除旧值；旧 ACL 不再信任当前签名则返回空值，由用户在设置页重新输入一次，绝不自动弹出钥匙串密码框，也不把访问权限扩大到其他本机应用。

打包链路嵌套 dylib 先签、主应用后签，并在最终主应用签名中显式附加 `LumenPDF.entitlements`。默认 ad-hoc 签名可正常打包；若使用稳定身份则应用到全部嵌套代码。ad-hoc 包不保证 Keychain 跨重装延续，系统可再次要求授权。

## 10. 架构约束

- 右栏读取数据走 `AppState`，不直接访问 Rust bridge。
- UI 状态更新保持在 `@MainActor`。
- PDFKit 交互集中在 coordinator 和窄 AppKit representable。
- Rust domain / application / infrastructure 不变。
- 数据库 schema 不变。

## 11. 验证

手动验证：

1. 打开含单词和笔记的 PDF，右栏只展示当前 PDF 数据。
2. 滚动 PDF，右栏跟随到当前页或最近页。
3. 手动滚动右栏，PDF 同步跳页。
4. 点击单词 / 笔记卡片，PDF 跳转并聚焦选区。
5. 点击「划线」，只创建普通下划线。
6. 点击「笔记」，保存空内容和非空内容都能创建笔记划线。
7. 对同一选区追加多条笔记，右栏按条目分开展示时间。
8. 笔记 Markdown 在右栏和笔记页正确渲染。
9. 笔记卡片默认收起，展开后展示完整内容。
10. AI 导读连续追问，历史消息稳定保留，回复用 Markdown 渲染。
11. 流式输出在底部时持续跟随；用户向上滚动后不强制回到底部。
12. 解释窗口可拖动、可缩放，hover 到边缘出现 resize cursor。
13. 保存单条 AI 回复和保存所有 AI 回复后，右栏出现独立笔记条目。
14. 删除已保存 AI 回复后，右栏和笔记页同步刷新。
15. 本地重新安装 App 后，API Key 能读取且不反复弹钥匙串授权。

程序检查：

- Swift / PDFKit 层改动优先运行 Xcode build。
- Rust 未改动时不强制运行 `cargo test`。
- 提交前保留 pre-commit hooks。

当前验证命令：

```bash
xcodebuild -project LumenPDF/LumenPDF.xcodeproj -scheme LumenPDF -configuration Debug -destination 'platform=macOS' build
```

## 12. 后续优化

1. `list_vocabulary_by_pdf` 和按 PDF 查询的分页 API。
2. 右栏卡片选中态和 PDF 标注反向选中右栏卡片。
3. 数据库 `pdf_path + page_index` 索引。
4. 右栏宽度用户可调。
