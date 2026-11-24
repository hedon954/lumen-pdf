---
version: v1.0.36
date: 2026-11-24
tdd: tdd/tdd-2026-11-24-keychain-rebuild-access.md
predecessor:
  - prd/prd-2026-07-02-reading-context-sidebar.md
  - prd/prd-2026-07-13-v1016-reader-selection-overlays.md
  - prd/prd-2026-08-21-selection-settings-feedback.md
  - prd/prd-2026-10-13-app-update.md
---

# 换包后 API Key 不再要钥匙串密码

## 问题

每次重新构建、重新安装 DMG，启动或保存设置都会弹出登录钥匙串密码框。ad-hoc 签名每次都是新身份，系统把旧条目当成别的应用在访问。

## 用户行为

- API Key 仍然只保存在本机，不进 `UserDefaults`，也不出现在日志里。
- 保存一次之后，重新编译、重新下载 DMG、覆盖安装，启动时直接用已保存的 Key，不再弹出钥匙串密码框。
- 读不到旧钥匙串条目时也不弹窗。设置页里的 Key 为空，用户再保存一次即可，之后同样不再弹窗。
- 保存失败仍只在设置页保存栏用日常中文说明，不出现状态码，也不要求重新安装。

## 非目标

不重新启用 App Sandbox，不把 API Key 写成明文配置，不要求用户准备稳定代码签名身份才能避免弹窗。

## 验收

1. 保存 API Key 后退出，用新的 ad-hoc DMG 覆盖安装再打开，翻译和设置里的 Key 仍在，过程中不出现钥匙串密码框。
2. 本机 `make upgrade` 换掉 `/Applications` 里的副本后再启动，同样不弹窗。
3. 若本机只有旧钥匙串条目且系统拒绝无界面读取，启动不弹窗；在设置里再保存一次后，之后的重装也不弹窗。
