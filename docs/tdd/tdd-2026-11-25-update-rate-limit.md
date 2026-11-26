---
version: v1.0.38
date: 2026-11-25
prd: prd/prd-2026-11-25-update-rate-limit.md
predecessor:
  - tdd/tdd-2026-11-24-note-overlay-update.md
---

# 检查更新失败时说明接口错误并可以重试

## 边界

GitHub 响应的分类和原文摘录在 `infrastructure/update`。domain 只把摘录放进 `AppUpdateStatus::Failed.detail`，不解析 HTTP。Swift 把固定说明和 `detail` 拼成面板文字，并在失败时提供重试。

| 模块 | 职责 |
| --- | --- |
| `api_error_detail` | 从失败响应取出 JSON `message`，没有则用正文，前面加上 `HTTP` 状态码。空白折叠，最长 400 个字符 |
| `is_rate_limited` | 429，或 403 且 `x-ratelimit-remaining` 为 0 或存在 `retry-after` |
| `ReleaseFeedError` | `RateLimited(String)` 与 `Unavailable(String)` 都带上这次的具体文字 |
| `AppUpdateCenter` | 手动失败时 `canRetryCheck`，成功或发现更新后清掉。「重试」再走 `checkManually` |

连不上、超时和跳转被拒时，`detail` 用传输层错误原文。发布列表不是 JSON 时，`detail` 说明无法解析并带上正文开头。

## 测试

- `is_rate_limited`：额度用尽的 403、429 为真；仍有剩余次数的 403 和 502 为假。
- `api_error_detail`：GitHub JSON 只保留 `message` 和状态码；空正文只有状态码。
- domain：`RateLimited` 的原文进入 `Failed.detail`，不并进 `FeedUnavailable`。
