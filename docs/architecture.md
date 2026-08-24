# LumenPDF 当前实现

当前模块边界写在本文。现行产品行为见 [product.md](product.md)；决策顺序见 [history.md](history.md)。

```
SwiftUI / PDFKit  →  BridgeService  →  UniFFI  →  interfaces/api.rs  →  domain ← infrastructure
```

`interfaces/` 只做 UniFFI 导出和组装 SQLite / LLM。翻译编排在 `domain/translation/service.rs`。笔记、单词、文库是仓库调用，不再经过 application 用例层。`domain/` 禁止 `reqwest` / `rusqlite` / `r2d2`。

Swift 不直接访问 SQLite 或发 HTTP。跨语言调用只走 `BridgeService`。Views 可以调 `BridgeService`（删笔记/单词时它会顺带发 `ReaderEventBus`）；不要再包一层只转发的 `ReaderPersistence`。

## 该读哪些文件

| 改什么 | 先读 |
| --- | --- |
| 设置 / Extra Config / 服务商 | `Views/SettingsView.swift`、`Views/LLMConfigurationSection.swift`、`Services/LLMSettingsStore.swift`、`Services/LLMProviderPickerSelection.swift`、`thinking_control.rs` |
| 翻译降级 / JSON | `domain/translation/service.rs`、`infrastructure/translator/llm_translator.rs`、`Views/TranslationBubble.swift` |
| 笔记 CRUD | `BridgeService.swift`、`Views/PDFReaderView.swift`、`NoteTextList.swift`、`ReadingNoteGrouping.swift` |
| 划线合并 | `PDFKitView.swift` 标注段、`TextLineMarkupMerge` / `UnderlineNoteMergePolicy` |
| 视口恢复 | `PDFKitView.swift` Coordinator 视口段、`ReaderViewportGeometry`、`ReadingRestorationStore` |

不要为了「文件更短」把 `PDFKitView` Coordinator 拆成三个共享可变状态的文件。视口、标注、选区共用 `pendingRestore`、undo、当前路径。

## 翻译

单词流式：`translate_streaming` → `TranslationDomainService`（缓存 → LLM → MyMemory；`skip_cache` 跳过读缓存以便重新生成）。句子流式与导读解释直接走 `LlmTranslator`，不走缓存链——这是有意的行为，不要为了「对称」改掉。

Extra Config 默认值只在 Rust `thinking_control.rs`。设置页空编辑器通过 UniFFI `default_extra_config` 显示同一份 JSON。请求时 `resolve_extra_config`：空 → 默认；任何对象（含 `{}`）原样合并。`extra_config.rs` 深合并，忽略 `messages` / `stream` / `stream_options`。Swift `LLMExtraConfig.reservedKeys` 只服务设置校验，须与 Rust 保持同一组键。

模型 JSON 输出：`model_json.rs` 先 repair 再反序列化。不要在流式 UI 中途 repair。

Swift `SentenceHash` 与 Rust `sentence_hash` 必须同算法（小写 UTF-8 的 SHA-256 hex）。两边都要留着：Rust 写缓存键，Swift 查单词。

## 设置存储

| 数据 | 位置 |
| --- | --- |
| Base URL、模型、提示词、目标语言、Extra Config 映射 | UserDefaults |
| API Key | Keychain `com.LumenPDF.app` / `llm_api_key`，按端点映射 |
| 笔记、单词、文库、翻译缓存 | `~/Library/Application Support/LumenPDF/data.db` |
| 窗口/分栏/视口 | 一份版本化阅读工作区状态，不要再平行加 UserDefaults 键 |

Base URL 有三套名字相近、职责不同的函数，不要合并：

- `BridgeService.normalizedLLMBaseURL`：补 `/v1`，给 HTTP
- `LLMConfigurationHistory.canonicalBaseURLKey`：小写去斜杠，给历史列表
- `LLMEndpointIdentity`：规范化 + 别名，给 Keychain / Extra Config 查找

服务商「其他」只在 Swift `LLMProviderPickerSelection`。

## 笔记分组（不要统一）

| 场景 | 键 | 原因 |
| --- | --- | --- |
| Inspector 卡片 | pdfPath + 页 + bounds + 规范化原文 | 同一位置不同原文要分开 |
| 阅读页锚点 | 页 + bounds | 同一矩形上的笔记合成一条下划线 |
| Markdown 导出 | pdfName | 给人读的导出 |

编码/解码走 `NoteTextList`。

## 覆盖层

翻译、笔记、选区操作栏、⌘F 搜索画在阅读窗口共同祖先上，不要为了躲裁切去开 `NSPanel`。AppKit 桥必须有单一所有者和可预测的拆除。

## UniFFI

Proc-macro：`#[uniffi::export]` / `Record` / `Error`。没有 UDL。新 API：`interfaces/api.rs` → `make build-rust` → `BridgeService`。全局只有 `POOL` 和 `LLM_CONFIG`，不要另起 runtime。

Schema 变更只写 `infrastructure/db/migration.rs`，可重复执行，新列要有默认值或可空。

## 测试

```bash
cd lumen-pdf-core && cargo fmt --check && cargo clippy -- -D warnings && cargo test
```

`domain/*/service.rs` 必须有无 I/O 的 `#[cfg(test)]`，用内联 `Fake*`。覆盖：缓存命中、LLM 成功写缓存、LLM 失败走兜底、兜底不写缓存。Linux CI 不编 Mac App；UI 改动需在 Mac 上点一遍。

## 明确不要动

- 视口恢复算法、Keychain 迁移路径、提示词 legacy 字符串：改了会丢用户数据或静默坏恢复。
- 把句子翻译/导读塞进单词那条缓存链：会改变失败与缓存行为。
- 重命名 `file_path` / `pdf_path`：要迁移数据库和 UniFFI。
