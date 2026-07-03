# LumenPDF — v1.0.14 重构与验证收口 PRD

**版本**: v1.0.14 · **日期**: 2026-07-04

## 1. 产品结论

v1.0.14 的目标不是新增功能，而是在现有功能不变的前提下，把阅读页、翻译浮窗、阅读 Inspector、Swift/Rust 边界和验证流程收敛到更清晰、可迭代的形态。

用户感知上，LumenPDF 仍然是同一个 PDF 阅读器：打开 PDF、翻译、解释、保存单词、保存笔记、自由标注、列表跳转和窗口恢复都不改变。变化主要发生在代码组织、右侧 Inspector 信息架构、浮窗样式和自动化验证文档化。

## 2. 目标

1. 保持现有 UI、存储、LLM 行为和 UniFFI public API 稳定。
2. 降低 `PDFReaderView`、翻译浮窗和 Rust translation/DB 层的重复逻辑。
3. 将右侧 Inspector 调整为更清楚的 `单词 | 笔记 | AI` 三段结构。
4. 恢复翻译浮窗更轻、更接近 v1.0.10 的视觉风格，并支持边缘拖拽缩放。
5. 建立可重复的前后对比报告和验证脚本。
6. 按当前项目判断移除 Swift 测试 target，避免维护低价值、易漂移的测试文件。

## 3. 非目标

- 不修改数据库 schema 或 migration 行为。
- 不修改 LLM prompt 的核心文本。
- 不修改通知名称、payload key、UserDefaults key。
- 不引入新的 Web 产品形态。
- 不为了重构创建额外抽象层。
- 不在本版本继续维护 Swift XCTest/XCUITest 文件。

## 4. 用户体验要求

### F1 — 阅读 Inspector

- Inspector 分段控制显示为 `单词 | 笔记 | AI`。
- `单词` 只展示当前 PDF 的词库条目。
- `笔记` 只展示当前 PDF 的笔记列表。
- `AI` 负责当前选区解释、追问和 AI 回复保存。
- 旧版本保存的 `context`、`guide` 模式应平滑映射到新模式。

### F2 — 翻译浮窗

- 浮窗内容高度自适应，只有超过最大高度时才滚动。
- 视觉风格回到轻量、克制、阅读友好的版本。
- 鼠标移动到边缘或角落时显示对应 resize cursor。
- 用户可拖住边缘或角落调整大小。
- 调整大小不得影响保存单词、播放发音、关闭浮窗等既有操作。

### F3 — 功能稳定性

以下用户路径必须保持可用：

- 打开、切换 PDF。
- 翻译选中文本并保存单词。
- AI 解释选区并保存 AI 回复为笔记。
- 笔记合并、删除和下划线恢复。
- 自由标注恢复。
- Reading Inspector 列表跳转。
- 单词/笔记管理页跳转。
- 窗口恢复和阅读位置恢复。

## 5. 验证策略

本版本保留更有实际价值的验证：

- Rust：`cargo fmt --check`、`cargo clippy -- -D warnings`、`cargo test`。
- Swift：`xcodebuild build` 作为编译和 target 集成验证。
- 前后对比：生成 baseline/after markdown 和 HTML 报告。
- UI：关键路径以 smoke 和人工验收为主；Browser 只用于查看本地 HTML 报告。

Swift XCTest/XCUITest target 在本版本删除。删除原因是当前测试主要覆盖浅层 UI 可见性和少量刚抽出的 Swift helper，维护成本高，且 macOS accessibility 环境不稳定，不能稳定表达真实 PDFKit 行为。

## 6. 验收标准

- App 可以通过 macOS build。
- Rust core 检查通过。
- 前后对比报告可以生成并打开。
- `PDFReaderView.swift` 明显缩小，阅读相关职责下沉到 `Reader/` 和 Inspector 子模块。
- Rust translation、LLM、DB repo 重复逻辑减少。
- Inspector 标签、顺序和面板职责符合 `单词 | 笔记 | AI`。
- Swift 测试 target 和测试文件从项目中移除。
- 版本号更新到 `1.0.14` / `14`。

