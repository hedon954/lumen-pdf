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

## Key Files

- PRD: `docs/prd/prd-2026-03-22.md`
- TDD: `docs/tdd/tdd-2026-03-22.md`
- Build script: `scripts/build-rust.sh`
- Swift bridge: `LumenPDF/Services/BridgeService.swift`
- Rust API entry: `lumen-pdf-core/src/interfaces/api.rs`
