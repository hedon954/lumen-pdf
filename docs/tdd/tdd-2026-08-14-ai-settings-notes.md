# LumenPDF — AI 阅读、设置与笔记删除 TDD

**版本**: v1.0.22 · **日期**: 2026-08-14

## 文档关系

- 对应 PRD：[`prd-2026-08-14-ai-settings-notes.md`](../prd/prd-2026-08-14-ai-settings-notes.md)
- 前序：[阅读 Inspector TDD](tdd-2026-07-03-reading-inspector.md) · [LLM 配置发现 TDD](tdd-2026-07-16-llm-configuration-discovery.md) · [阅读 AI 输入 TDD](tdd-2026-07-16-reading-ai-input-selection.md)
- 后续：[v1.0.23 TDD](tdd-2026-08-15-settings-usage-overlay.md)
- 索引：[`docs/README.md`](../README.md)

## 1. 技术结论

本版本以 Swift 设置/导读/笔记层为主，Rust 侧配合提示词模板升级与调用日志所需字段。凭据继续只走 Keychain，不新增文件型密钥存储。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `ReadingGuidePanel.swift` / `GuideConversationPolicy` | 原文卡片展开策略、失败态覆盖、原位重试请求。 |
| `PromptTemplateValidator` / `PromptTemplateUpdateCoordinator` | 动态变量校验；未改动的系统模板自动升版。 |
| `SettingsView.swift` / `SettingsPages.swift` | 侧边栏设置、提示词子页。 |
| `LLMCallLogStore.swift` | 持久化阅读相关调用审计。 |
| `LLMAPIKeyVault` / `KeychainService.swift` | 按 Base URL 隔离的 data-protection Keychain 项。 |
| `PDFReaderView.swift` 笔记回顾 | 单条 `NoteTextList.removingItem` 或整组删除，并同步划线。 |

## 3. 关键行为

- 导读失败后重试必须复用同一消息身份，用成功结果替换失败气泡，而不是再追加一条。
- 提示词保存路径：先校验变量，再写入；自定义语言模板跳过自动覆盖。
- `LLMCallLogStore` 只记录用户触发的阅读/翻译/导读请求，不把内部探测算作用户审计（探测过滤在 v1.0.23 收口）。
- 删除笔记时：空剩余内容则 `deleteNote` + 移除划线；否则只 `updateNote`。

## 4. 验证

- `PromptTemplateValidatorTests`、`PromptTemplateUpdateCoordinatorTests`
- `LLMAPIKeyVaultTests`、`LLMCallLogStoreTests`
- `GuideConversationPolicyTests`
- 笔记删除路径的人工验收：回顾浮窗、Inspector、PDF 划线三者一致
