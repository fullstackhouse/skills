#!/usr/bin/env bash
# Idempotently prepare the bundled renderer: install node deps + Playwright Chromium.
# Safe to re-run. PDF works after this; DOCX additionally needs `pandoc` on PATH.
set -euo pipefail

RENDERER_DIR="$(cd "$(dirname "$0")/../renderer" && pwd)"
cd "$RENDERER_DIR"

if [ ! -d node_modules ] || [ package.json -nt node_modules ]; then
  echo "→ Installing renderer dependencies…"
  npm install --no-audit --no-fund
else
  echo "→ Dependencies present."
fi

echo "→ Ensuring Playwright Chromium…"
npx --yes playwright install chromium >/dev/null

if command -v pandoc >/dev/null 2>&1; then
  echo "→ pandoc found — DOCX output available."
else
  echo "→ pandoc NOT found — PDF only. Install pandoc for DOCX: https://pandoc.org/installing.html"
fi

echo "✓ Renderer ready: $RENDERER_DIR"
