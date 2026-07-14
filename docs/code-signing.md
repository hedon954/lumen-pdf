# LumenPDF 代码签名与 Keychain 延续

LumenPDF 把 API Key 保存在 macOS data-protection Keychain。重新安装后是否仍被系统视为同一个应用，取决于新旧版本是否具有一致、可验证的代码签名身份；service 名称本身不能替代签名身份。

## 本机签名身份

按以下优先级选择长期身份：

1. Developer ID Application：用于正式分发。
2. Apple Development：用于已加入 Apple Developer 团队的本机开发。
3. 固定自签名 Code Signing 证书：只用于同一台开发机，不用于公开分发。

可在 Xcode 的 Accounts / Manage Certificates 中创建 Apple Development 证书。没有 Apple 身份时，也可以在“钥匙串访问 → 证书助理 → 创建证书”中创建名为 `LumenPDF Local Development`、Identity Type 为 Self Signed Root、Certificate Type 为 Code Signing 的固定证书。证书和私钥必须保留在登录钥匙串中；删除后重新创建会形成新的应用身份。

确认可用身份：

```bash
security find-identity -v -p codesigning
```

打包脚本默认使用 ad-hoc 签名。需要使用已有身份时可以显式指定：

```bash
SIGN_IDENTITY=<certificate-sha1-or-name> make upgrade
```

使用非默认钥匙串时，同时传入：

```bash
SIGNING_KEYCHAIN=/path/to/signing.keychain-db \
SIGN_IDENTITY=<certificate-sha1-or-name> \
make dmg
```

没有稳定身份时，脚本会生成 ad-hoc 包。二进制变化后它不保证跨重装读取旧 Keychain 条目，系统可能要求再次授权。

## GitHub Release Secrets

Release workflow 默认使用 ad-hoc 签名。若后续配置稳定签名身份，可通过 `SIGN_IDENTITY` 和 `SIGNING_KEYCHAIN` 复用同一打包路径。

## 安全边界

- 主应用只使用一个 data-protection Keychain 条目。
- 旧 file-based 条目仅在无需认证 UI 即可读取时迁移；无法读取时由用户重新输入一次 API Key。
- 不把旧条目的 ACL 扩大为任意应用可访问。
- 嵌套 dylib 与主应用使用同一身份从内到外签名。
- 发布包最终签名刻意不包含 `LumenPDF.entitlements` 或 App Sandbox entitlement，以继续使用 `~/Library/Application Support/LumenPDF` 和全局 `UserDefaults` 中已有的数据。若未来重新启用 Sandbox，必须在同一版本提供并验证无损数据库与偏好迁移。

验证最终产物：

```bash
codesign --verify --deep --strict --verbose=2 build/export/LumenPDF.app
codesign -dvvv --entitlements :- build/export/LumenPDF.app
codesign -dvvv build/export/LumenPDF.app/Contents/Frameworks/liblumen_pdf_core.dylib
```
