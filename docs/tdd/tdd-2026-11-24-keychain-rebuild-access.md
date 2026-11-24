---
version: unreleased
date: 2026-11-24
prd: prd/prd-2026-11-24-keychain-rebuild-access.md
predecessor:
  - tdd/tdd-2026-07-02-reading-context-sidebar.md
  - tdd/tdd-2026-07-13-v1016-reader-selection-overlays.md
  - tdd/tdd-2026-08-21-selection-settings-feedback.md
  - tdd/tdd-2026-10-13-app-update.md
---

# 换包后 API Key 不再要钥匙串密码

## 边界

| 模块 | 职责 |
| --- | --- |
| `CredentialVaultCodec` | AES-GCM 封装 / 打开；密钥由本机 `IOPlatformUUID` 派生 |
| `CredentialVaultStore` | 把封装结果写到 `AppDataDirectory` 下 `llm-api-key.vault`，权限 `0600` |
| `KeychainService` | 读写以 vault 为准；data-protection 钥匙串尽力而为；登录钥匙串只作无界面迁移 |
| `KeychainInteraction` | 所有 `SecItem` 调用期间关闭钥匙串交互，禁止 SecurityAgent 弹窗 |

Swift 视图仍不直接碰文件或钥匙串。本次不改 Rust、数据库或 UniFFI。

## 关键规则

登录钥匙串的 file-based 条目会把 ACL 绑到当前二进制签名。ad-hoc 重签后 `SecItemCopyMatching` 会弹出登录密码，且 `kSecUseAuthenticationUIFail` 挡不住。因此：

1. `save` 必须先写入 vault。vault 成功即视为已保存。
2. data-protection 写入成功更好，失败不回退到 file-based 登录钥匙串，也不让保存失败。
3. `load` 先读 vault。没有文件时，在关闭交互的前提下尝试 data-protection 和旧 file-based 条目；读到则迁移进 vault。读不到就当没有 Key。
4. 旧 file-based 条目仅在无界面可读时删除。
5. 不把 API Key 写入 `UserDefaults`，不恢复 App Sandbox 来换 entitlement。

## 验证

- `CredentialVaultCodecTests`：同一机器标识可往返；换标识或篡改密文打不开；密文不含明文 Key。
- `KeychainItemQueryTests`：既有查询键与 `-34018` 文案保持不变。
- 运行中的 App 验收：保存 Key 后用新 ad-hoc 包覆盖安装，启动不弹钥匙串密码，设置页仍能读到 Key。编译不能代替这项验收。
