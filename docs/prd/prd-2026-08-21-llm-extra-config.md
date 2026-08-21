---
version: unreleased
date: 2026-08-21
tdd: tdd/tdd-2026-08-21-llm-extra-config.md
predecessor:
  - prd/prd-2026-07-16-llm-configuration-discovery.md
  - prd/prd-2026-08-20-llm-settings-persistence.md
  - prd/prd-2026-08-21-llm-disable-thinking.md
---

# LumenPDF — LLM Extra Config 与 API Key 入口 PRD

## 1. 产品结论

设置里的 Extra Config 是用户看得见、改得了的请求附加字段。关闭 thinking 的厂商字段由系统按服务商写入 Extra Config 默认值；用户没改就用默认，改了就用用户的。不再在请求里偷偷加字段，也不再追加 `/no_think`。编辑器做 JSON 语法着色，并在编辑结束和保存时自动格式化。每个内置服务商在 LLM 配置表单外右下角给出官方申请链接。

## 2. 问题

各家网关的 thinking、预算、采样字段并不统一。把关 thinking 藏在请求拼装里，用户看不到也改不了；只靠 Extra Config 又不填时，thinking 会重新打开。JSON 挤在一行也不好改。

## 3. 功能需求

### F1 — Extra Config

- LLM 设置页在服务商、Base URL、API Key、模型同一张配置卡片内、模型字段下方提供 Extra Config 编辑器，内容为 JSON 对象，可为空。不单独成节。
- 未保存过用户值时，编辑器显示当前 Base URL / 模型对应的系统默认（关闭 thinking 的那一套字段）。OpenAI / Gemini 默认是空。
- 用户改过并保存后，用用户的 JSON；切换服务商时按 Base URL 隔离，互不覆盖。
- 清空并保存表示恢复系统默认；保存 `{}` 表示不附加任何字段。
- 只改编辑框、不点「保存设置」不会进入下一次请求。
- 每次单词翻译、整句翻译、AI 导读、图片能力探测的 `/chat/completions` 都把 Extra Config 合并进请求体。未保存用户值时合并系统默认。
- 同名键以 Extra Config 为准，对象字段深度合并。
- 不得用 Extra Config 改写 `messages`、`stream`、`stream_options`。
- 非法 JSON、非对象、或包含上述保留键时，保存失败并在设置页保存栏说明原因。
- Extra Config 不是密钥，可写入偏好设置；不写入 Keychain。
- 不在用户消息里追加 `/no_think`。

### F1b — JSON 编辑器

- Extra Config 使用内置轻量 JSON 编辑器：键、字符串、数字、`true`/`false`/`null` 与括号用不同颜色。
- 合法 JSON 在编辑结束（失焦）和保存时自动格式化（缩进、键排序）。不合法时保持原文，方便继续改。

### F2 — 官方 API Key 链接

- 每个内置服务商都有官方获取 API Key 的 https 链接。
- 当前 Base URL 匹配内置服务商时，LLM 配置表单外右下角显示「获取 {服务商} API Key」，点击在浏览器打开该链接。不插入表单行之间。
- 自定义 Base URL 不显示该链接。

## 4. 非目标

- 不在界面提供单独的 thinking 开关；默认字段就在 Extra Config 里。
- 不校验 Extra Config 里的厂商字段是否被网关接受。
- 不把 Extra Config 用于 `/models` 列表请求。
- 不引入第三方代码编辑器依赖。

## 5. 验收标准

1. 百炼或 IdeaLab、未改 Extra Config 时，请求带 `"enable_thinking": false`，消息不含 `/no_think`。
2. Extra Config 改成 `{"enable_thinking": true}` 并保存后，请求用 `true`。
3. 保存 `{}` 后，请求不再带系统默认的 thinking 字段。
4. Extra Config 在 LLM 配置卡片内、模型字段下方；打开时已是格式化后的 JSON，键有语法着色。
5. 填写数组或带 `messages` 的对象时无法保存，保存栏说明原因。
6. 选择任一内置服务商，表单外右下角能打开对应官方申请页。
7. 完全退出再打开，同一 Base URL 下用户改过的 Extra Config 仍在；未改过的仍显示系统默认。
