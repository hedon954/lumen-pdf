---
version: v1.0.36
date: 2026-11-24
prd: prd/prd-2026-11-24-local-upgrade.md
predecessor:
  - tdd/tdd-2026-06-25-v109.md
---

# 本机升级只做有变化的步骤

## 边界

| 入口 | 行为 |
| --- | --- |
| `make upgrade` | `LUMEN_ARCH=host LUMEN_PACKAGE_DMG=0` 再跑 `upgrade-local.sh` |
| `make dmg` | 默认 `LUMEN_ARCH=universal`、`LUMEN_PACKAGE_DMG=1`，发布流程不变 |

`upgrade-local.sh` 仍从 `build/export/LumenPDF.app` 安装，不挂载 DMG。

## 关键规则

- 本机升级只 `cargo build --release` 当前架构。发布才编 `aarch64` 和 `x86_64`；两份产物都不比已有 universal dylib 新时跳过 `lipo`。
- UniFFI 用将要嵌入应用的 dylib 的 sha256 做戳。戳没变就不跑 bindgen。生成时只读单架构库：本机用当前架构，发布用 `aarch64`，不读 `lipo` 之后的双架构文件。生成到临时目录，内容与 `Generated/` 相同则不覆盖，避免 Swift 增量编译失效。
- `xcodegen` 之后若 `project.pbxproj` 字节相同，把修改时间改回去。
- 本机升级用 `xcodebuild build`，`ONLY_ACTIVE_ARCH=YES`，DerivedData 固定在 `build/DerivedData`。发布仍用 `xcodebuild archive`。
- 组装 `.app` 前对比未签名产物和 dylib 的哈希。哈希相同且已有签名通过验证时，不重新拷贝、不重新签名。
- DMG 用同一哈希做戳。戳相同且文件还在时不跑 `hdiutil`。
- `upgrade-local.sh` 在结束进程之前比较主二进制和 dylib。相同则直接退出。

## 验证

- `bash -n scripts/package-dmg.sh` 与 `bash -n scripts/upgrade-local.sh`。
- `make -n upgrade` 应先以 `LUMEN_ARCH=host LUMEN_PACKAGE_DMG=0` 调用 `package-dmg.sh`，再调用 `upgrade-local.sh`，且不再依赖 `dmg` 目标。
- 不在这里实际执行 `make upgrade`：它会替换 `/Applications/LumenPDF.app`。
