# LumenPDF — 阅读 AI 输入与选区操作优化 TDD

对应 PRD：`docs/prd/prd-2026-07-16-reading-ai-input-selection.md`

## 设计概览

本迭代限定在现有 SwiftUI/PDFKit 与翻译 prompt 层完成，避免新增跨语言数据结构和数据库迁移。

| 模块 | 变更 |
| --- | --- |
| `lumen-pdf-core/src/infrastructure/translator/llm_translator.rs` | 更新默认单词 prompt，让词源说明作为 `context_explanation` 的可选末尾小节。 |
| `LumenPDF/Reader/PDFKitView.swift` | 选区几何从 `selection.pages` 中选择有效页面，修复页面交界处 `currentPage` bounds 为空导致操作栏不展示。 |
| `LumenPDF/Views/ReadingInspector/ReadingGuidePanel.swift` | 追问输入改为多行 `TextEditor`，增加图片附件选择与 chip 展示。 |

## 详细设计

### 1. 单词词源

保持 `TranslationResult` 结构不变。默认 JSON prompt 仍要求模型输出原有字段，但将 `context_explanation` 的描述扩展为：在有帮助且可靠时，追加简短词源、历史故事或构词来源；不可靠时省略。这样旧缓存、UniFFI 绑定和 Swift 展示都无需迁移。

### 2. 页面交界选区几何

新增 `SelectedPageGeometry` helper：

1. 使用 `selection.pages` 作为候选页面；为空时回退 `pdfView.currentPage`。
2. 对每个候选页面计算逐行 selection bounds。
3. 若逐行 bounds 为空，则尝试 `selection.bounds(for: page)`。
4. 过滤空 bounds。
5. 如果 `currentPage` 在候选中有有效几何，优先使用；否则选择 bounds 面积最大的页面。

该策略保留单页选区的原有行为，同时修复跨页边缘选择时误用空 `currentPage` 几何的问题。

### 3. 多行 AI 输入

`questionBar` 内部使用 `TextEditor` 替代 `TextField`：

- 空文本时用 overlay 文本模拟 placeholder。
- `questionEditorHeight` 根据显式换行数和字符数估算换行数。
- 行数限制为 `1...10`，高度为 `lines * 20 + 14`。
- `TextEditor` 超过固定高度后由自身滚动。

### 4. 图片附件

使用 SwiftUI `fileImporter` 与 `UTType.image`：

- `attachedImageURLs` 保存当前输入区附件。
- 横向 chip 展示文件名和移除按钮。
- 提交时把 `[附加图片：文件名...]` 追加到问题文本。
- 当前实现只传递附件名称，不读取图片二进制；未来若 LLM 网关支持多模态，可在 `BridgeService` 扩展请求体。

## 风险与验证

| 风险 | 缓解 |
| --- | --- |
| PDFKit 跨页选区页面顺序不稳定 | 优先当前页有效几何，否则按面积选择最主要页面。 |
| `TextEditor` 默认 Return 插入换行，不再触发 submit | 保留发送按钮和默认按钮快捷键；多行输入符合本次需求。 |
| 图片附件被误解为已发送图片内容 | UI help 与 TDD 明确当前只随问题记录文件名。 |

## 测试计划

- `cargo fmt --check`
- `cargo test domain`
- `xcodebuild -project LumenPDF/LumenPDF.xcodeproj -scheme LumenPDF -configuration Debug build`
- 人工运行验证：页面交界选区、输入框 1/2/10/11 行、图片选择和移除、提交后清空。
