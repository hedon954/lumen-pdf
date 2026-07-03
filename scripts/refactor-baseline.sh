#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash scripts/refactor-metrics.sh \
  docs/plan/refactor-baseline.md \
  docs/plan/refactor-baseline.html \
  "LumenPDF Refactor Baseline"
