# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LumenPDF is a macOS PDF reader with context-aware translation, native annotations, and vocabulary management. The architecture is:

```
SwiftUI (PDFKit) → Mozilla UniFFI → Rust (DDD layers)
```

## Build Commands

```bash
# First-time setup
make setup

# Rebuild Rust + regenerate Swift bindings (after Rust changes)
make build-rust

# Run Rust unit tests
cd lumen-pdf-core && cargo test

# Run domain-layer tests only
cd lumen-pdf-core && cargo test domain

# Regenerate Xcode project (after project.yml changes)
make gen-project

# Package DMG
make dmg
```

## Release Process Notes

- Use `$release-tag` for release closeout work: version bumps, AI-authored changelog entries with commit URLs, release commits, annotated tags, and post-tag checks.
- Keep annotated tag messages aligned with the matching changelog section: include the version title, a concise user-facing release summary, and a pointer to `CHANGELOG.md`; do not use a version-only message.
- `CHANGELOG.md` is maintained before tagging. The release workflow reads the matching version section as the GitHub Release body; it must not generate or commit changelog content.
- Write changelog entries in Chinese and include GitHub commit URLs for the concrete changes covered by each version.
- Version bumps live in `LumenPDF/Info.plist`:
  - `CFBundleShortVersionString` is the public version, for example `1.0.9`.
  - `CFBundleVersion` is the internal build number, for example `9`.
- User-facing release labels, tags, DMG filenames, and docs should normally use only the short version (`1.0.9`). Include the build number only when debugging or explicitly discussing build metadata.
- When asked to commit, push, and tag a release, commit the code/docs/version/changelog changes, push the branch, create an annotated `vX.Y.Z` tag, and push the tag.

## Pull Request Branch Naming

Every branch intended to open a PR must use a unique, semantic name. Do not use agent or tool names as branch names or prefixes.

Format:

```text
<type>/<scope>-<short-topic>-<YYYYMMDD-HHmm>
```

Rules:

- Use a Conventional Commit type: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`, or `revert`.
- Use a short lowercase scope and topic in kebab-case. The name must describe the actual change.
- Append the local creation time in `YYYYMMDD-HHmm` format so parallel tasks do not collide.
- Never use generic or agent-specific names such as `codex/*`, `claude/*`, `agent/*`, `feature`, `fix`, or `temp`.
- Do not reuse an existing remote branch for an unrelated task. If the semantic name already exists, create a new branch with the current timestamp.
- Release-only branches may use `release/vX.Y.Z`.

Examples:

```text
feat/reader-image-input-20260716-2215
fix/settings-prompt-migration-20260716-2230
docs/repo-branch-naming-20260716-2245
release/v1.0.20
```


## Git Commit Message Convention

All new commits must use Conventional Commits so release notes, history, and GitHub views stay readable. Keep the `type(scope):` prefix in English, and write the summary after the colon in Chinese.

Format:

```text
<type>(<scope>): <summary>

<body>
```

Rules:

- Use lowercase `type`. Allowed types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`, `revert`.
- Use a short lowercase scope when it clarifies the affected area, for example `reader`, `notes`, `sidebar`, `bridge`, `core`, `release`, or `docs`.
- Write the summary in Chinese, without a trailing period, and keep the first line under 72 characters when practical.
- Every commit must include a non-empty body, including small changes and `docs`/`chore` commits. Separate the summary and body with one blank line.
- Write the body in Chinese. Explain the motivation or context and the key behavior or impact. Do not merely repeat the summary.
- Do not include verification, build, or test results in the commit message body. Report them separately in the PR description or task summary.
- Mark breaking changes with `!` after the type/scope and include a `BREAKING CHANGE:` footer.
- Agent-authored commits should keep the Codex git identity (`Codex <codex@openai.com>`) unless the user explicitly requests another author.

Examples:

```text
feat(reader): 增加阅读上下文侧栏

统一承载单词、笔记和 AI 导读，减少阅读过程中在多个页面间切换。

fix(notes): 保留划线笔记追加顺序

修复追加笔记后排序发生变化的问题，确保同一划线下的内容按创建顺序展示。

docs(readme): 说明 Gatekeeper 处理方式

补充首次安装时处理未签名应用提示的步骤，避免用户误以为安装失败。

chore(release): 更新版本到 1.0.12

同步应用公开版本号和内部构建号，为 1.0.12 发布做准备。
```

## Pre-commit Checks

Before every git commit, these checks run automatically via `.pre-commit-config.yaml`:

- `cargo fmt --check`
- `cargo clippy -- -D warnings`
- `cargo test`

Install pre-commit hooks:

```bash
brew install pre-commit
pre-commit install
```

Or run `make setup` which handles this automatically.

## Architecture

### Engineering Design Principles

Code should stay simple, understandable, maintainable, iterable, and free of avoidable duplication. Use SOLID as a constraint for reducing complexity, not as a reason to add abstract layers.

- **Single responsibility**: Views handle layout and event forwarding; ViewModels/models coordinate state; coordinators/controllers handle PDFKit/AppKit work; services handle persistence, bridge calls, and LLM calls.
- **Open/closed**: Add new reading panels or workflows through small, explicit components and model state instead of adding more branches to oversized views such as `PDFReaderView` or `TranslationBubble`.
- **Liskov substitution**: Introduce protocols only when there is a real alternate implementation or test boundary. Do not create empty abstractions just to look architectural.
- **Interface segregation**: Pass only the data and callbacks a component needs. Avoid handing broad objects like the whole `AppState` or large request structs to narrow UI components.
- **Dependency inversion**: SwiftUI Views must not call `BridgeService.shared` directly. Inject narrow closures, models, or services for side effects.
- **KISS**: Prefer native SwiftUI/AppKit controls and layout behavior over custom hit-testing, cursor, or resize machinery unless the native option cannot satisfy the interaction.
- **No redundancy**: Keep one source of truth for shared logic such as note grouping, Markdown rendering, AI reply saving, selection bounds parsing, and viewport restoration.
- **Small boundaries**: Treat 300-500 lines as a soft limit for new Swift files. If a file grows beyond that, check whether responsibilities are mixed before adding more code.
- **Testable logic**: Put pure behavior in UI-independent types where practical, especially note grouping, message compression, save-state calculation, and selection matching.
- **Incremental migration**: Refactors must keep the app buildable and behaviorally stable at each step. Prefer small reversible commits over broad rewrites.

### DDD Layer Constraints (Strict)

| Layer | Directory | Constraint |
|-------|-----------|------------|
| interfaces | `src/interfaces/` | Only `#[uniffi::export]` functions + dependency injection |
| application | `src/application/` | Use case orchestration; no direct SQL/HTTP |
| domain | `src/domain/` | Zero external I/O dependencies (no reqwest/rusqlite) |
| infrastructure | `src/infrastructure/` | Implements domain traits; no business logic |

**Critical**: `domain/` must not import `reqwest`, `rusqlite`, or `r2d2`. Domain services only depend on trait definitions from the same layer.

### Swift Layer Constraints

- **Views**: Only hold `@StateObject`/`@ObservedObject`; never call `BridgeService` directly
- **Coordinators/Services**: Call `BridgeService`; Views observe via ViewModels
- All UI updates must run on `@MainActor`
- No direct `URLSession`, `sqlite3` in Views or Coordinators

### SwiftUI / AppKit Presentation Boundaries (Strict)

- Keep in-window UI in one SwiftUI hierarchy whenever possible. When an overlay must appear above multiple `NavigationSplitView` columns, lift its state and rendering to their nearest common SwiftUI ancestor before considering AppKit.
- Do not inject arbitrary subviews into `NSHostingView`, and do not introduce an `NSPanel` or child window solely to bypass SwiftUI clipping or local `zIndex`. A separate window is allowed only when the feature is semantically a separate window and SwiftUI cannot express the required behavior.
- Moving a view to another presentation container is a behavioral change, not only a layout change. Before implementation, record and preserve appearance and transparency, coordinate space, hit testing, keyboard focus, inside/outside dismissal, selection ownership, instance uniqueness, attach/update/detach lifecycle, window activation, resizing, moving, minimization, closing, and multi-window behavior.
- Every AppKit bridge must have one explicit owner and deterministic cleanup. Child windows, event monitors, notification observers, delegates, and hosted views must be removed on every dismissal and teardown path.
- If a new bridge requires custom event routing, global identifiers, orphan cleanup, and duplicated state merely to reproduce behavior SwiftUI previously provided, stop and reconsider the abstraction boundary.
- Classify window state as stable or transient before implementation. Persist user-adjusted stable state such as the main window frame, split visibility and split widths, and each document's reader viewport (zoom mode, scale, horizontal offset, and vertical offset); do not restore transient selections, action bars, loading overlays, or editors.
- Collect the complete stable reading workspace in one versioned state model and one persistence manager. Views, view models, window bridges, and PDFKit coordinators may report changes or apply restored values, but must not create parallel `UserDefaults` keys for window frame, split widths, split visibility, active tab, last document, inspector mode, or PDF viewport.
- Treat restoration as an ordered phase, not independent property initialization. While the saved window and split geometry are being applied, initial layout measurements must not overwrite persisted values; only enable geometry capture after the restored layout has settled.
- A persisted split width must be the same explicit state that controls the pane width. If a native SwiftUI split view does not expose a reliable width binding, use one narrow, accessible divider component rather than inferring user intent from private `NSSplitView` ancestry or child geometry.
- Window minimization is a restoration boundary. Freeze stable-layout writes before miniaturization, closing, and termination; keep the last visible split widths unchanged while hidden; then reapply the complete saved layout before reopening width capture after deminiaturization.

### Signing and Keychain Security (Strict)

- Persistent credentials use one Keychain item (`com.LumenPDF.app` / `llm_api_key`). Prefer the data-protection keychain when the current signature can use it. If that write returns `errSecMissingEntitlement` (`-34018`), write the same service/account to the file-based keychain without `SecAccess` or trusted-application ACLs. Do not keep a second live store after a successful data-protection write, and do not re-enable App Sandbox just to obtain the entitlement.
- Packaging may use ad-hoc signing by default. If a stable signing identity is configured, use it consistently for the app and all nested code; do not claim that ad-hoc signing preserves Keychain access across binary replacement.
- After modifying embedded code, sign nested dylibs first and the app last with the same identity. Do not use `codesign --deep` as a signing shortcut.
- Release packages intentionally omit `com.apple.security.app-sandbox` and must not reattach `LumenPDF.entitlements`: the app's existing SQLite database and `UserDefaults` live in the historical non-container locations. Do not re-enable Sandbox unless the same change includes a tested, non-destructive migration for database and preferences.
- CI release jobs follow the same configured signing identity as local packaging and must not add identity-presence gates that block ad-hoc release packaging.

### UI Runtime Verification Gate (Strict)

- A successful build proves compilation only. Do not report a visual or interaction fix as complete until the affected behavior has been exercised in a running app.
- For selection overlays, popovers, floating controls, and split-view chrome, runtime verification must cover normal placement; placement near the left sidebar and right inspector; clicking inside the control; clicking PDF content, sidebar, inspector, and toolbar; creating a second selection; zooming and scrolling while the control is visible; resizing and moving the window; app deactivation and reactivation; and transparency and clipping in both light and dark appearance.
- Changes to the primary reading window or split layout must also be verified across quit and relaunch after moving, live resizing, using the window zoom/tile actions, hiding or resizing each sidebar, changing the active reading tab, manually zooming and panning the PDF in both axes, and disconnecting a display. Restored windows must remain fully visible on the current screens, and the reopened PDF must preserve the same text scale and visible region.
- If runtime or visual verification is unavailable, state that the change is unverified and do not treat compilation as acceptance evidence.
- After the first regression caused by a new presentation or ownership boundary, stop stacking local patches. Revert or reassess the architecture before adding more lifecycle machinery.
- Keep feature fixes separate from unrelated development tooling or workspace configuration unless the user explicitly requests both.

## UniFFI Bridge

The project uses `uniffi::setup_scaffolding!()` in `lib.rs` with proc-macros instead of UDL files:

- Rust types: `#[uniffi::Record]` for data structs
- Rust errors: `#[uniffi::Error]` on enums
- Rust functions: `#[uniffi::export]` (sync) or `#[uniffi::export(async_runtime = "tokio")]` (async)
- Swift bindings auto-generated to `LumenPDF/Generated/`

When adding a new API:
1. Add Rust function with `#[uniffi::export]` in `interfaces/api.rs`
2. Add data types with `#[uniffi::Record]` in domain layer
3. Run `make build-rust` to regenerate Swift bindings
4. Wrap in `BridgeService.swift`

## Global State (interfaces/api.rs)

```rust
static POOL: OnceLock<DbPool> = OnceLock::new();
static LLM_CONFIG: RwLock<Option<LlmConfig>> = RwLock::new(None);
```

New APIs obtain runtime and config from these globals; do not create additional runtimes.

## Domain Unit Testing

Every `domain/*/service.rs` must have a `#[cfg(test)]` module. Tests must not depend on I/O.

- Use inline `struct Fake*` implementations of domain traits
- Run with `cargo test domain`
- Cover: cache hit, LLM success, LLM failure → fallback, both fail

## Translation Fallback Chain

```
SQLite cache → LLM (OpenAI-compatible) → MyMemory API
```

Cache writes only on LLM success; fallback results are not cached.

## Database Schema Changes

All database schema changes must follow these rules:

1. **Forward Compatibility**: New columns must have default values or allow NULL
2. **Use current rusqlite migrations**: Keep migration logic in `lumen-pdf-core/src/infrastructure/db/migration.rs`
3. **Idempotent migration**: Guard every `ALTER TABLE`, table rebuild, and backfill so existing installs can launch repeatedly without data loss
4. **Breaking changes**: If you must drop columns or change types, provide data migration logic to prevent data loss
5. **Testing**: Verify migrations against a copy of an existing SQLite DB before deployment

### Migration Commands

```bash
# Run the migration path through tests
cd lumen-pdf-core && cargo test migration

# Run all DB/domain checks before release
cd lumen-pdf-core && cargo test
```

### Migration Script Example

```sql
-- Adding a new column (forward compatible)
ALTER TABLE notes ADD COLUMN translation TEXT DEFAULT '';

-- Data migration for breaking changes
CREATE TABLE notes_new (
    id TEXT PRIMARY KEY,
    pdf_path TEXT NOT NULL,
    pdf_name TEXT NOT NULL,
    page_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    note TEXT NOT NULL,
    translation TEXT DEFAULT '',
    bounds_str TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

INSERT INTO notes_new SELECT id, pdf_path, pdf_name, page_index, content, note, '', bounds_str, created_at FROM notes;
DROP TABLE notes;
ALTER TABLE notes_new RENAME TO notes;
```

## PRD 与 TDD

产品行为与实现边界写在 `docs/prd/` 和 `docs/tdd/`。配对表与主题演进只写在 [`docs/README.md`](docs/README.md)，不要在每份 PRD/TDD 正文里再链回索引。

### 何时必须更新

用户可感知的行为变化、交互规则变化、或模块边界/持久化/桥接变化，必须在**同一份 PR** 里更新或新增成对的 PRD 与 TDD。不能只改代码、不改文档。

包括但不限于：阅读浮层定位、笔记/单词编辑与保存、Inspector、LLM 设置、翻译失败与重试、窗口/视口恢复、跨页标注。

纯内部重构且用户行为不变时，可只更新 TDD；若发现现有 PRD 描述已过时，仍要改 PRD，并在旧条款旁标注「后续修订」，同时更新双方 frontmatter 的 `successor` / `predecessor`。

### 成对与 frontmatter

- 新主题使用相同日期与主题后缀：`docs/prd/prd-YYYY-MM-DD-<topic>.md` 与 `docs/tdd/tdd-YYYY-MM-DD-<topic>.md`。
- 版本、日期、对应文档、前序、后续一律放在 YAML frontmatter，不要写进正文：

```yaml
---
version: v1.0.21          # 未发版写 unreleased
date: 2026-08-09
tdd: tdd/tdd-YYYY-MM-DD-<topic>.md   # PRD 用 tdd:；TDD 用 prd:
predecessor:
  - prd/prd-YYYY-MM-DD-<prev>.md
successor:
  - prd/prd-YYYY-MM-DD-<next>.md
related:                  # 可选：并行主题或补丁文档
  - tdd/tdd-YYYY-MM-DD-<related>.md
---
```

- 路径相对 `docs/`。无前序或后续时省略对应字段。
- 后一份文档改写了前一份的需求时，不要只在新文档里写新规则。必须在旧文档对应条款旁标注「后续修订」并链到新文档，避免两份 PRD 互相矛盾。
- 更新 [`docs/README.md`](docs/README.md) 配对表和相关主题演进，不要留下未登记的新文件。

### 文档写什么

- PRD：问题、用户可感知行为、非目标、验收标准。不写实现细节。
- TDD：模块边界、关键算法/状态、测试与运行时验收。不重复粘贴整份 PRD。
- `version`：已发布的迭代写 `CFBundleShortVersionString`（如 `v1.0.21`）；尚未发版的写 `unreleased`。

### 禁止

- 不把 CHANGELOG 当作 PRD/TDD 的替代。
- 不新增只在一边存在的 PRD 或 TDD。
- 不删除旧文档来「整理」；用 frontmatter 的 `predecessor` / `successor` 表达演进。
- 不在 PRD/TDD 正文重复版本、日期、对应文档或指向 `docs/README.md` 的索引。

## Key Files

- 文档索引：`docs/README.md`
- 基线 PRD：`docs/prd/prd-2026-03-22.md`
- 基线 TDD：`docs/tdd/tdd-2026-03-22.md`
- Build script: `scripts/build-rust.sh`
- Swift bridge: `LumenPDF/Services/BridgeService.swift`
- Rust API entry: `lumen-pdf-core/src/interfaces/api.rs`
