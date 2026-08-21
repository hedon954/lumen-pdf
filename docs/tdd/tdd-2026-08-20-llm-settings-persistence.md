---
version: unreleased
date: 2026-08-20
prd: prd/prd-2026-08-20-llm-settings-persistence.md
predecessor:
  - tdd/tdd-2026-07-16-llm-configuration-discovery.md
  - tdd/tdd-2026-08-14-ai-settings-notes.md
successor:
  - tdd/tdd-2026-08-21-selection-settings-feedback.md
---

# LumenPDF — LLM 设置跨重启持久化 TDD

## 1. 技术结论

保存路径必须先把 API Key 写入 data-protection Keychain，再把 Base URL / 模型写入 `UserDefaults`，成功后再热更新 Rust 运行时配置。Keychain 写入失败要抛错，且不得改偏好设置。读写 Key 时用与请求相同的 Base URL 规范化结果作为 vault 主键，并兼容旧条目中未带 `/v1` 的别名。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `LLMSettingsStore` | 显式写入/读取 `llm_base_url`、`llm_model`；空 Base URL 不得填成 OpenAI 默认值。 |
| `LLMEndpointIdentity` | 规范化后的端点身份；判断是否同一服务商；给出 Keychain 查找别名。 |
| `SettingsRuntimeService.persistAndUpdateConfig` | 「保存设置」：落盘 → Keychain → `updateLlmConfig`。 |
| `KeychainItemQuery` | 搜索 query 与 `SecItemAdd` 属性分开；Add 不得带 `kSecUseAuthenticationUI` 等查询专用键。 |
| `LLMAPIKeyVault` | 按规范化 Base URL 存 Key；读取时容忍旧别名。 |
| `LLMConfigurationSection.selectBaseURL` | 同一端点身份时只同步 URL 文本，不覆盖模型或 API Key。 |

## 3. 保存与加载

```text
保存设置
  → 校验提示词
  → 规范化 Base URL / 模型
  → KeychainService.saveLLMAPIKey（失败则抛错，不改 UserDefaults，不显示已保存）
  → LLMSettingsStore.persist(baseURL, model)
  → BridgeService.updateConfig
  → 记录最近 Base URL / 模型历史

启动 / 打开设置
  → 非空 Base URL 先规范化
  → loadLLMAPIKey(for: normalizedBaseURL)
  → 运行时 initializeIfNeeded 读同一对 UserDefaults + Keychain
```

语言或提示词热更新仍只调用 `updateConfig`，不把设置页里可能尚未保存的 API Key 写回 Keychain。

## 4. Keychain 写入

`SecItemUpdate` 使用带 `kSecUseAuthenticationUIFail` 的搜索 query。`SecItemAdd` 只包含 class / service / account / data-protection / accessible / value。Add 返回 duplicate 时再 Update。`save` 失败抛出 `KeychainServiceError`，不再 `return` 后继续显示成功。后续修订：失败文案与展示位置见 [tdd-2026-08-21-selection-settings-feedback.md](tdd-2026-08-21-selection-settings-feedback.md)；`-34018` 时改写同一条 file-based 条目，见同文档。

## 5. 验证

- `LLMSettingsStoreTests`：规范化写入、再次读取、空 Base URL 不填默认值。
- `LLMEndpointIdentityTests`：OpenAI 有无 `/v1` 视为同一端点；查找键包含旧别名。
- `LLMAPIKeyVaultTests`：无 `/v1` 写入后可用 `/v1` 读回；旧 vault 别名仍能加载。
- `KeychainItemQueryTests`：Add 属性不含搜索专用键，且带 `kSecAttrAccessibleWhenUnlocked`。

运行时必须在 macOS App 中确认：保存后退出再启动，设置页与实际请求仍使用新 API Key 和模型。本环境无法运行原生 UI，编译不能代替这项验收。
