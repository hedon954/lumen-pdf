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

- Do not manually edit `CHANGELOG.md` for releases. It is generated automatically from commits/tags by the release workflow.
- Version bumps live in `LumenPDF/Info.plist`:
  - `CFBundleShortVersionString` is the public version, for example `1.0.9`.
  - `CFBundleVersion` is the internal build number, for example `9`.
- User-facing release labels, tags, DMG filenames, and docs should normally use only the short version (`1.0.9`). Include the build number only when debugging or explicitly discussing build metadata.
- When asked to commit, push, and tag a release, commit the code/docs/version changes, push the branch, create an annotated `vX.Y.Z` tag, and push the tag; leave `CHANGELOG.md` unchanged.


## Git Commit Message Convention

All new commits must use Conventional Commits so release notes, history, and GitHub views stay readable.

Format:

```text
<type>(<scope>): <summary>
```

Rules:

- Use lowercase `type`. Allowed types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`, `revert`.
- Use a short lowercase scope when it clarifies the affected area, for example `reader`, `notes`, `sidebar`, `bridge`, `core`, `release`, or `docs`.
- Write the summary in imperative mood, without a trailing period, and keep the first line under 72 characters when practical.
- Use a body for motivation, behavior changes, migration notes, or testing details when the change is non-trivial.
- Mark breaking changes with `!` after the type/scope and include a `BREAKING CHANGE:` footer.
- Agent-authored commits should keep the Codex git identity (`Codex <codex@openai.com>`) unless the user explicitly requests another author.

Examples:

```text
feat(reader): add reading context sidebar
fix(notes): preserve underline note append order
docs(readme): document Gatekeeper workaround
chore(release): update version to 1.0.12
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
2. **Use `sqlx` migrations**: Use `sqlx migrate add <name>` to create migration scripts
3. **Migration location**: `lumen-pdf-core/migrations/`
4. **Breaking changes**: If you must drop columns or change types, provide data migration logic to prevent data loss
5. **Testing**: Verify migration scripts in a test environment before deployment

### Migration Commands

```bash
# Create a new migration
cd lumen-pdf-core && sqlx migrate add <migration_name>

# Run migrations
cd lumen-pdf-core && sqlx migrate run

# Revert migration
cd lumen-pdf-core && sqlx migrate revert
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
