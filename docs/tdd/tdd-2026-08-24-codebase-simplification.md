---
version: unreleased
date: 2026-08-24
prd: prd/prd-2026-08-24-codebase-simplification.md
predecessor:
  - tdd/tdd-2026-03-30-optimization.md
  - tdd/tdd-2026-07-04-v1014-refactor-automation.md
---

# LumenPDF — 内部去重与死代码清理 TDD

## 1. 技术结论

只合并已被调用路径证明等价的辅助逻辑，并删除无引用代码。不引入新的中间层。

## 2. 模块边界

| 入口 | 职责 |
| --- | --- |
| `AnnotationBoundsCodec` | 唯一的 `boundsStr` 编解码；`PDFKitView` 不再自实现解析。 |
| `LLMExtraConfig.liveJSON` / `resolvedOrDefault` | Extra Config 校验后的运行时 JSON：空则用 `LLMThinkingExtraConfig.defaultJSON`。 |
| `PromptTemplateValidator.validatePair` | 设置保存与提示词编辑器共用的 User + System 校验。 |
| `ReaderPersistence.deleteNoteRemovingUnderline` / `deleteVocabularyRemovingHighlight` | 删除 SQLite 记录并发送对应 PDF 标注移除事件。 |
| `AppState.openLibraryDocument` | 笔记/单词列表跳转到文库文档并延迟 `jumpToPage`。 |
| `LlmTranslator::post_chat` | 单词/句子流式与非流式请求共用的 HTTP 发送与 vendor-extension 重试。 |
| `ReadingSessionService.sentenceHash` | 静态哈希，不再作为 `@StateObject`。 |

已删除且无替代调用点：

- `AnnotationPersistenceService`（从未写入 PDF 文件）
- `JSONSyntaxHighlighter.attributedString`
- `ReaderEventBus.postFreeAnnotation`（只保留 `postFreeAnnotations`）
- `BridgeService.translate` / `translateSentence` / `getVocabularyEntry`（Swift 侧未使用；UniFFI 导出保留）
- `TranslationUseCase::{new, new_for_language, with_phonetic}`（生产只走 `with_phonetic_for_language`）

## 3. 关键算法 / 状态

- `PDFKitView.parseAnnotationRects` 直接调用 `AnnotationBoundsCodec.parse`，空矩形和 `{0,0,0,0}` 一律丢弃。
- 笔记下划线创建走 `PDFMarkupAppearance.makeUnderline`，颜色仍由 `applyUnderline` 固定为可见红。
- Extra Config 持久化仍写校验后的原文（空则清除该 endpoint 的存储）；发给 Rust 的是 `resolvedOrDefault` 之后的 live JSON。
- `TranslationUseCase` 构造只保留带 phonetic 与 cache language 的一条路径。

## 4. 测试与运行时验收

自动化：

- `AnnotationBoundsCodecTests`：空/零矩形过滤与 round-trip。
- `LLMExtraConfigTests.testLiveJSONUsesProviderDefaultWhenEmpty`
- `PromptTemplateValidatorTests.testValidatePairCombinesUserAndSystemErrors`
- `PDFMarkupAppearanceTests.testMakeUnderlineAppliesAppearanceAndIdentity`
- `cargo test` 覆盖 `post_chat` 抽取后的 translator 与 `TranslationUseCase` 构造收缩。

本环境无法运行 macOS 应用。阅读页删除笔记、列表跳转、设置 Extra Config 与调用日志状态色在发版前仍需在真实 app 里点一次。
