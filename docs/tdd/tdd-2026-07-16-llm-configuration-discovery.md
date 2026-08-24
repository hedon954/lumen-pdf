---
version: v1.0.19
date: 2026-07-16
prd: prd/prd-2026-07-16-llm-configuration-discovery.md
successor:
  - tdd/tdd-2026-08-14-ai-settings-notes.md
  - tdd/tdd-2026-08-20-llm-settings-persistence.md
  - tdd/tdd-2026-08-21-llm-disable-thinking.md
  - tdd/tdd-2026-08-21-llm-extra-config.md
  - tdd/tdd-2026-08-24-llm-provider-other.md
related:
  - tdd/tdd-2026-07-16-reading-ai-input-selection.md
---

# TDD - 2026-07-16：LLM 配置发现与快速选择

## 设计概览

功能保持在 Swift 设置与服务层，不修改 Rust LLM 调用协议。视图只负责布局和事件转发；模型列表请求、状态协调和历史持久化分别放在独立类型中。

| 模块 | 职责 |
| --- | --- |
| `LumenPDF/Views/SettingsView.swift` | 持有当前配置并接入新的 LLM 配置组件；保存时继续热更新运行时配置。 |
| `LumenPDF/Views/LLMConfigurationSection.swift` | 服务商菜单、可编辑 Base URL/API Key/模型、模型搜索下拉、刷新与状态提示。 |
| `LumenPDF/Services/LLMModelCatalogService.swift` | 构造 `/models` 请求、Bearer 鉴权、状态码处理和模型列表解析。 |
| `LumenPDF/Services/LLMConfigurationModel.swift` | `@MainActor` UI 状态、请求生命周期、成功/失败提示和历史模型合并。 |
| `LumenPDF/Services/LLMConfigurationHistory.swift` | 使用 `UserDefaults` 保存最近 Base URL 和按 Base URL 分组的模型历史。 |
| `LumenPDF/Tests/LLMModelCatalogServiceTests.swift` | 覆盖 URL 构造和响应解析。 |
| `LumenPDF/Tests/LLMConfigurationHistoryTests.swift` | 覆盖历史去重、顺序和 Base URL 隔离。 |

## 1. 服务商预设

`LLMProviderPreset` 是只读值类型：

```swift
struct LLMProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
}
```

- 预设只保存厂商名称和 OpenAI-compatible Base URL。后续修订：预设还包含官方 API Key 链接；请求 Extra Config 按 Base URL 持久化并在发送前合并，见 [tdd-2026-08-21-llm-extra-config.md](tdd-2026-08-21-llm-extra-config.md)。
- 当前 Base URL 规范化后与预设比较，决定 Picker 当前选择。后续修订：比较只认规范化后的完整地址，不就近归到某个内置商；菜单固定有「其他」，未匹配时选中它，见 [tdd-2026-08-24-llm-provider-other.md](tdd-2026-08-24-llm-provider-other.md)。
- 自定义 Base URL 不强制映射到厂商。
- 最近使用的自定义地址作为独立分组加入 Picker。

预设不包含模型列表，避免应用版本内的静态模型名称快速过期。

## 2. 模型列表请求

### 2.1 URL 构造

复用 `BridgeService.normalizedLLMBaseURL`，然后在路径末尾追加 `/models`：

```text
https://api.openai.com/v1
→ https://api.openai.com/v1/models

https://dashscope.aliyuncs.com/compatible-mode/v1
→ https://dashscope.aliyuncs.com/compatible-mode/v1/models
```

如果输入已经以 `/models` 结尾，不重复追加。URL 缺少 scheme 或 host 时在发起请求前返回本地错误。

### 2.2 请求

```http
GET {baseURL}/models
Accept: application/json
Authorization: Bearer {apiKey}
```

- API Key 为空时不添加 Authorization。
- 超时为 20 秒。
- 只保留解析后的模型 ID，不缓存完整响应。
- 不输出请求头或 API Key 日志。

### 2.3 响应解析

优先支持标准结构：

```json
{
  "object": "list",
  "data": [
    { "id": "model-id", "object": "model" }
  ]
}
```

兼容：

- `models` 数组；
- 数组元素使用 `id` 或 `name`；
- 字符串模型数组；
- 根节点直接为模型数组。

解析后去除空值、去重并使用本地化名称排序。

### 2.4 错误映射

| 状态 | 用户提示 |
| --- | --- |
| 401/403 | 鉴权失败，请检查 API Key 与 Base URL |
| 404 | 当前地址未提供兼容的模型列表接口 |
| 其他非 2xx | 显示 HTTP 状态和可安全展示的服务端 message |
| 非 HTTP/解码失败 | 显示本地化网络或格式错误 |
| 空列表 | 厂商返回的模型列表为空 |

错误只更新提示状态，不修改绑定的当前模型。

## 3. UI 状态与请求生命周期

`LLMConfigurationModel` 在 `@MainActor` 上维护：

- `fetchedModels`
- `fetchedBaseURLKey`
- `recentBaseURLs`
- `isLoadingModels`
- `modelListMessage`
- `modelListMessageIsError`

每次刷新生成 request ID。只有仍为当前请求的结果可以更新 UI，避免用户快速切换厂商时旧请求覆盖新列表。

下拉模型来源为：

```text
当前 Base URL 的历史模型
        +
当前 Base URL 最新拉取的模型
        +
当前手动输入的模型
        ↓
      去重
```

下拉使用 popover，包含搜索框、模型列表、当前选中标记、模型数量和刷新按钮。模型文本框保持可编辑。

Base URL、API Key 和模型输入框使用左侧 `LabeledContent` 作为可见标签，输入框不再重复设置 placeholder；同时显式保留 accessibility label，避免移除占位文字后影响 VoiceOver。

## 4. 历史持久化

`LLMConfigurationHistory` 使用两个 `UserDefaults` 键：

```text
llm_recent_base_urls
llm_recent_models_by_base_url
```

模型历史结构：

```json
{
  "https://api.openai.com/v1": [
    "gpt-4o-mini",
    "gpt-4.1-mini"
  ]
}
```

Base URL key 的规范化规则：

- 去除首尾空白；
- 去除末尾 `/`；
- 转为小写。

限制：

- 最多保存 12 个 Base URL；
- 每个 Base URL 最多保存 30 个模型；
- 新使用项放在最前；
- 重复项先删除再插入。

历史中不包含 API Key。

## 5. 设置页集成

`SettingsView` 继续通过 `@AppStorage` 持有 Base URL 和模型，通过本地 `@State` 持有 Keychain 读取出的 API Key。

打开设置页时：

1. 从 Keychain 读取 API Key。
2. 把现有 Base URL 和模型加入历史，确保升级后当前配置可立即出现在下拉中。
3. API Key 非空时自动刷新模型。
4. OpenRouter 等允许匿名列出模型的已知服务商可在无 Key 时自动刷新。

保存时：

1. 记录 Base URL 和模型历史。
2. API Key 写入现有 Keychain 条目。
3. 调用 `SettingsRuntimeService.updateConfig` 热更新 Rust 配置。

后续修订：保存顺序改为先写入 Keychain，成功后再写 `UserDefaults` 并热更新运行时；Keychain 失败必须抛错且不得显示已保存。见 [tdd-2026-08-20-llm-settings-persistence.md](tdd-2026-08-20-llm-settings-persistence.md)。

## 6. 测试计划

### 自动测试

- `LLMModelCatalogServiceTests`
  - 为标准 Base URL 正确追加 `/models`；
  - 解析 OpenAI `data[].id`；
  - 解析字符串 `models`；
  - 去重与排序。
- `LLMConfigurationHistoryTests`
  - 最近使用项置顶；
  - 同一 Base URL 去除尾部 `/` 后仍视为同一配置；
  - 不同 Base URL 的模型历史隔离。
- 全量 Xcode 单元测试。

### 运行时验证

1. 打开设置页，现有配置没有被重置。
2. 逐个选择内置服务商，Base URL 正确变化。
3. 使用有效 API Key 刷新模型并从下拉中选择。
4. 搜索模型名称，列表正确过滤。
5. 切换厂商时不会显示前一个厂商的远程模型。
6. 使用错误 API Key 时显示鉴权错误，当前模型仍保留。
7. 使用不支持 `/models` 的自定义网关时仍可手动输入并保存。
8. 关闭并重新打开设置页，自定义 Base URL 与模型历史仍存在。
9. 保存后立即发起翻译或解释，确认运行时使用新配置。

## 7. 已知边界

- `/models` 返回的可能是账号全部模型，不保证都支持当前应用使用的 Chat Completions。
- 部分厂商的模型列表需要专属控制面 API；此类厂商会降级为手动输入。
- 厂商可能返回数量很大的模型列表，因此 UI 提供搜索，不在设置页直接展开所有项目。
- 模型的多模态能力仍由现有能力检测链路判断，不能只依据模型列表中的名称。
