---
version: v1.0.34
date: 2026-10-13
prd: prd/prd-2026-10-13-app-update.md
predecessor:
  - tdd/tdd-2026-06-25-v109.md
---

# 应用内检查更新并原地替换

## 边界

版本比较、稳定版选择、发布地址和校验解析在 Rust domain。GitHub 发布列表的读取在 infrastructure。Swift 只负责 macOS 上的下载、挂载、替换和重新打开。检查更新不依赖 LLM 初始化。

| 模块 | 职责 |
| --- | --- |
| `domain/update` | 解析 `1.0.33` / `v1.0.33`，按数字比较；只选最新的非草稿、非预发布版本；磁盘映像必须叫 `LumenPDF-<version>.dmg`，校验文件必须叫 `LumenPDF-<version>.dmg.sha256` |
| `infrastructure/update` | 请求最近 20 条 `api.github.com/repos/hedon954/lumen-pdf/releases`，拒绝跳转到官方发布主机以外的地址 |
| `AppUpdateCenter` | 启动检查间隔、菜单和设置共用的状态 |
| `AppUpdateInstaller` | 下载、SHA-256、`hdiutil`、退出后替换 |

官方发布资源的起始地址必须是 `https://github.com/hedon954/lumen-pdf/releases/download/<tag>/<file>`，且不能带查询串。下载过程中的跳转只允许 `github.com` 的上述路径，以及 `objects.githubusercontent.com`、`release-assets.githubusercontent.com`、`github-releases.githubusercontent.com`。

校验正文接受单独一行 64 位十六进制，或 `shasum` 的 `摘要  文件名`。文件名存在时必须是这次的磁盘映像。

发布说明先去掉首尾空白，再保留最多 8000 个字符。

## 替换顺序

1. 下载到临时目录并比对 SHA-256。不一致就删除安装包。
2. 用当前 bundle 路径、卷是否只读、父目录是否可写判断能不能原地替换。路径含 `/AppTranslocation/` 时视为系统隔离，优先于只读和权限。
3. 不能原地替换时，把已校验的 DMG 复制到「下载」并在 Finder 中显示。
4. 能替换时挂载 DMG，确认其中 `LumenPDF.app` 的 `CFBundleShortVersionString` 与发布版本一致，再复制到临时目录并卸载映像。
5. 写出 `swap.sh`，用 `nohup` 脱离当前进程。脚本等当前 pid 自己退出，让已有的退出保存先写完阅读位置，再把原 bundle 改名为 `LumenPDF.app.previous`，并用 `ditto` 放入新副本。`ditto` 失败时把旧副本移回。成功后去掉 `com.apple.quarantine`，删除备份，并 `open` 新副本。30 秒内进程仍未退出则放弃替换。
6. 下次启动删除 `.previous` 和临时目录里的 `LumenPDF-update-*`。日志写在 `~/Library/Logs/LumenPDF/update.log`。

`scripts/package-dmg.sh` 在 DMG 旁写出只含摘要的 `.dmg.sha256`。Release workflow 把这两个文件一起传到 GitHub Release。没有校验文件的发布不会被安装。

## 验证

- `cargo test --lib update` 覆盖版本顺序、稳定版选择、不受信任的地址、缺失的磁盘映像或校验、校验正文，以及发布 JSON 的解析。
- `AppUpdatePolicyTests` 覆盖原地替换判断、自动检查间隔，以及 `hdiutil` plist 里的挂载点。
- 下载、挂载、替换和重新打开需要在 macOS 上对已安装的应用验收。本次没有运行中的 App，不能把编译或单元测试当作界面验收。
