---
version: unreleased
date: 2026-11-27
prd: prd/prd-2026-11-27-system-proxy.md
predecessor:
  - tdd/tdd-2026-11-25-update-rate-limit.md
---

# 检查更新和翻译跟随系统代理

## 边界

代理选择在 `infrastructure/net/proxy.rs`。`choose_proxy` 不做 I/O：环境变量优先，否则用调用方传入的系统代理。macOS 上每次请求调用 `CFNetworkCopyProxiesForURL`，所以端口和开关都是当时的系统设置，不是进程启动时的快照。

检查更新的客户端和翻译共用的客户端都经过 `configure`。加上 `reqwest` 的 `socks`，才能使用 SOCKS 地址。

| 系统返回 | 实际使用 |
| --- | --- |
| 无代理 | 直连 |
| HTTP 代理，或 HTTPS 隧道代理 | `http://主机:端口`。隧道代理仍是 HTTP CONNECT，不是连到一个 TLS 代理 |
| SOCKS | `socks5h://主机:端口`，域名由代理解析 |
| 自动代理脚本 | 先算出脚本结果，再套用上面的规则 |
| 排除名单命中，例如 `127.0.0.1` | 直连 |

环境变量 `NO_PROXY` 命中时也不查系统代理。`REQUEST_METHOD` 存在时忽略 `HTTP_PROXY`。

## 测试

- 未配置时代理为空。
- HTTP 代理保留调用方给的端口，不替换成某个固定端口。
- SOCKS 使用 `socks5h`。
- `HTTPS_PROXY` 优先于系统代理；目标在 `NO_PROXY` 里时两者都不使用。
- 不带协议的环境变量地址补上 `http://`。
- 排除规则识别域名后缀和 IPv4 网段。
- macOS 上对真实系统设置做一次查询，本机地址得到直连，且查询本身不崩溃。
