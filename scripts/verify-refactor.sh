#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== Rust fmt =="
(cd lumen-pdf-core && cargo fmt --check)

echo "== Rust clippy =="
(cd lumen-pdf-core && cargo clippy -- -D warnings)

echo "== Rust tests =="
(cd lumen-pdf-core && cargo test)

echo "== Swift build =="
xcodebuild build \
  -project LumenPDF/LumenPDF.xcodeproj \
  -scheme LumenPDF \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "== Refactor metrics =="
bash scripts/refactor-metrics.sh \
  docs/plan/refactor-after.md \
  docs/plan/refactor-after.html \
  "LumenPDF Refactor After"
