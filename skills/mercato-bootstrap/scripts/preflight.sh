#!/usr/bin/env bash
# Preflight checks for bootstrapping an Open Mercato app.
# Exits non-zero (and prints what's wrong) if any hard requirement is missing.
set -uo pipefail

fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

echo "Preflight:"

# Node >= 24
if command -v node >/dev/null 2>&1; then
  major=$(node -p 'process.versions.node.split(".")[0]')
  if [ "$major" -ge 24 ] 2>/dev/null; then ok "node $(node -v)"; else bad "node >= 24 required (have $(node -v))"; fi
else
  bad "node not found (need >= 24)"
fi

# corepack (provides yarn 4 via the app's packageManager field)
if command -v corepack >/dev/null 2>&1; then
  ok "corepack present"
  corepack enable >/dev/null 2>&1 || warn "could not 'corepack enable' (may need: sudo corepack enable)"
else
  bad "corepack not found (ships with node >= 16; try 'npm i -g corepack')"
fi

# Docker daemon running
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then ok "docker daemon running"; else bad "docker installed but daemon not running — start Docker Desktop"; fi
else
  bad "docker not found"
fi

if [ "$fail" -ne 0 ]; then
  echo "Preflight FAILED — resolve the above before continuing." >&2
  exit 1
fi
echo "Preflight OK."
