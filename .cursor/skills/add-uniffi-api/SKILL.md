---
name: add-uniffi-api
description: 为 LumenPDF 添加一个新的跨语言 API（UniFFI 桥接）。当需要新增 Rust → Swift 接口或扩展 BridgeService 时使用。
---

# 添加 UniFFI API

Proc-macro only，没有 UDL 文件。

### 1. Rust

`lumen-pdf-core/src/interfaces/api.rs`：

```rust
#[uniffi::export]
pub fn do_something(input: String) -> Result<MyResult, LumenError> {
    // 组装仓库或 domain service，不要另起 Tokio runtime
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn do_something_async(request: MyRequest) -> Result<MyResult, LumenError> {
    ...
}
```

新数据类型用 `#[uniffi::Record]`。新模块：`domain/` 实体 + trait，`infrastructure/` 实现。不要加 application 用例包装层。

### 2. 构建

```bash
make build-rust
```

不要手改 `LumenPDF/Generated/`。

### 3. Swift

在 `BridgeService.swift` 包一层，调用方只走 `BridgeService`。
