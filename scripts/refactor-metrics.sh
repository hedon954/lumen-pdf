#!/usr/bin/env bash
set -euo pipefail

OUT_MD="${1:-docs/plan/refactor-baseline.md}"
OUT_HTML="${2:-docs/plan/refactor-baseline.html}"
TITLE="${3:-LumenPDF Refactor Metrics}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p "$(dirname "$OUT_MD")" "$(dirname "$OUT_HTML")"

count_rg() {
  local pattern="$1"
  local path="$2"
  rg -n "$pattern" "$path" --glob '!LumenPDF/Generated/**' --glob '!build/**' 2>/dev/null | wc -l | tr -d ' '
}

hash_uniffi_exports() {
  awk '
    /^#\[uniffi::export/ { print; capture=1; trait=0; next }
    capture {
      print
      if ($0 ~ /^pub trait/) { trait=1; next }
      if (trait && $0 ~ /^}/) { capture=0; trait=0; next }
      if (!trait && $0 ~ /\{[[:space:]]*$/) { capture=0; next }
    }
  ' "$1" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | shasum -a 256 | awk '{print $1}'
}

swift_total="$(find LumenPDF -name '*.swift' -not -path '*/Generated/*' -print0 | xargs -0 wc -l | tail -1 | awk '{print $1}')"
rust_total="$(find lumen-pdf-core/src -name '*.rs' -print0 | xargs -0 wc -l | tail -1 | awk '{print $1}')"
pdf_reader_lines="$(wc -l < LumenPDF/Views/PDFReaderView.swift | tr -d ' ')"
translation_service_lines="$(wc -l < lumen-pdf-core/src/domain/translation/service.rs | tr -d ' ')"
llm_translator_lines="$(wc -l < lumen-pdf-core/src/infrastructure/translator/llm_translator.rs | tr -d ' ')"
bridge_calls="$(count_rg 'BridgeService\.shared' LumenPDF)"
notification_uses="$(count_rg 'NotificationCenter\.default\.(post|addObserver)' LumenPDF)"
try_optional="$(count_rg 'try\?' LumenPDF)"
generated_bindings_hash="$(shasum -a 256 LumenPDF/Generated/lumen_pdf_core.swift 2>/dev/null | awk '{print $1}')"
api_exports_hash="$(hash_uniffi_exports lumen-pdf-core/src/interfaces/api.rs)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

largest_swift="$(find LumenPDF -name '*.swift' -not -path '*/Generated/*' -print0 | xargs -0 wc -l | sort -nr | head -10)"
largest_rust="$(find lumen-pdf-core/src -name '*.rs' -print0 | xargs -0 wc -l | sort -nr | head -10)"

cat > "$OUT_MD" <<EOF
# $TITLE

- Generated: $timestamp
- Branch: \`$branch\`
- Commit: \`$commit\`

## Summary Metrics

| Metric | Value |
| --- | ---: |
| Swift LOC (excluding Generated) | $swift_total |
| Rust LOC | $rust_total |
| PDFReaderView.swift LOC | $pdf_reader_lines |
| translation/service.rs LOC | $translation_service_lines |
| llm_translator.rs LOC | $llm_translator_lines |
| Swift BridgeService.shared references | $bridge_calls |
| Swift NotificationCenter post/addObserver references | $notification_uses |
| Swift try? references | $try_optional |

## Compatibility Fingerprints

| Fingerprint | SHA-256 |
| --- | --- |
| Generated Swift binding | \`$generated_bindings_hash\` |
| Rust UniFFI public signatures | \`$api_exports_hash\` |

## Largest Swift Files

\`\`\`text
$largest_swift
\`\`\`

## Largest Rust Files

\`\`\`text
$largest_rust
\`\`\`
EOF

cat > "$OUT_HTML" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$TITLE</title>
  <style>
    body { font: 14px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; line-height: 1.45; color: #1f2328; }
    table { border-collapse: collapse; margin: 16px 0 24px; min-width: 560px; }
    th, td { border: 1px solid #d0d7de; padding: 8px 10px; text-align: left; }
    td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
    code, pre { background: #f6f8fa; border-radius: 6px; }
    pre { padding: 12px; overflow: auto; }
  </style>
</head>
<body>
  <h1>$TITLE</h1>
  <p>Generated: <code>$timestamp</code> on <code>$branch</code> at <code>$commit</code>.</p>
  <h2>Summary Metrics</h2>
  <table>
    <tr><th>Metric</th><th>Value</th></tr>
    <tr><td>Swift LOC (excluding Generated)</td><td>$swift_total</td></tr>
    <tr><td>Rust LOC</td><td>$rust_total</td></tr>
    <tr><td>PDFReaderView.swift LOC</td><td>$pdf_reader_lines</td></tr>
    <tr><td>translation/service.rs LOC</td><td>$translation_service_lines</td></tr>
    <tr><td>llm_translator.rs LOC</td><td>$llm_translator_lines</td></tr>
    <tr><td>Swift BridgeService.shared references</td><td>$bridge_calls</td></tr>
    <tr><td>Swift NotificationCenter post/addObserver references</td><td>$notification_uses</td></tr>
    <tr><td>Swift try? references</td><td>$try_optional</td></tr>
  </table>
  <h2>Compatibility Fingerprints</h2>
  <table>
    <tr><th>Fingerprint</th><th>SHA-256</th></tr>
    <tr><td>Generated Swift binding</td><td><code>$generated_bindings_hash</code></td></tr>
    <tr><td>Rust UniFFI public signatures</td><td><code>$api_exports_hash</code></td></tr>
  </table>
  <h2>Largest Swift Files</h2>
  <pre>$largest_swift</pre>
  <h2>Largest Rust Files</h2>
  <pre>$largest_rust</pre>
</body>
</html>
EOF

echo "Wrote $OUT_MD"
echo "Wrote $OUT_HTML"
