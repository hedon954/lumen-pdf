# LumenPDF — v1.0.14 重构与验证收口 TDD

**版本**: v1.0.14 · **日期**: 2026-07-04

## 文档关系

- 对应 PRD：[`prd-2026-07-04-v1014-refactor-automation.md`](../prd/prd-2026-07-04-v1014-refactor-automation.md)
- 前序：[`tdd-2026-07-03-reading-inspector.md`](tdd-2026-07-03-reading-inspector.md)
- 后续：[`tdd-2026-07-10-note-overlay-optimization.md`](tdd-2026-07-10-note-overlay-optimization.md)
- 索引：[`docs/README.md`](../README.md)

## 1. 技术结论

本迭代把大文件和重复流程拆到更小的边界中，同时保留现有行为。Swift 侧重点是让 `PDFReaderView` 变薄，把 PDFKit、标注、事件、持久化和 Inspector 状态拆开；Rust 侧重点是减少 translation pipeline、LLM translator 和 DB repo 的重复。

Swift XCTest/XCUITest target 已移除。后续不再把当前浅层 Swift 测试作为质量主线，验证主线改为 Rust 自动化、Swift build、前后指标报告和关键 PDFKit 路径人工验收。

## 2. Swift 模块边界

| 模块 | 职责 |
| --- | --- |
| `PDFReaderView.swift` | 组合阅读 UI，转发用户动作，保留最少状态。 |
| `Reader/PDFKitView.swift` | 承载 PDFKit/AppKit representable 和 coordinator。 |
| `Reader/PDFReaderModels.swift` | 阅读页纯数据结构和请求模型。 |
| `Reader/ReaderPersistence.swift` | 阅读位置、窗口、标注等持久化读写。 |
| `Reader/ReaderEventBus.swift` | 统一封装 reader 相关 Notification payload。 |
| `Reader/AnnotationBoundsCodec.swift` | bounds 字符串编码和解析。 |
| `Reader/UnderlineNoteMergePolicy.swift` | 下划线笔记合并规则。 |
| `Reader/FreeMarkupStore.swift` | 自由标注存取。 |
| `ReadingInspector/*` | 右侧单词、笔记、AI 面板和导读状态。 |

View 不直接拼 reader notification payload；需要跨模块事件时走 `ReaderEventBus`。View 不直接扩散 `BridgeService.shared` 调用；副作用优先放入 service/model。

## 3. Reading Inspector 调整

`ReadingInspectorMode` 更新为：

```swift
enum ReadingInspectorMode: String, CaseIterable, Identifiable {
    case words
    case notes
    case ai
}
```

兼容旧持久化值：

- `context` -> `.words`
- `guide` -> `.ai`
- `notes` -> `.notes`

面板职责：

- `ReadingWordsPanel`：只读取 vocabulary，按当前页附近排序。
- `ReadingNotesPanel`：只读取 notes，负责笔记分组、展开和跳转。
- `ReadingGuidePanel`：当前选区 AI 解释、追问、保存和删除已保存回复。

## 4. 翻译浮窗实现

`TranslationBubble` 保留轻量浮窗定位和保存能力，同时补齐 resize 行为：

- 内容高度根据实际内容收缩。
- 超过最大高度时，正文区域进入滚动。
- 通过 AppKit cursor rect 在边缘和角落显示 resize cursor。
- 拖拽时按边缘方向更新 frame，保留最小/最大尺寸限制。
- 样式恢复为轻量 material 背景、细分隔线和克制阴影。

该实现只影响浮窗尺寸和样式，不改变翻译结果、保存单词、发音和关闭行为。

## 5. Rust 重构

### Translation domain

- 合并普通翻译和 streaming 翻译的共享流程。
- 保留 fallback 链：SQLite cache -> LLM -> MyMemory。
- 只在 LLM 成功时写入 cache。
- domain 层继续不依赖 `reqwest`、`rusqlite`、`r2d2`。

### LLM translator

- 抽出 chat request、completion request 和 JSON 转换 helper。
- 保持 prompt 和 OpenAI-compatible 请求语义不变。
- streaming 和非 streaming 共享 payload 构造。

### DB repo

- 抽出 optional query、list query、not found helper。
- 保持 rusqlite 实现，不引入 sqlx，不改 schema。
- 各 repo 保留现有 public 行为和错误映射。

### UniFFI interfaces

- `interfaces/api.rs` 保留 export 函数签名。
- 私有 factory/helper 只服务依赖组装，避免 export 函数重复创建 use case。
- 不新增全局 runtime 或额外 public API。

## 6. Swift 测试 target 删除

删除内容：

- `LumenPDF/Tests/LumenPDFTests`
- `LumenPDF/Tests/LumenPDFUITests`
- `LumenPDFTests` target
- `LumenPDFUITests` target

`project.yml` 是源配置，删除测试 target 后通过 `xcodegen generate` 重新生成 `LumenPDF.xcodeproj`。

后续如果需要恢复 Swift 自动化，应先定义稳定、高价值的测试边界，例如纯 Swift parser/model、可注入 service，或独立 PDFKit harness，而不是恢复当前浅层 UI 可见性测试。

## 7. 验证脚本

新增脚本：

- `scripts/refactor-metrics.sh`：收集 Swift/Rust 文件行数、最大文件、关键调用计数、git hash。
- `scripts/refactor-baseline.sh`：生成 baseline markdown/html。
- `scripts/verify-refactor.sh`：运行 Rust checks、Swift build，并生成 after markdown/html。

报告输出：

- `docs/plan/refactor-baseline.md`
- `docs/plan/refactor-baseline.html`
- `docs/plan/refactor-after.md`
- `docs/plan/refactor-after.html`

Browser 只用于打开 HTML 报告和截图确认可读性，不替代原生 App 测试。

## 8. 验证命令

```bash
cd lumen-pdf-core && cargo fmt --check
cd lumen-pdf-core && cargo clippy -- -D warnings
cd lumen-pdf-core && cargo test
xcodebuild build -project LumenPDF/LumenPDF.xcodeproj -scheme LumenPDF -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
scripts/verify-refactor.sh
```

由于 Swift 测试 target 已删除，`xcodebuild test` 不再作为本版本验收命令。

## 9. 风险与回滚

- 风险：删除 Swift tests 后，Swift 纯逻辑回归依赖 build 和人工验收发现。
- 风险：PDFKit 交互依旧难以用普通 UI test 稳定覆盖。
- 缓解：保留 Rust 自动化、前后指标报告和关键路径手动验收清单。
- 回滚：可恢复 `LumenPDF/Tests` 目录和 `project.yml` test target，再运行 `xcodegen generate`。

