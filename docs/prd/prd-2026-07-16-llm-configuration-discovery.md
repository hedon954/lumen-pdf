# PRD - 2026-07-16：LLM 配置发现与快速选择

## 背景

当前设置页要求用户手动填写 Base URL 和模型名称。即使用户使用常见厂商，也需要自行查找并准确复制配置；模型升级或下线后，还需要重新访问厂商文档确认名称。

本功能将 LLM 配置升级为“可编辑、可发现、可复用”的交互：内置常见服务商 Base URL，根据当前服务商和 API Key 获取最新模型列表，同时保留完全自定义的 OpenAI-compatible 配置能力。

## 目标

1. 常见厂商可以快速选择，无需手动记忆 Base URL。
2. 在厂商提供兼容接口时，从服务端获取当前账号实际可用的模型。
3. Base URL 和模型始终允许手动输入，不把用户限制在内置选项中。
4. 记住用户主动使用过的自定义 Base URL，以及每个 Base URL 下使用过的模型。
5. 模型列表获取失败不影响用户保存配置或继续使用现有模型。

## 非目标

- 不在客户端维护一份容易过期的完整模型清单。
- 不根据模型名称猜测价格、上下文长度或多模态能力。
- 不校验模型一定能够完成翻译、JSON 输出或图片理解；具体能力仍由模型调用结果判断。
- 不把 API Key 保存到 `UserDefaults`、历史记录或日志。
- 不支持需要厂商专属签名协议、控制面凭证或非 OpenAI-compatible 调用方式的模型发现接口。

## 用户故事

- 作为阿里百炼用户，我希望选择“阿里云百炼（北京）”后自动填入正确的 Base URL。
- 作为多厂商用户，我希望输入 API Key 后刷新模型列表，并直接选择当前账号可用的模型。
- 作为自建网关用户，我希望继续手动输入 Base URL 和模型，不受预设列表限制。
- 作为经常切换模型的用户，我希望下次回到同一个 Base URL 时可以快速选择之前使用过的模型。
- 当厂商没有模型列表接口时，我希望看到明确提示，但仍能手动配置和保存。

## 功能需求

### FR1：服务商预设

- 设置页提供“服务商”下拉菜单。
- 内置常用 OpenAI-compatible Base URL：
  - OpenAI
  - 阿里云百炼北京、新加坡
  - DeepSeek
  - OpenRouter
  - Google Gemini
  - 硅基流动
  - 智谱开放平台
  - MiniMax 中国
  - 火山方舟
- 选择预设后自动填写 Base URL。
- 用户仍可直接编辑 Base URL；不匹配内置预设时显示为自定义配置。
- 厂商地址变化时通过应用版本更新预设，不远程覆盖用户当前配置。

### FR2：动态模型列表

- 模型名称保持为可编辑文本框。
- Base URL、API Key 和模型行已有固定标签，不再在输入框内部重复显示示例或字段名占位。
- 提供模型下拉入口、搜索框和手动刷新按钮。
- 默认使用 `GET {normalizedBaseURL}/models` 获取模型列表。
- 请求使用当前 API Key 的 Bearer 认证；不需要认证的服务商允许无 Key 请求。
- 支持 OpenAI-compatible 的 `data[].id` 返回格式，并兼容常见的 `models[]` 或字符串列表。
- 模型按名称排序并去重。
- 设置页打开时：
  - API Key 非空则自动获取一次模型列表。
  - 对已知允许匿名读取模型的服务商，可在 API Key 为空时自动获取。
- 切换服务商后获取对应模型列表。
- 请求期间显示加载状态，成功后显示模型数量。

### FR3：失败降级

- 401/403 提示检查 API Key 与 Base URL。
- 404 提示当前地址没有兼容的模型列表接口。
- 网络错误、限流、返回格式不兼容等错误均显示简短原因。
- 所有获取失败都不得清空用户当前已填写的模型。
- 获取失败时模型文本框、保存按钮和历史模型仍可使用。

### FR4：自定义历史

- 保存设置、提交文本框或切换服务商前，记录当前非空 Base URL 和模型。
- 最近使用的自定义 Base URL 出现在服务商菜单的“最近使用”分组。
- 模型历史按规范化 Base URL 分组，避免不同厂商的模型混在一起。
- 同一 Base URL 或模型重复使用时移动到最前，不产生重复项。
- 历史记录设置数量上限，避免无限增长。
- 不记录 API Key。

### FR5：现有配置兼容

- 继续使用现有 `llm_base_url`、`llm_model` 和 Keychain `llm_api_key`。
- 不迁移、不重置已有用户配置。
- 保存后继续通过现有运行时配置热更新链路立即生效。
- Base URL 规范化规则与实际 LLM 请求保持一致。

## 安全与隐私

- API Key 只从内存和现有 Keychain 条目读取。
- 模型列表请求只发送到用户当前配置的 Base URL。
- 不记录请求头、API Key 或完整服务端响应。
- 历史记录只保存 Base URL 和模型名称。
- 自定义 Base URL 代表用户明确选择的网络目标，不在后台轮询未选中的厂商。

## 验收标准

1. 用户可从内置服务商中选择并自动填入对应 Base URL。
2. 用户可随时直接修改 Base URL 和模型名称。
3. 对支持 `/models` 的厂商，输入有效 API Key 后可获取、搜索并选择模型。
4. 模型列表失败时保留当前模型，并明确提示仍可手动输入。
5. 保存自定义 Base URL 和模型后，重新打开设置页仍能在最近历史中找到。
6. 不同 Base URL 的模型历史互不混淆。
7. API Key 仍只保存在 Keychain，不出现在 `UserDefaults` 和日志中。
8. 保存设置后运行中的翻译与解释请求立即使用新配置。

## 参考接口

- OpenAI Models：<https://platform.openai.com/docs/api-reference/models>
- 阿里云百炼 Base URL：<https://help.aliyun.com/en/model-studio/base-url>
- DeepSeek Models：<https://api-docs.deepseek.com/api/list-models>
- OpenRouter Models：<https://openrouter.ai/docs/api/api-reference/models/get-models>
- Gemini OpenAI compatibility：<https://ai.google.dev/gemini-api/docs/openai>
- SiliconFlow Models：<https://docs.siliconflow.cn/en/api-reference/models/get-model-list>
