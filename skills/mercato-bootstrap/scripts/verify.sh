#!/usr/bin/env bash
# Verify a running Open Mercato dev server.
#   /         should return 200
#   /backend  should return 200 or a 3xx redirect to /login (unauthenticated)
# Usage: verify.sh [base_url]   (default http://localhost:3000)
set -uo pipefail

base=${1:-http://localhost:3000}
probe() { curl -s -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }

root=$(probe "$base/")
backend=$(probe "$base/backend")

printf 'GET %-22s -> %s\n' "$base/"        "$root"
printf 'GET %-22s -> %s\n' "$base/backend" "$backend"

case "$root" in 200) ;; *) echo "FAIL: / did not return 200" >&2; exit 1;; esac
case "$backend" in 200|301|302|307|308) ;; *) echo "FAIL: /backend unexpected status" >&2; exit 1;; esac
echo "Verify OK."
