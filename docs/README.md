# LumenPDF 产品与技术文档

PRD 记录**用户可感知的行为与验收标准**。TDD 记录**如何实现这些行为**、模块边界和自动化验证。两者成对维护；配对与演进只在本文索引，各文件用 YAML frontmatter 记录版本、日期、对应文档、前序和后续。

维护规则见 [`CLAUDE.md`](../CLAUDE.md) 中的「PRD 与 TDD」。

## 怎么读

1. 先看对应主题最新一份 PRD，再看 frontmatter 里的 `tdd`。
2. 若行为被后续版本改写，以 frontmatter 的 **`successor`** 为准；前序文档保留当时的产品结论，条款级变化在正文用「后续修订」标注。
3. 发布说明在 [`CHANGELOG.md`](../CHANGELOG.md)，不替代 PRD/TDD。

## 配对总表

| 版本 | 日期 | 主题 | PRD | TDD |
| --- | --- | --- | --- | --- |
| v1.0.0 | 2026-03-22 | 产品与架构基线 | [prd-2026-03-22.md](prd/prd-2026-03-22.md) | [tdd-2026-03-22.md](tdd/tdd-2026-03-22.md) |
| 基线补丁 | 2026-03-24 ~ 03-27 | 翻译卡片、首次配置引导 | 同上 | [03-24](tdd/tdd-2026-03-24.md) · [03-25](tdd/tdd-2026-03-25.md) · [03-26](tdd/tdd-2026-03-26.md) · [03-27](tdd/tdd-2026-03-27.md) |
| v1.0.2 | 2026-03-30/31 | 错误展示、句子翻译、笔记划线 | [prd-2026-03-31.md](prd/prd-2026-03-31.md) | [tdd-2026-03-30-optimization.md](tdd/tdd-2026-03-30-optimization.md) |
| v1.0.3 | 2026-03-31 | 迁移与稳定性 | [prd-2026-03-31-v103.md](prd/prd-2026-03-31-v103.md) | [tdd-2026-03-31-v103.md](tdd/tdd-2026-03-31-v103.md) |
| v1.0.4 | 2026-05-06 | 流式翻译 | [prd-2026-05-06-v104.md](prd/prd-2026-05-06-v104.md) | [tdd-2026-05-06-v104.md](tdd/tdd-2026-05-06-v104.md) |
| v1.0.5 | 2026-05-06 | 翻译与缓存体验 | [prd-2026-05-06-v105.md](prd/prd-2026-05-06-v105.md) | [tdd-2026-05-06-v105.md](tdd/tdd-2026-05-06-v105.md) |
| v1.0.9 | 2026-06-25 | 阅读与设置迭代 | [prd-2026-06-25-v109.md](prd/prd-2026-06-25-v109.md) | [tdd-2026-06-25-v109.md](tdd/tdd-2026-06-25-v109.md) |
| v1.0.11 | 2026-06-26 | 窗口与交互优化 | [prd-2026-06-26-v1011.md](prd/prd-2026-06-26-v1011.md) | [tdd-2026-06-26-v1011.md](tdd/tdd-2026-06-26-v1011.md) |
| v1.0.12 | 2026-07-02 | 阅读上下文与 AI 导读 | [prd-2026-07-02-reading-context-sidebar.md](prd/prd-2026-07-02-reading-context-sidebar.md) | [tdd-2026-07-02-reading-context-sidebar.md](tdd/tdd-2026-07-02-reading-context-sidebar.md) |
| v1.0.13 | 2026-07-03 | 阅读 Inspector | [prd-2026-07-03-reading-inspector.md](prd/prd-2026-07-03-reading-inspector.md) | [tdd-2026-07-03-reading-inspector.md](tdd/tdd-2026-07-03-reading-inspector.md) |
| v1.0.14 | 2026-07-04 | 重构与验证收口 | [prd-2026-07-04-v1014-refactor-automation.md](prd/prd-2026-07-04-v1014-refactor-automation.md) | [tdd-2026-07-04-v1014-refactor-automation.md](tdd/tdd-2026-07-04-v1014-refactor-automation.md) |
| v1.0.15 | 2026-07-10 | 阅读浮层与划线回顾 | [prd-2026-07-10-note-overlay-optimization.md](prd/prd-2026-07-10-note-overlay-optimization.md) | [tdd-2026-07-10-note-overlay-optimization.md](tdd/tdd-2026-07-10-note-overlay-optimization.md) |
| v1.0.16 | 2026-07-13 | 选区控件与窗口延续 | [prd-2026-07-13-v1016-reader-selection-overlays.md](prd/prd-2026-07-13-v1016-reader-selection-overlays.md) | [tdd-2026-07-13-v1016-reader-selection-overlays.md](tdd/tdd-2026-07-13-v1016-reader-selection-overlays.md) |
| v1.0.19 | 2026-07-16 | LLM 配置发现 | [prd-2026-07-16-llm-configuration-discovery.md](prd/prd-2026-07-16-llm-configuration-discovery.md) | [tdd-2026-07-16-llm-configuration-discovery.md](tdd/tdd-2026-07-16-llm-configuration-discovery.md) |
| v1.0.19 | 2026-07-16 | 阅读 AI 输入与选区 | [prd-2026-07-16-reading-ai-input-selection.md](prd/prd-2026-07-16-reading-ai-input-selection.md) | [tdd-2026-07-16-reading-ai-input-selection.md](tdd/tdd-2026-07-16-reading-ai-input-selection.md) |
| v1.0.20 | 2026-08-05 | 阅读位置恢复与浮窗拖动 | [prd-2026-08-05-viewport-restore-overlay-drag.md](prd/prd-2026-08-05-viewport-restore-overlay-drag.md) | [tdd-2026-08-05-viewport-restore-overlay-drag.md](tdd/tdd-2026-08-05-viewport-restore-overlay-drag.md) |
| v1.0.21 | 2026-08-09 | 选区浮层统一定位 | [prd-2026-08-09-selection-overlay-placement.md](prd/prd-2026-08-09-selection-overlay-placement.md) | [tdd-2026-08-09-selection-overlay-placement.md](tdd/tdd-2026-08-09-selection-overlay-placement.md) |
| v1.0.22 | 2026-08-14 | AI 阅读、设置与笔记删除 | [prd-2026-08-14-ai-settings-notes.md](prd/prd-2026-08-14-ai-settings-notes.md) | [tdd-2026-08-14-ai-settings-notes.md](tdd/tdd-2026-08-14-ai-settings-notes.md) |
| v1.0.23 | 2026-08-15 | 用量统计、设置打磨与根层浮窗 | [prd-2026-08-15-settings-usage-overlay.md](prd/prd-2026-08-15-settings-usage-overlay.md) | [tdd-2026-08-15-settings-usage-overlay.md](tdd/tdd-2026-08-15-settings-usage-overlay.md) |
| v1.0.24 | 2026-08-19 | 跨页划线与失败诊断 | [prd-2026-08-19-markup-diagnostics.md](prd/prd-2026-08-19-markup-diagnostics.md) | [tdd-2026-08-19-markup-diagnostics.md](tdd/tdd-2026-08-19-markup-diagnostics.md) |
| v1.0.25 | 2026-08-20 | 文库封面与翻译重新生成 | [prd-2026-08-20-library-cover-translation-retry.md](prd/prd-2026-08-20-library-cover-translation-retry.md) | [tdd-2026-08-20-library-cover-translation-retry.md](tdd/tdd-2026-08-20-library-cover-translation-retry.md) |
| v1.0.26 | 2026-08-20 | 笔记自动保存与翻译浮窗位置稳定 | [prd-2026-08-20-note-autosave-overlay-stability.md](prd/prd-2026-08-20-note-autosave-overlay-stability.md) | [tdd-2026-08-20-note-autosave-overlay-stability.md](tdd/tdd-2026-08-20-note-autosave-overlay-stability.md) |
| unreleased | 2026-08-20 | LLM 设置跨重启持久化 | [prd-2026-08-20-llm-settings-persistence.md](prd/prd-2026-08-20-llm-settings-persistence.md) | [tdd-2026-08-20-llm-settings-persistence.md](tdd/tdd-2026-08-20-llm-settings-persistence.md) |
| unreleased | 2026-08-21 | 选区标题误入与设置保存反馈 | [prd-2026-08-21-selection-settings-feedback.md](prd/prd-2026-08-21-selection-settings-feedback.md) | [tdd-2026-08-21-selection-settings-feedback.md](tdd/tdd-2026-08-21-selection-settings-feedback.md) |
| unreleased | 2026-08-21 | 工作区 Cmd+F 搜索 | [prd-2026-08-21-workspace-search.md](prd/prd-2026-08-21-workspace-search.md) | [tdd-2026-08-21-workspace-search.md](tdd/tdd-2026-08-21-workspace-search.md) |
| unreleased | 2026-08-21 | 划线按行区间合并 | [prd-2026-08-21-markup-interval-merge.md](prd/prd-2026-08-21-markup-interval-merge.md) | [tdd-2026-08-21-markup-interval-merge.md](tdd/tdd-2026-08-21-markup-interval-merge.md) |
| unreleased | 2026-08-21 | LLM 关闭 thinking | [prd-2026-08-21-llm-disable-thinking.md](prd/prd-2026-08-21-llm-disable-thinking.md) | [tdd-2026-08-21-llm-disable-thinking.md](tdd/tdd-2026-08-21-llm-disable-thinking.md) |
| unreleased | 2026-08-21 | LLM JSON 修复 | [prd-2026-08-21-llm-json-repair.md](prd/prd-2026-08-21-llm-json-repair.md) | [tdd-2026-08-21-llm-json-repair.md](tdd/tdd-2026-08-21-llm-json-repair.md) |
| unreleased | 2026-08-21 | LLM Extra Config 与 API Key 入口 | [prd-2026-08-21-llm-extra-config.md](prd/prd-2026-08-21-llm-extra-config.md) | [tdd-2026-08-21-llm-extra-config.md](tdd/tdd-2026-08-21-llm-extra-config.md) |
| unreleased | 2026-08-21 | 调用日志完整 HTTP 请求 | [prd-2026-08-21-llm-call-log-http-request.md](prd/prd-2026-08-21-llm-call-log-http-request.md) | [tdd-2026-08-21-llm-call-log-http-request.md](tdd/tdd-2026-08-21-llm-call-log-http-request.md) |
| unreleased | 2026-08-24 | Extra Config 单源与未用 UniFFI 收缩 | [prd-2026-08-24-codebase-simplification.md](prd/prd-2026-08-24-codebase-simplification.md) | [tdd-2026-08-24-codebase-simplification.md](tdd/tdd-2026-08-24-codebase-simplification.md) |
| unreleased | 2026-08-24 | LLM 服务商「其他」 | [prd-2026-08-24-llm-provider-other.md](prd/prd-2026-08-24-llm-provider-other.md) | [tdd-2026-08-24-llm-provider-other.md](tdd/tdd-2026-08-24-llm-provider-other.md) |
| unreleased | 2026-08-25 | 搜索模糊、翻译 AI 快捷入口与跨页笔记划线 | [prd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md](prd/prd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md) | [tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md](tdd/tdd-2026-08-25-reader-overlay-shortcuts-cross-page-notes.md) |

未单独成对的发布：

- v1.0.17 取消 App Sandbox、继续使用历史数据目录：见 [code-signing.md](code-signing.md) 与 `CLAUDE.md` 签名约束。
- v1.0.18 右侧栏开关/拖拽过渡：延续 [v1.0.16](prd/prd-2026-07-13-v1016-reader-selection-overlays.md) 的视口与分栏恢复。

## 主题演进

### 阅读浮层与定位

```text
v1.0.15 公共窗口外壳
  → v1.0.16 选区操作栏归属与窗口恢复
  → v1.0.20 拖动手柄与关闭命中
  → v1.0.21 统一定位（下/上/右/左/最小遮挡）
  → v1.0.23 翻译浮窗提升到阅读窗口根层
  → v1.0.26 首次定位后锁定原点，内容变高不再换边跳位
  → unreleased 小节标题不因正文复述而进入翻译原文
```

v1.0.21 曾要求内容变高后重新换边避让；2026-08-20 修订为「首次位置固定」，以 v1.0.15 的稳定方向为优先体验。

### 笔记

```text
v1.0.2 笔记 + 划线
  → v1.0.12 / v1.0.13 侧栏与 Inspector 展示
  → v1.0.15 原文回顾浮窗、删除、空内容禁止提交
  → v1.0.22 回顾浮窗内删除单条/全部
  → v1.0.26 Inspector、回顾浮窗、笔记列表可编辑并自动保存
  → unreleased ⌘F 工作区搜索覆盖笔记、单词、划线、原文与 AI 解释
  → unreleased 邻近新划线不再抹掉未选中的旧行
  → unreleased 笔记保存逐页选区，跨页划线可重启恢复
```

### 划线与高亮

```text
v1.0.0 Toggle：包围盒重叠则合并或整段取消
  → v1.0.24 跨页逐页落笔、页眉页脚
  → unreleased 按文本行一维区间合并，禁止用多行包围盒误删上一行
  → unreleased 自由标注与笔记标注共用逐页载荷，笔记持久化完整跨页几何
```

### LLM 与 AI 导读

```text
v1.0.12 / v1.0.13 导读进入 Inspector
  → v1.0.19 配置发现、词源、多模态追问
  → v1.0.22 失败原位重试、提示词校验、调用审计、Keychain
  → v1.0.23 Token 热点图与设置反馈
  → v1.0.24 空响应诊断、追问串行、跨页划线
  → v1.0.25 翻译刷新/重新生成
  → unreleased 保存设置后 API Key 与模型跨重启仍在
  → unreleased 设置保存失败只在设置页保存栏提示；ad-hoc 安装可写入钥匙串
  → unreleased 当前导读会话可经 ⌘F 检索
  → unreleased 按服务商关闭 thinking；字段改为 Extra Config 默认值，去掉 /no_think
  → unreleased 期望 JSON 的模型输出先 json repair 再解析
  → unreleased Extra Config 显示关 thinking 默认值；去掉 /no_think；JSON 着色，回车缩进，画笔才整段格式化
  → unreleased Extra Config 默认值只在 Rust 计算，设置页不再复制 host/模型规则
  → unreleased 调用日志可展开实际发出的完整 HTTP 请求（密钥脱敏）
  → unreleased 服务商菜单增加「其他」，未匹配内置地址时不误标厂商，自定义端点不被预设覆盖
  → unreleased 翻译成功 footer 增加 AI 解释快捷入口，复用当前选区导读
```

## 其他文档

- [instruction.md](instruction.md)：最初产品意图
- [code-signing.md](code-signing.md)：签名与 Keychain
- [plan/plan-2026-06-08-native-highlight.md](plan/plan-2026-06-08-native-highlight.md)：历史计划，非正式需求源
