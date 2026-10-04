---
version: unreleased
date: 2026-10-04
prd: prd/prd-2026-10-04-reading-log.md
predecessor:
  - tdd/tdd-2026-03-22.md
---

# 阅读日志

## 边界

- 计时规则全部在 Rust `domain/reading_log`。`ReadingTracker` 是不做 I/O 的状态机，时间（毫秒）由调用方传入。常量：空闲 2 分钟、5 分钟写一行、不足 5 秒不写。
- `ReadingSignal`：`Open`、`Page`、`Input`、`Front`、`Tick`、`Close`、`Quit`。`Front(true)` 和 `Input` 开始计时；空闲后只算到最后一次输入加 2 分钟。`Tick` 在空闲时写出当前一段；任何事件在累计满 5 分钟时写一行。`Front(false)` 只暂停，不写行。`Close`、`Quit` 和打开另一本书都会结束当前一段，并丢弃不足 5 秒的部分；同一 id 再次 `Open` 只更新页码。页码从 0 开始传入，写出时加 1。
- `application/reading_log::ReadingLogUseCase` 把信号交给 tracker，再把产生的行交给 `ReadingLogSink`。
- `infrastructure::JsonlActivityLog` 实现 sink。每批行拼好后，用 `O_APPEND` 打开文件，一次 `write_all` 写入。`log_started` 用 `create_new` 写，文件已存在就跳过。字段顺序固定：
  - `{"v":1,"ts":…,"app":"lumenpdf","action":"log_started"}`
  - `{"v":1,"ts":…,"app":"lumenpdf","id":"<pdf_documents.id>","item":"<路径>","title":"<文件名>","action":"read","started":…,"secs":…,"page":…}`
  - `ts` 是这一段结束的 Unix 秒，`started` 是开始的 Unix 秒，`secs` 是这一段的秒数。
- `interfaces/reading_log_api`：`initialize` 打开数据库后调用 `start_reading_log`，日志放在 `data.db` 同一目录，失败不影响初始化。UniFFI 导出 `record_reading_event(ReadingEvent)`。全局状态用 `Mutex<Option<ReadingLogUseCase>>`，未初始化时忽略事件。
- Swift `ReadingActivityMonitor`（`@MainActor`）只负责采集信号。它监听 App 和窗口的激活、主窗口、最小化变化，以及主窗口的 `PDFViewPageChanged`。本地 `NSEvent` 监视器收集键盘、鼠标和滚动，最多每 5 秒发一次 `Input`。每 15 秒发一次 `Tick`。退出时发 `Quit`。前台判断为：App 激活，主窗口 autosave 名为 `LumenPDFMainWindow` 且未最小化，并且当前是阅读页签。
- `AppState` 在 Rust 初始化后启动 monitor。`selectedDocument` 变化时发 `Open` 或 `Close`，`activeTab` 变化时重新判断前台。`BridgeService.recordReadingEvent` 用 `try?`，写日志出错不打断阅读。

## 验证

- `tracker.rs` 的单元测试覆盖：每行是增量、12 分钟阅读每 5 分钟一行且合计 720 秒、空闲截断、后台和后台输入不计时、不足 5 秒不写、短片段在书开着时并入下一段、换书写出上一本、重开同一本继续计时、没打开书时不写。
- `application/reading_log` 用假 sink 验证用例把行交给 sink。
- `activity_log.rs` 在临时目录验证：每行是合法 JSON 并以换行结尾、字段顺序、没有 `log_started` 时追加也能创建文件。
- Swift 端的前台判断和事件采集需要在运行中的 App 里验收。
