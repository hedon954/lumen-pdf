---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-llm-extra-config.md
predecessor:
  - tdd/tdd-2026-07-16-llm-configuration-discovery.md
  - tdd/tdd-2026-08-20-llm-settings-persistence.md
  - tdd/tdd-2026-08-21-llm-disable-thinking.md
---

# LumenPDF — LLM Extra Config 与 API Key 入口 TDD

## 1. 技术结论

Extra Config 是一段 JSON 对象字符串，经 UniFFI `AppConfig.llm_extra_config` 进入 `LlmConfig`。发送 chat 请求前用 `extra_config::merge_chat_request` 深度合并进已序列化的请求体。API Key 链接是 `LLMProviderPreset.apiKeyURL`，画在 API Key 输入旁。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `LLMConfigurationSection` | API Key 旁的官方申请链接。 |
| `LLMSettingsPage` Extra Config 区 | JSON 编辑；空表示不合并。 |
| `LLMSettingsStore` | `llm_extra_config_by_base_url`：按规范化 Base URL 存取。 |
| `LLMExtraConfig` | 保存前校验：空、对象、禁止保留键。 |
| `extra_config.rs` | 合并算法；忽略 `messages` / `stream` / `stream_options`。 |
| `LlmTranslator` | `send_chat_request` / `stream_completion` / 图片探测都走合并后的 JSON。 |

## 3. 合并规则

```text
序列化 ChatRequest
若 Extra Config 为空 → 原样发送
否则解析为 object，深度合并，用户标量覆盖内置值
保留键不合并
```

400 重试仍只剥内置 vendor thinking 字段，然后再合并 Extra Config。用户显式写的字段不会在重试时被丢掉。

## 4. 验证

- `extra_config`：空、覆盖、深合并、保留键、非对象报错
- `LLMSettingsStore`：按 Base URL 隔离；`openai.com` 与 `/v1` 读回同一份
- `LLMExtraConfig`：非法 JSON / 数组 / `messages` 不能过校验
- `LLMModelCatalogServiceTests`：每个内置服务商都有 https 官方 Key 链接

本环境无法运行 macOS 设置页。运行时须确认保存后的请求体带上 Extra Config，且 API Key 旁链接可打开。
