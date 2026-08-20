# LumenPDF — 阅读 AI 输入与选区操作优化 TDD

## 文档关系

- 对应 PRD：[`prd-2026-07-16-reading-ai-input-selection.md`](../prd/prd-2026-07-16-reading-ai-input-selection.md)
- 并行主题：[`tdd-2026-07-16-llm-configuration-discovery.md`](tdd-2026-07-16-llm-configuration-discovery.md)
- 后续：[`tdd-2026-08-14-ai-settings-notes.md`](tdd-2026-08-14-ai-settings-notes.md)
- 索引：[`docs/README.md`](../README.md)

## 设计概览

本迭代在现有翻译链路上增加独立词源字段，并保持旧缓存与旧数据库向前兼容。

| 模块 | 变更 |
| --- | --- |
| `lumen-pdf-core/src/domain/translation/entity.rs` | 为 `TranslationResult` 新增带 serde 默认值的 `etymology` 字段。 |
| `lumen-pdf-core/src/infrastructure/translator/llm_translator.rs` | 更新默认单词 prompt、流式字段映射和最终 JSON 解析，独立读取 `etymology`。 |
| `lumen-pdf-core/src/domain/vocabulary/entity.rs`、`infrastructure/db/` | 将词源写入词汇记录，并通过幂等迁移为旧数据库新增默认空值列。 |
| `LumenPDF/Views/TranslationBubble.swift` | 将「词源 / 历史故事」作为独立小块展示。 |
| `LumenPDF/Views/VocabularyListView.swift` | 展示并支持编辑已保存的词源内容。 |
| `LumenPDF/Services/PromptTemplateUpdateCoordinator.swift` | 按语言维护单词提示词版本，自动迁移内置模板并保护用户自定义模板。 |
| `LumenPDF/App/AppState.swift`、`Views/SettingsView.swift` | 启动时执行迁移并提示；设置页处理自定义模板的保留或升级。 |
| `LumenPDF/Tests/PromptTemplateUpdateCoordinatorTests.swift` | 覆盖自定义模板保护、旧内置模板自动升级和保留后不重复提醒。 |
| `LumenPDF/Reader/PDFKitView.swift` | 选区几何从 `selection.pages` 中选择有效页面，修复页面交界处 `currentPage` bounds 为空导致操作栏不展示。 |
| `lumen-pdf-core/src/interfaces/api.rs`、`llm_translator.rs` | 新增图片附件桥接类型，并用 OpenAI-compatible 图文消息发送图片。 |
| `LumenPDF/Views/ReadingInspector/ReadingGuidePanel.swift` | 追问输入改为纵向增长输入框，增加图片附件选择与 chip 展示。 |
| `LumenPDF/Views/ReadingInspector/ReadingGuideService.swift` | 读取图片原始字节，并将真实图片内容传给桥接层。 |

## 详细设计

### 1. 单词词源

`TranslationResult` 新增 `etymology: String`，默认 JSON prompt 将它定义为独立字段：

- `context_explanation` 只解释当前语境下为什么是这个含义。
- `etymology` 单独承载词源、历史故事或构词来源。
- 信息不可靠、带有猜测性或无助于理解记忆时，模型输出空字符串。

流式解析在该字段闭合后发出新的 partial result；最终解析将其写入完整结果。`TranslationResult.etymology` 使用 `serde(default)`，因此旧缓存 JSON 无该字段时仍可读取。

词汇表新增 `etymology TEXT NOT NULL DEFAULT ''`。迁移先检查列是否存在，再执行 `ALTER TABLE`，可重复运行。保存、更新、列表读取和 Swift 编辑链路同步传递该字段。

`etymology` 的空字符串是合法结果。翻译卡片只在字段非空时渲染独立小块，不因空值自动重试，也不显示占位内容。

提示词升级使用显式 revision：

- 每个语言族保存 `word_prompt_template_revision_<suffix>` 和 pending 标记。
- 启动时，未处理当前 revision 的模板若匹配已知内置版本，则自动替换为最新版。
- 不匹配任何已知内置版本时视为用户自定义，仅设置 pending，不改写内容。
- 用户选择「保留自定义」或「使用新版」后写入当前 revision，避免每次启动重复提醒。
- Rust 翻译缓存 scope 由目标语言、实际生效的单词 User Prompt 和 System Prompt 的哈希组成；模板变化会自然产生新的缓存空间，不依赖 `etymology` 是否为空。

### 2. 页面交界选区几何

新增 `SelectedPageGeometry` helper：

1. 使用 `selection.pages` 作为候选页面；为空时回退 `pdfView.currentPage`。
2. 对每个候选页面计算逐行 selection bounds。
3. 若逐行 bounds 为空，则尝试 `selection.bounds(for: page)`。
4. 过滤空 bounds。
5. 如果 `currentPage` 在候选中有有效几何，优先使用；否则选择 bounds 面积最大的页面。

该策略保留单页选区的原有行为，同时修复跨页边缘选择时误用空 `currentPage` 几何的问题。

### 3. 多行 AI 输入

`questionBar` 使用支持纵向增长的原生 `TextField(axis: .vertical)`：

- placeholder、首行文本和插入光标由同一个文本控件布局，避免手写 placeholder 与 `TextEditor` 内边距不一致导致的光标错位。
- 使用 `.lineLimit(1...10)` 随内容自然增高。
- 超过 10 行后由输入控件内部滚动。

### 4. 图片附件

使用 SwiftUI `fileImporter` 与 `UTType.image`：

- `attachedImageURLs` 保存当前输入区附件。
- 横向 chip 展示文件名和移除按钮。
- 提交后在后台读取图片原始字节，不缩放、不压缩、不重新编码。
- Swift 通过 UniFFI `ImageAttachment` 传递文件名、MIME 和 base64。
- Rust 将用户消息构造成 `text` 与 `image_url` content parts，图片 URL 使用 `data:<mime>;base64,<payload>`。
- 纯文本请求继续使用字符串 `content`，保持现有 OpenAI-compatible 网关兼容性。
- 能力检测先请求 `/models`，读取常见的 `architecture.input_modalities`、`input_modalities`、`modalities` 或 `capabilities.vision`。
- metadata 未提供明确结果时，发送一张内置 1×1 PNG 的最小探测请求；只把明确的图片不支持错误判定为 `unsupported`。
- 探测结果按 Base URL + 模型在当前进程缓存；认证、网络、限流等失败返回 `unknown`，不禁用按钮。
- 模型明确不支持时上传按钮置灰；能力未知时允许发送，并沿现有错误链展示服务端错误。

## 风险与验证

| 风险 | 缓解 |
| --- | --- |
| PDFKit 跨页选区页面顺序不稳定 | 优先当前页有效几何，否则按面积选择最主要页面。 |
| 多行输入的 Return 插入换行，不直接触发 submit | 保留发送按钮和默认按钮快捷键；多行输入符合本次需求。 |
| 原图使请求体过大或超过模型限制 | 不在客户端修改图片；直接展示模型或网关返回的大小/格式错误。 |
| 模型或网关不支持多模态 | 不静默降级，直接展示 API 返回错误，便于用户更换模型。 |

## 测试计划

- `cargo fmt --check`
- `cargo test domain`
- `cargo test migration`
- `xcodebuild -project LumenPDF/LumenPDF.xcodeproj -scheme LumenPDF -configuration Debug build`
- `PromptTemplateUpdateCoordinatorTests`：使用独立 `UserDefaults` suite 验证提示词版本迁移，不读写真实用户设置。
- 人工运行验证：页面交界选区、输入框 1/2/10/11 行、图片选择和移除、提交后清空。
