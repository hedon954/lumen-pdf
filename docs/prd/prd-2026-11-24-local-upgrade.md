---
version: v1.0.36
date: 2026-11-24
tdd: tdd/tdd-2026-11-24-local-upgrade.md
predecessor:
  - prd/prd-2026-06-25-v109.md
---

# 本机升级只做有变化的步骤

## 问题

`make upgrade` 每次都编两套架构、重新归档，再压缩一个用不上的 DMG。代码没改也要等完这一整条发布链路。

## 用户行为

- `make upgrade` 只编译当前 Mac 的架构，把 `.app` 装到 `/Applications`。不制作 DMG。
- Rust、UniFFI 绑定、Xcode 工程和 Swift 编译都沿用已有产物。输入没变就不重写文件、不重编。
- 这次构建和已经装上的副本是同一个二进制时，不结束正在运行的应用，也不再拷一次。
- `make dmg` 仍然产出双架构 DMG，给发布用。两套架构都没有重编时，不重新 `lipo`，应用内容没变时不重新压缩 DMG。

## 非目标

不改应用内检查更新，也不让本机升级包变成可分发的双架构安装包。

## 验收

1. 连续两次 `make upgrade`，第二次不编另一套 CPU 架构，不调用 `hdiutil`；二进制相同时不结束正在运行的 LumenPDF。
2. 只改 Swift、Rust dylib 没变时，不重新生成 UniFFI 绑定。
3. `make dmg` 仍产出 `build/LumenPDF-<version>.dmg` 和对应的 `.sha256`。
