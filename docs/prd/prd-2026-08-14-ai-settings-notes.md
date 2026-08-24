---
version: v1.0.22
date: 2026-08-14
tdd: tdd/tdd-2026-08-14-ai-settings-notes.md
prev: prd/prd-2026-08-09-selection-overlay-placement.md
next: prd/prd-2026-08-15-settings-usage-overlay.md
---

# LumenPDF — AI 阅读、设置与笔记删除 PRD

## 1. 产品结论

v1.0.22 把 AI 解释、LLM 设置和笔记回顾收成可完成的闭环：解释原文能自然展开，失败可以原位重试，不同供应商的 API Key 互不覆盖，并提供调用审计与费用估算。笔记回顾浮窗可直接删除单条或当前选区全部笔记。

## 2. 功能需求

### F1 — AI 解释原文与失败重试

- 解释中的原文使用独立卡片；只有超出最大高度才出现展开/收起。
- 展开后由正常布局为后续消息腾出空间，不使用遮挡式 overlay。
- LLM 失败展示具体原因，可原位重试；成功结果覆盖失败状态。

### F2 — 设置信息架构与提示词

- 设置使用系统风格侧边栏；提示词模板在独立子页，并解释全部动态变量。
- 保存前校验缺失、未知或不适用于当前模板的变量。
- 用户未改过的模板跟随新版系统默认值；自定义模板不被覆盖。

### F3 — 调用审计与费用

- 记录阅读相关 LLM 调用：类型、模型、耗时、输入/输出 Token、失败原因。后续修订：详情可展开实际发出的完整 HTTP 请求（密钥脱敏），见 [prd-2026-08-21-llm-call-log-http-request.md](prd-2026-08-21-llm-call-log-http-request.md)。
- 提供 Token 统计与费用估算，便于定位问题和了解成本。

### F4 — 供应商与 Keychain

- 新增 OpenCode Zen 等供应商，并从公开模型目录选择模型。
- 不同 Base URL 的 API Key 存在同一条 data-protection Keychain 凭据中；切换供应商恢复对应 Key。后续修订：保存必须真正写入该凭据，重启后按规范化 Base URL 读回，见 [prd-2026-08-20-llm-settings-persistence.md](prd-2026-08-20-llm-settings-persistence.md)。
- 本次设置会话中尚未保存的输入在切换时保留。

### F5 — 笔记回顾删除

- 笔记回顾浮窗可删除单条笔记，或清空当前选区的全部笔记及关联划线。
- 不强制先打开右侧 Inspector。

## 3. 非目标

- 不把 API Key 写入 `UserDefaults`、历史记录或调用日志正文。
- 不在本版本做 Inspector 内笔记编辑。

## 4. 验收标准

1. 长原文解释可展开，展开后后续消息不被挡住。
2. 失败消息可重试，成功后不再显示失败态。
3. 切换供应商后 API Key 回到该地址上次保存的值。后续修订：完全退出再启动后，当前供应商的 API Key 与模型也必须仍在，见 [prd-2026-08-20-llm-settings-persistence.md](prd-2026-08-20-llm-settings-persistence.md)。
4. 调用日志能看到一次真实阅读请求的模型、耗时和失败原因。
5. 在原文笔记图标打开的回顾窗中删除一条或全部后，列表与 PDF 划线同步更新。
