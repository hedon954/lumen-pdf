# LumenPDF 演进时间线

当前行为在 [`product.md`](product.md)，当前实现在 [`architecture.md`](architecture.md)。本页只记决策按什么顺序落地，不是现行规格。

每一行对应当时的一份归档 PRD（或仅有 TDD 的基线补丁）。正文冻结在 [`archive/`](archive/README.md)，不要改那些文件。发布说明在 [`CHANGELOG.md`](../CHANGELOG.md)，不替代本时间线。

以后有用户可感知或架构变化时，在表末**追加一行**，并改 `product.md` / `architecture.md`。

| 日期 | 落地 | 当时规格 |
| --- | --- | --- |
| 2026-03-22 | 基线：上下文翻译、原生划线、单词与笔记沉淀 | [PRD](archive/prd/prd-2026-03-22.md) · [TDD](archive/tdd/tdd-2026-03-22.md) |
| 2026-03-24 | 工具栏文件名/页码；多行选区按行标注 | [TDD](archive/tdd/tdd-2026-03-24.md)（补基线 PRD） |
| 2026-03-25 | 翻译失败原因展示；高亮/划线 Cmd+Z | [TDD](archive/tdd/tdd-2026-03-25.md) |
| 2026-03-26 | 单词卡片高度自适应；首次启动弹出 LLM 配置 | [TDD](archive/tdd/tdd-2026-03-26.md) |
| 2026-03-27 | 翻译卡片高度自适应；LLM 配置检查 | [TDD](archive/tdd/tdd-2026-03-27.md) |
| 2026-03-31 | 翻译错误展示、整句翻译、笔记与划线联动 | [PRD](archive/prd/prd-2026-03-31.md) · [TDD](archive/tdd/tdd-2026-03-30-optimization.md) |
| 2026-03-31 | schema 迁移规范、划线颜色、句子翻译保存 | [PRD](archive/prd/prd-2026-03-31-v103.md) · [TDD](archive/tdd/tdd-2026-03-31-v103.md) |
| 2026-05-06 | 翻译改为流式输出 | [PRD](archive/prd/prd-2026-05-06-v104.md) · [TDD](archive/tdd/tdd-2026-05-06-v104.md) |
| 2026-05-06 | 句子流式真正生效；长句拆解 | [PRD](archive/prd/prd-2026-05-06-v105.md) · [TDD](archive/tdd/tdd-2026-05-06-v105.md) |
| 2026-06-25 | 发布链路、笔记 Markdown 展示、PDF 抽词合并 | [PRD](archive/prd/prd-2026-06-25-v109.md) · [TDD](archive/tdd/tdd-2026-06-25-v109.md) |
| 2026-06-26 | 解释先问再答；目标语言切换立即生效 | [PRD](archive/prd/prd-2026-06-26-v1011.md) · [TDD](archive/tdd/tdd-2026-06-26-v1011.md) |
| 2026-07-02 | 阅读页右侧上下文：当前文档单词与笔记；可追问的 AI 导读 | [PRD](archive/prd/prd-2026-07-02-reading-context-sidebar.md) · [TDD](archive/tdd/tdd-2026-07-02-reading-context-sidebar.md) |
| 2026-07-03 | 三栏：目录 · PDF · Inspector；导读迁入右侧 | [PRD](archive/prd/prd-2026-07-03-reading-inspector.md) · [TDD](archive/tdd/tdd-2026-07-03-reading-inspector.md) |
| 2026-07-04 | 阅读页/浮窗/Inspector 与验证收口（无新功能） | [PRD](archive/prd/prd-2026-07-04-v1014-refactor-automation.md) · [TDD](archive/tdd/tdd-2026-07-04-v1014-refactor-automation.md) |
| 2026-07-10 | 翻译/笔记浮层统一窗口规则；划线回顾 | [PRD](archive/prd/prd-2026-07-10-note-overlay-optimization.md) · [TDD](archive/tdd/tdd-2026-07-10-note-overlay-optimization.md) |
| 2026-07-13 | 选区操作栏与笔记快捷按钮；恢复主窗口与阅读布局 | [PRD](archive/prd/prd-2026-07-13-v1016-reader-selection-overlays.md) · [TDD](archive/tdd/tdd-2026-07-13-v1016-reader-selection-overlays.md) |
| 2026-07-16 | LLM 内置服务商、模型列表发现、可复用配置 | [PRD](archive/prd/prd-2026-07-16-llm-configuration-discovery.md) · [TDD](archive/tdd/tdd-2026-07-16-llm-configuration-discovery.md) |
| 2026-07-16 | 词源、跨页选区操作栏、多行追问与图片 | [PRD](archive/prd/prd-2026-07-16-reading-ai-input-selection.md) · [TDD](archive/tdd/tdd-2026-07-16-reading-ai-input-selection.md) |
| 2026-08-05 | 按文本锚点恢复阅读位置；浮窗手柄拖动与关闭 | [PRD](archive/prd/prd-2026-08-05-viewport-restore-overlay-drag.md) · [TDD](archive/tdd/tdd-2026-08-05-viewport-restore-overlay-drag.md) |
| 2026-08-09 | 选区浮层统一定位：下 → 上 → 右 → 左 | [PRD](archive/prd/prd-2026-08-09-selection-overlay-placement.md) · [TDD](archive/tdd/tdd-2026-08-09-selection-overlay-placement.md) |
| 2026-08-14 | 解释原位重试、Keychain 分端点、调用审计；回顾浮窗删笔记 | [PRD](archive/prd/prd-2026-08-14-ai-settings-notes.md) · [TDD](archive/tdd/tdd-2026-08-14-ai-settings-notes.md) |
| 2026-08-15 | Token 热点图；翻译浮窗提到阅读窗口根层 | [PRD](archive/prd/prd-2026-08-15-settings-usage-overlay.md) · [TDD](archive/tdd/tdd-2026-08-15-settings-usage-overlay.md) |
| 2026-08-19 | 跨页划线落在各页正文；失败诊断；导读串行追问 | [PRD](archive/prd/prd-2026-08-19-markup-diagnostics.md) · [TDD](archive/tdd/tdd-2026-08-19-markup-diagnostics.md) |
| 2026-08-20 | 文库封面；翻译刷新/重新生成 | [PRD](archive/prd/prd-2026-08-20-library-cover-translation-retry.md) · [TDD](archive/tdd/tdd-2026-08-20-library-cover-translation-retry.md) |
| 2026-08-20 | 已有笔记自动保存；翻译浮窗首次定位后不再换边 | [PRD](archive/prd/prd-2026-08-20-note-autosave-overlay-stability.md) · [TDD](archive/tdd/tdd-2026-08-20-note-autosave-overlay-stability.md) |
| 2026-08-20 | 保存设置后 API Key 与模型跨重启仍在 | [PRD](archive/prd/prd-2026-08-20-llm-settings-persistence.md) · [TDD](archive/tdd/tdd-2026-08-20-llm-settings-persistence.md) |
| 2026-08-21 | 未高亮的小节标题不进入翻译原文；设置失败只在保存栏提示 | [PRD](archive/prd/prd-2026-08-21-selection-settings-feedback.md) · [TDD](archive/tdd/tdd-2026-08-21-selection-settings-feedback.md) |
| 2026-08-21 | ⌘F 工作区搜索，默认搜笔记和划线 | [PRD](archive/prd/prd-2026-08-21-workspace-search.md) · [TDD](archive/tdd/tdd-2026-08-21-workspace-search.md) |
| 2026-08-21 | 划线按同一文本行的水平区间合并，避免误删邻行 | [PRD](archive/prd/prd-2026-08-21-markup-interval-merge.md) · [TDD](archive/tdd/tdd-2026-08-21-markup-interval-merge.md) |
| 2026-08-21 | 按服务商关闭 thinking，不用 `/no_think` | [PRD](archive/prd/prd-2026-08-21-llm-disable-thinking.md) · [TDD](archive/tdd/tdd-2026-08-21-llm-disable-thinking.md) |
| 2026-08-21 | 期望 JSON 的模型输出先 json repair 再解析 | [PRD](archive/prd/prd-2026-08-21-llm-json-repair.md) · [TDD](archive/tdd/tdd-2026-08-21-llm-json-repair.md) |
| 2026-08-21 | Extra Config 可编辑；关 thinking 默认值写进编辑器 | [PRD](archive/prd/prd-2026-08-21-llm-extra-config.md) · [TDD](archive/tdd/tdd-2026-08-21-llm-extra-config.md) |
| 2026-08-21 | 调用日志可展开脱敏后的完整 HTTP 请求 | [PRD](archive/prd/prd-2026-08-21-llm-call-log-http-request.md) · [TDD](archive/tdd/tdd-2026-08-21-llm-call-log-http-request.md) |
| 2026-08-24 | Extra Config 默认值只保留 Rust 单源；删未走的 UniFFI | [PRD](archive/prd/prd-2026-08-24-codebase-simplification.md) · [TDD](archive/tdd/tdd-2026-08-24-codebase-simplification.md) |
| 2026-08-24 | 服务商菜单增加「其他」，未匹配地址不再误标内置项 | [PRD](archive/prd/prd-2026-08-24-llm-provider-other.md) · [TDD](archive/tdd/tdd-2026-08-24-llm-provider-other.md) |
| 2026-08-24 | 现行规格改为 product / architecture；本表承接演进历史；归档 PRD/TDD 冻结 | 无新 PRD（本页即时间线） |
