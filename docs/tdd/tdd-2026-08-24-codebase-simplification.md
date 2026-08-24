---
version: unreleased
date: 2026-08-24
prd: prd/prd-2026-08-24-codebase-simplification.md
related:
  - tdd/tdd-2026-08-24-llm-provider-other.md
---

# LumenPDF — 内部去重与结构收缩 TDD

## 1. 技术结论

删除平行规则和未走的桥接，不引入新的中间层。Extra Config 默认值只在 Rust 计算；设置页只做展示和编辑。生产翻译只走流式 UniFFI。笔记导出只留 Swift。

## 2. 模块边界

| 入口 | 职责 |
| --- | --- |
| `thinking_control::default_extra_config_json` | 唯一的 host/模型启发式；HTTP `resolve_extra_config` 与 UniFFI 共用。 |
| `default_extra_config(base_url, model)` | 纯函数 UniFFI，不依赖 `initialize`。 |
| `LLMThinkingExtraConfig.defaultJSON` | 设置页展示包装：调用 Bridge 后 `prettyPrinted`。Views 仍不直接调 `BridgeService`。 |
| `LLMExtraConfig.liveJSON` / `resolvedOrDefault` | Extra Config 校验后的运行时 JSON：空则用上面的默认。 |
| `AnnotationBoundsCodec` | 唯一的 `boundsStr` 编解码。 |
| `PromptTemplateValidator.validatePair` | 设置保存与提示词编辑器共用的 User + System 校验。 |
| `ReaderPersistence.deleteNoteRemovingUnderline` / `deleteVocabularyRemovingHighlight` | 删除 SQLite 记录并发送对应 PDF 标注移除事件。 |
| `AppState.openLibraryDocument` | 笔记/单词列表跳转到文库文档并延迟 `jumpToPage`。 |
| `LlmTranslator::post_chat` | 单词/句子流式与非流式请求共用的 HTTP 发送与 vendor-extension 重试。 |
| `BridgeService.exportNotesMarkdown` | 唯一笔记导出；用 `NoteTextList.markdown` 拼 Markdown。 |
| `ReadingSessionService.sentenceHash` | 静态哈希，不再作为 `@StateObject`。 |

已删除且无替代调用点：

- `AnnotationPersistenceService`（从未写入 PDF 文件）
- `JSONSyntaxHighlighter.attributedString`
- `ReaderEventBus.postFreeAnnotation`（只保留 `postFreeAnnotations`）
- UniFFI `translate` / `translate_sentence` / `get_vocabulary_entry` / `export_notes_markdown`
- `TranslationUseCase::translate` 与未用构造 `new` / `new_for_language` / `with_phonetic`（生产只走 `translate_streaming` + `with_phonetic_for_language`）
- `VocabularyUseCase::get_by_id`（仓库 `get_by_id` 仍给 `update` 用）
- `NoteUseCase::export_markdown`
- `LlmTranslator::translate_sentence`（非流式；流式路径保留）
- Swift 侧复制的 Extra Config host/模型启发式

保留且有意不合并：

- `ReaderPersistence`：Views 不得直接调用 `BridgeService`。
- `PDFKitView`：拆文件不删除重复，视口恢复回归面大。
- application 用例层：DDD 约束，不是平行业务规则。

## 3. 关键算法 / 状态

- Extra Config 默认 JSON 只在 `ThinkingDisableKind::for_endpoint` 生成。Swift 不再解析 host/模型名。
- `default_extra_config` 可在 `initialize` 之前调用，避免设置页启动早期得到 `{}`。
- Extra Config 持久化仍写校验后的原文（空则清除该 endpoint 的存储）；发给 Rust 的是 `resolvedOrDefault` 之后的 live JSON。Rust 对空 Extra Config 再 `resolve_extra_config` 一次，与设置页同源。
- `PDFKitView.parseAnnotationRects` 直接调用 `AnnotationBoundsCodec.parse`，空矩形和 `{0,0,0,0}` 一律丢弃。
- 笔记下划线创建走 `PDFMarkupAppearance.makeUnderline`，颜色仍由 `applyUnderline` 固定为可见红。
- 生产翻译入口只剩 `translate_streaming` / `translate_sentence_streaming`。Domain `TranslationDomainService::translate` 仍给单测用。

## 4. 测试与运行时验收

自动化：

- `thinking_control`：各服务商默认 JSON；空 resolve 到默认；`{}` 与用户 JSON 原样保留。Swift 不再复制这张表。
- `AnnotationBoundsCodecTests`：空/零矩形过滤与 round-trip。
- `LLMExtraConfigTests.testLiveJSONKeepsUserObjectAndRejectsReservedKeys`
- `PromptTemplateValidatorTests.testValidatePairCombinesUserAndSystemErrors`
- `PDFMarkupAppearanceTests.testMakeUnderlineAppliesAppearanceAndIdentity`
- `cargo test` 覆盖 `post_chat` 抽取后的 translator、收缩后的 `TranslationUseCase`，以及已删除 UniFFI 的编译缺失。

本环境无法运行 macOS 应用，也无法对 `*-apple-darwin` 执行 `make build-rust`。`LumenPDF/Generated/` 由 CI 在 macOS 上按 UniFFI 重新生成。发版前须在真实 app 里点：设置页 Extra Config 默认值（含启动早期打开设置）、笔记 Markdown 导出、流式单词/句子翻译、阅读页删除笔记与列表跳转。
