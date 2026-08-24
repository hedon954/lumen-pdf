---
version: unreleased
date: 2026-08-24
prd: prd/prd-2026-08-24-llm-provider-other.md
predecessor:
  - tdd/tdd-2026-07-16-llm-configuration-discovery.md
  - tdd/tdd-2026-08-21-llm-extra-config.md
related:
  - tdd/tdd-2026-08-24-codebase-simplification.md
---

# LumenPDF — LLM 服务商「其他」TDD

## 1. 技术结论

服务商选择从当前 Base URL 推导，而不是封闭枚举强制吸附到某个预设。`LLMProviderPreset.matching` 只比较规范化后的完整地址；对不上就视为「其他」。选择「其他」不调用内置预设写入；从内置改回「其他」时，只恢复本次会话记下的上一份未匹配地址。Extra Config 默认值只走 Rust `thinking_control` / UniFFI `default_extra_config`，Keychain 仍按 `LLMEndpointIdentity`，都不按「其他」另存一份。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `LLMProviderPreset.matching` | 规范化 Base URL 与内置 `baseURL` 精确比较；不就近匹配 host。 |
| `LLMProviderPickerSelection` | 解析当前选中项（内置 / 其他）；选择「其他」时决定是否恢复上一份自定义地址。 |
| `LLMConfigurationSection` | 菜单在「内置服务商」后固定展示「其他」；选择内置仍走 `selectBaseURL`；选择「其他」不套预设。 |
| `LLMThinkingExtraConfig` | 设置页展示包装：调用 `BridgeService.defaultExtraConfig` 后 pretty-print。未知主机默认空 JSON，除非 Rust 启发式命中。 |

## 3. 选择规则

```text
preferOther == true
        → 其他
规范化 Base URL 命中某个 LLMProviderPreset.baseURL
        → 该内置项
否则
        → 其他
```

- 菜单 tag：`provider:{id}` 或 `other`。未匹配地址的当前选中项是 `other`，不是「最近使用」里的 URL tag。
- 选择内置：`selectBaseURL(preset.baseURL)`，按端点身份切换 API Key / Extra Config，模型取该地址历史或保留当前值。
- 选择「其他」且当前已是未匹配地址：不改字段。
- 选择「其他」且当前命中内置、同时记有上一份未匹配地址：切回那份地址，并按该地址读取草稿/Keychain/已存 Extra Config。
- 选择「其他」且没有可恢复的自定义地址：保留当前字段，不写入任何预设。

`matching` 使用 `LLMConfigurationHistory.canonicalBaseURLKey`（去空白、去尾斜杠、小写），不把 `https://api.deepseek.com/v1/proxy` 或不同 host 当成 DeepSeek。

## 4. Extra Config 与密钥

- 切换端点时 Extra Config 仍按 Base URL 草稿和 `LLMSettingsStore` 隔离。
- 未知主机 + 普通模型名：Rust `default_extra_config_json` 为空；Swift 不再复制 host/模型规则。
- 未知主机但模型名命中 Qwen / GLM / DeepSeek 启发式时，仍用 Rust 原表，不因菜单是「其他」而改成 `{}`。
- Keychain 主键仍是规范化 Base URL，不因选中「其他」换成另一个 account。

## 5. 验证

### 自动测试

- `LLMProviderPickerSelectionTests`
  - 未匹配 Base URL → `.other`
  - 内置地址（含尾斜杠）→ 对应预设，不是 `.other`
  - 选择「其他」且已是自定义：不恢复、不重置
  - 选择「其他」且无上一份自定义：不返回新地址
  - 从内置选回「其他」：恢复上一份自定义 URL
  - 选择内置仍得到该预设 Base URL
- `thinking_control`：未知主机默认 Extra Config 为空，除非模型启发式命中（与设置页同源，不在 Swift 再断言一份）

### 运行时验证

本环境无法运行 macOS 应用。合并前须在真实 Mac 上打开设置 → LLM 点一遍：

1. 打开服务商菜单，内置列表之后能看到「其他」。
2. 选 DeepSeek（或当前内置），Base URL / Extra Config 按预设变化。
3. 再选「其他」，当前字段不被预设清空；把 Base URL 改成自定义地址后，菜单勾在「其他」。
4. 从自定义地址改选某个内置，再选回「其他」，刚才的自定义 Base URL 回来。
5. 填写自定义地址与 Key，刷新模型列表仍可请求 `/models`；右下角不出现官方申请链接。
6. 保存后重启，自定义地址、模型、Key、Extra Config 仍按该 Base URL 读回。
