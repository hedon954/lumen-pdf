# CLAUDE.md

LumenPDF：macOS PDF 阅读器（翻译、划线、笔记、单词本、AI 导读）。

```
SwiftUI / PDFKit  →  BridgeService  →  UniFFI  →  interfaces  →  domain ← infrastructure
```

当前规格：[`docs/product.md`](docs/product.md)（行为）、[`docs/architecture.md`](docs/architecture.md)（实现）。不要再新增 dated PRD/TDD，不要改 `docs/archive/`。

## 命令

```bash
make setup          # 首次
make build-rust     # Rust + Swift 绑定
cd lumen-pdf-core && cargo test
make gen-project    # 改过 project.yml 之后
make dmg
```

## 约定

- Commit：`type(scope): 中文摘要`，正文非空、中文。Agent 作者保持 `Codex <codex@openai.com>`，除非用户指定别人。
- 分支（给人看的 PR）：`<type>/<scope>-<topic>-<YYYYMMDD-HHmm>`，不要 `codex/`、`claude/`、`agent/` 当前缀。
- 发布：用仓库里的 release-tag skill。版本在 `LumenPDF/Info.plist`。`CHANGELOG.md` 中文，带 commit URL；tag 说明与 changelog 对齐。

## 实现约束（短）

- `domain/` 零 I/O（无 reqwest/rusqlite/r2d2）。翻译编排在 domain service；笔记/单词/文库由 `interfaces/api.rs` 调仓库。
- Swift 不直接 SQLite/HTTP。跨语言只走 `BridgeService`。
- Extra Config 默认值只在 Rust `thinking_control.rs`。
- 覆盖层放在阅读窗口共同祖先；不要为了躲裁切开 NSPanel。
- 稳定布局（窗口、分栏、视口）一份状态；不要平行 UserDefaults 键。
- Keychain 一项：`com.LumenPDF.app` / `llm_api_key`。`-34018` 时写普通钥匙串。不要重新打开 App Sandbox。
- 新 UniFFI：`#[uniffi::export]`（无 UDL）→ `make build-rust` → `BridgeService`。全局只有 `POOL` 和 `LLM_CONFIG`。
- Schema 只改 `infrastructure/db/migration.rs`，可重复执行。
- `PDFKitView` Coordinator 不要拆成多个共享可变状态的文件。
- Linux 只跑 `cargo fmt/clippy/test`。UI 未在 Mac 上点过就写明未验证。

细节、文件地图、不要动的边界：`docs/architecture.md`。
