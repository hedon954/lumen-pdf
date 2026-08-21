---
version: unreleased
date: 2026-08-20
tdd: tdd/tdd-2026-08-20-llm-settings-persistence.md
predecessor:
  - prd/prd-2026-07-16-llm-configuration-discovery.md
  - prd/prd-2026-08-14-ai-settings-notes.md
successor:
  - prd/prd-2026-08-21-selection-settings-feedback.md
  - prd/prd-2026-08-21-llm-disable-thinking.md
  - prd/prd-2026-08-21-llm-extra-config.md
---

# LumenPDF — LLM 设置跨重启持久化 PRD

## 1. 产品结论

点击「保存设置」后，API Key 和模型必须同时写入持久存储。当前会话的下一次请求要用新配置，完全退出并重新打开应用后，设置页和实际请求仍要使用同一份配置，不能回到保存前的值。

## 2. 问题

用户在设置里改 API Key 和模型后，立刻再请求已经生效，但退出应用再启动，改动消失，看起来像没有保存。

## 3. 功能需求

### F1 — 保存即落盘

- 「保存设置」必须把当前 Base URL、模型写入偏好设置，并把 API Key 写入现有 Keychain 条目。后续修订：同一保存动作还要按 Base URL 写入 Extra Config，见 [prd-2026-08-21-llm-extra-config.md](prd-2026-08-21-llm-extra-config.md)。
- 不能只更新当前进程内存里的 LLM 配置。
- 保存成功后，完全退出并重新打开应用，设置页应显示刚保存的 Base URL、模型和对应供应商的 API Key。

### F2 — 读回使用同一套地址规则

- 保存、启动加载、设置页打开时，按与实际 LLM 请求相同的规则规范化 Base URL，再读写 API Key。
- `https://api.openai.com` 与 `https://api.openai.com/v1` 视为同一服务商地址，不得因此读不到已保存的 Key，也不得把模型清空。

### F3 — 保存失败必须可见

- 若 API Key 未能写入钥匙串，不得显示「设置已保存」或「LLM 配置已生效」。
- 向用户说明保存失败，当前未持久化的改动不能假装已经保存。后续修订：失败原因必须出现在设置页保存栏且可读，不得用主窗口浮窗或钥匙串状态码，见 [prd-2026-08-21-selection-settings-feedback.md](prd-2026-08-21-selection-settings-feedback.md)。

## 4. 非目标

- 不把 API Key 写入 `UserDefaults`、历史记录或调用日志。
- 不改为文件型密钥存储，也不恢复 trusted-application ACL。
- 不改变翻译降级链或模型列表发现交互。

## 5. 验收标准

1. 修改 API Key 和模型并保存后，立即发起翻译或解释，使用新配置。
2. 完全退出再打开应用，设置页仍显示刚保存的 API Key 和模型，而不是空白或旧值。
3. 重启后的翻译/解释请求继续使用保存后的 API Key 和模型。
4. 仅规范化 Base URL（例如补上 `/v1`）时，已保存的 Key 和当前模型仍在。
5. 钥匙串写入失败时，界面提示保存失败，且不出现已保存标记。
