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

设置里的 LLM 配置必须允许用户填写 **Extra Config**（JSON 对象），合并进每次 chat 请求，用来覆盖我们内置逻辑照顾不到的厂商参数。每个内置服务商都要在 API Key 旁给出**官方获取 API Key 的链接**。

## 2. 问题

各家网关的 thinking、预算、采样字段并不统一。只靠内置映射会漏。用户还得自己去搜申请 Key 的页面。

## 3. 功能需求

### F1 — Extra Config

- LLM 设置页提供 Extra Config 编辑框，内容为 JSON 对象，可为空。
- 保存后按当前 Base URL 记住；切换服务商时加载该地址下已保存的 Extra Config，互不覆盖。只改编辑框、不点「保存设置」不会进入下一次请求。
- 每次单词翻译、整句翻译、AI 导读、图片能力探测的 `/chat/completions` 都把 Extra Config 合并进请求体。
- 同名键以用户填写的为准，对象字段深度合并。
- 不得用 Extra Config 改写 `messages`、`stream`、`stream_options`。
- 非法 JSON、非对象、或包含上述保留键时，保存失败并在设置页保存栏说明原因。
- Extra Config 不是密钥，可写入偏好设置；不写入 Keychain，也不出现在调用日志的可复制密钥位置。

### F2 — 官方 API Key 链接

- 每个内置服务商都有官方获取 API Key 的 https 链接。
- 当前 Base URL 匹配内置服务商时，API Key 输入旁显示「获取 {服务商} API Key」，点击在浏览器打开该链接。
- 自定义 Base URL 不显示该链接。

## 4. 非目标

- 不在界面提供 thinking 开关；需要时由 Extra Config 自行填写。
- 不校验 Extra Config 里的厂商字段是否被网关接受。
- 不把 Extra Config 用于 `/models` 列表请求。

## 5. 验收标准

1. 填写 `{"thinking_budget": 0}` 并保存后，下一次翻译请求体带有该字段。
2. Extra Config 里的 `enable_thinking` 覆盖内置关闭 thinking 的同名字段。
3. 填写数组或带 `messages` 的对象时无法保存，保存栏说明原因。
4. 选择任一内置服务商，API Key 旁能打开对应官方申请页。
5. 完全退出再打开，同一 Base URL 下的 Extra Config 仍在。
