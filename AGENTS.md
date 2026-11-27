# AGENTS.md

Agent guide for this repository. `AGENTS.md` and `CLAUDE.md` are the same file.

## Commands

```bash
make setup        # first-time setup, including pre-commit hooks
make build-rust   # after Rust or UniFFI changes; regenerates LumenPDF/Generated/
make gen-project  # after project.yml changes
make dmg          # package a DMG
```

From `lumen-pdf-core`, these are the CI checks:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
```

`cargo test domain` and `cargo test migration` cover those slices. Pre-commit runs the three CI commands only when Rust files are staged, so a docs-only commit can pass the hook while CI still fails.

## Stack

macOS 13+ PDF reader: SwiftUI + PDFKit, UniFFI, Rust (Tokio, rusqlite, reqwest). Speech is `AVSpeechSynthesizer` in Swift.

```
SwiftUI → interfaces → application → domain ← infrastructure
```

| Layer | Path | Rule |
| --- | --- | --- |
| Swift UI | `LumenPDF/` | No database or HTTP access |
| interfaces | `lumen-pdf-core/src/interfaces/` | UniFFI exports and dependency injection only |
| application | `lumen-pdf-core/src/application/` | Orchestrate use cases. No SQL or HTTP |
| domain | `lumen-pdf-core/src/domain/` | No I/O. Do not import `reqwest`, `rusqlite`, or `r2d2` |
| infrastructure | `lumen-pdf-core/src/infrastructure/` | Implement domain traits. No business rules |

Views forward events and hold view state. They must not call `BridgeService.shared`; inject a narrow closure, model, or service. Coordinators and services call the bridge. UI updates run on `@MainActor`. No `URLSession` or `sqlite3` in views or coordinators.

Do not add a protocol without a second implementation or a test boundary. Pass only the data and callbacks a view needs, not `AppState` or a wide request type. Keep one implementation of note grouping, Markdown rendering, AI-reply saving, selection-bounds parsing, and viewport restoration. New Swift files should stay within roughly 300–500 lines; split mixed responsibilities. Put pure behavior in UI-independent types.

## UniFFI

Proc macros via `uniffi::setup_scaffolding!()` in `lib.rs`. Do not add a UDL file.

- Records: `#[uniffi::Record]` in the domain layer. Errors: `#[uniffi::Error]`.
- Functions: `#[uniffi::export]`, or `#[uniffi::export(async_runtime = "tokio")]` when async.
- Add the export in `interfaces/api.rs`, run `make build-rust`, then wrap it in `LumenPDF/Services/BridgeService.swift`.
- Reuse the process-wide `POOL` and `LLM_CONFIG` in `interfaces/api.rs`. Do not create another Tokio runtime.

Entry points: `lumen-pdf-core/src/interfaces/api.rs`, `LumenPDF/Services/BridgeService.swift`, `scripts/build-rust.sh`.

## Translation and domain tests

Lookup order is SQLite cache, then an OpenAI-compatible LLM, then MyMemory. Cache only a successful LLM result.

Every `domain/*/service.rs` has a `#[cfg(test)]` module with in-memory `Fake*` traits and no I/O. Translation tests cover cache hit, LLM success, LLM failure then fallback, and both failing.

## Database

Migrations live in `lumen-pdf-core/src/infrastructure/db/migration.rs` and must be idempotent. New columns are nullable or have defaults. Dropping or retyping a column requires a rebuild that keeps existing rows. Verify a migration against a copy of an existing database before shipping it.

## Product docs

A user-visible behavior change, an interaction-rule change, or a module, persistence, or bridge boundary change needs a paired PRD and TDD in the same PR:

- `docs/prd/prd-YYYY-MM-DD-<topic>.md`
- `docs/tdd/tdd-YYYY-MM-DD-<topic>.md`

PRD: problem, observable behavior, non-goals, acceptance. No implementation. TDD: boundaries, state, tests, runtime checks. Do not paste the PRD into the TDD.

Keep `version`, `date`, `tdd` or `prd`, `predecessor`, `successor`, and optional `related` in YAML frontmatter only. Paths are relative to `docs/`. Omit empty predecessor or successor lists. `version` is the short app version (`v1.0.21`) or `unreleased`. Do not repeat that metadata in the body, and do not link the body back to `docs/README.md`.

When a new doc replaces an old rule, mark the old clause with `后续修订` and a link, and set `successor` / `predecessor` on both files. Update the pairing table and topic history in `docs/README.md`.

Do not treat `CHANGELOG.md` as a substitute. Do not add an unpaired PRD or TDD. Do not delete an old doc to tidy the tree. An internal refactor with no behavior change may update only the TDD; if the PRD is already wrong, correct it the same way.

Index: `docs/README.md`. Baseline: `docs/prd/prd-2026-03-22.md`, `docs/tdd/tdd-2026-03-22.md`.

## Git

Conventional Commits. The `type(scope):` prefix is English. The summary and body are Chinese. Every commit has a non-empty body after one blank line. Say why and what changed. Do not repeat the summary. Do not put build or test results in the body. Keep the first line under 72 characters, with no trailing period.

```text
feat(reader): 增加阅读上下文侧栏

统一承载单词、笔记和 AI 导读，减少阅读过程中在多个页面间切换。
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`, `revert`. Breaking changes use `!` and a `BREAKING CHANGE:` footer. Agent-authored commits use `Codex <codex@openai.com>` unless the user asks for another author.

PR branches:

```text
<type>/<scope>-<short-topic>-<YYYYMMDD-HHmm>
```

No `codex/*`, `claude/*`, `agent/*`, `feature`, `fix`, or `temp`. Do not reuse a remote branch for unrelated work. Release branches may be `release/vX.Y.Z`.

## Release

Follow `.cursor/skills/release-tag/SKILL.md`. That skill owns the checks required before creating a tag.

- Public version is `CFBundleShortVersionString` in `LumenPDF/Info.plist` (for example `1.0.9`). `CFBundleVersion` is the build number (for example `9`). Tags, DMG names, and docs use the short version.
- Write the Chinese changelog section, including commit URLs, before tagging. The release workflow publishes that section as the GitHub Release body and must not generate it.
- The annotated tag message has the version title, the changelog summary, and a pointer to `CHANGELOG.md`.

## Signing and credentials

- Store the LLM API key in `AppDataDirectory/llm-api-key.vault`. A data-protection Keychain copy is optional. Never fall back to the login keychain: those items bind an ACL to this binary and prompt for the login password after every ad-hoc rebuild.
- Disable user interaction on every `SecItem` call so a signature mismatch cannot present SecurityAgent.
- Ad-hoc signing is allowed. A configured identity signs every nested dylib first and the app last. Do not use `codesign --deep`. An ad-hoc build must still open the vault without a Keychain dialog.
- Do not enable App Sandbox or reattach `LumenPDF.entitlements`. The database and `UserDefaults` live outside a container. Turning Sandbox on requires a tested, non-destructive migration in the same change.
- CI uses the same identity policy as local packaging and must not block an ad-hoc release because no signing identity is present.

## Windows and overlays

- Keep in-window UI in one SwiftUI tree. An overlay above several `NavigationSplitView` columns belongs on their nearest common SwiftUI ancestor.
- Do not add an `NSPanel`, child window, or hosted subview only to escape clipping or `zIndex`. A separate window is for a feature that is actually a separate window.
- One owner removes every child window, event monitor, observer, delegate, and hosted view on dismiss and teardown.
- If a bridge needs custom event routing, global identifiers, and copied state to recreate behavior SwiftUI already had, stop. Change the boundary instead of adding lifecycle machinery.
- Moving a view to another presentation container is a behavior change. Preserve appearance, transparency, coordinate space, hit testing, focus, dismissal, selection ownership, attach/update/detach, activation, resize, move, miniaturize, close, and multi-window behavior.
- After the first regression from a new presentation or ownership boundary, stop stacking patches. Revert or redesign.
- Persist stable workspace state in one versioned model and one manager: window frame, split visibility and widths, and each document viewport (zoom mode, scale, horizontal offset, vertical offset). Do not persist selections, action bars, loading overlays, or editors.
- Views may report or apply that state. They must not add their own `UserDefaults` keys for frame, splits, active tab, last document, inspector mode, or viewport.
- Apply saved geometry before capturing measurements. The persisted split width is the binding that sets the pane. If SwiftUI has no reliable width binding, use one divider. Do not infer width from private `NSSplitView` ancestry.
- Freeze stable-layout writes before miniaturize, close, and quit. Keep the last visible widths while hidden, reapply the saved layout, then capture again after deminiaturize.

## Verification

A successful build only proves compilation. Run the affected interaction before calling a visual or interaction fix done. For overlays, popovers, floating controls, and split chrome, cover normal placement, placement beside the sidebar and inspector, clicks inside the control and on the PDF, sidebar, inspector, and toolbar, a second selection, zoom and scroll, resize and move, deactivate and reactivate, and light and dark appearance. Window or split changes also need quit and relaunch after move, live resize, zoom or tile, hiding or resizing each sidebar, a tab change, manual zoom and pan on both axes, and disconnecting a display. The restored window stays fully on the current screens, and the PDF keeps its scale and visible region.

If that run is impossible, say the change is unverified. Do not mix a feature fix with unrelated tooling unless the user asks for both.
