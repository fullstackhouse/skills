#!/usr/bin/env bash
# Pick a free host-port block for this project's local infra (Postgres/Redis/Meilisearch),
# so multiple Open Mercato stacks (and conductor worktrees) can coexist on one machine.
#
# Default block: 5442 / 6389 / 7710  (offset +10 from the framework defaults 5432/6379/7700).
# If any port in the candidate block is taken, the whole block shifts by +10 and retries.
#
# Prints three KEY=VALUE lines on success, e.g.:
#   POSTGRES_PORT=5442
#   REDIS_PORT=6389
#   MEILISEARCH_PORT=7710
set -uo pipefail

pg_base=${1:-5442}
redis_base=${2:-6389}
meili_base=${3:-7710}

port_in_use() {
  # macOS + Linux: prefer lsof, fall back to nc
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
  else
    return 1  # can't tell; assume free
  fi
}

for shift in 0 10 20 30 40 50 60 70 80 90 100; do
  pg=$((pg_base + shift)); rd=$((redis_base + shift)); ms=$((meili_base + shift))
  if ! port_in_use "$pg" && ! port_in_use "$rd" && ! port_in_use "$ms"; then
    echo "POSTGRES_PORT=$pg"
    echo "REDIS_PORT=$rd"
    echo "MEILISEARCH_PORT=$ms"
    exit 0
  fi
done

echo "Could not find a free port block after 11 attempts; pick ports manually." >&2
exit 1
