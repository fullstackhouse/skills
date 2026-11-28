#!/bin/bash
# patch-id.sh — the patch-id of a PR's own diff at one or more heads.
#
#   patch-id.sh <base-ref> <head>...
#
# Prints "<head> <patch-id>" per head: `git patch-id --verbatim` of
# `git diff <merge-base with base-ref>..<head>`. Two heads with the same value carry the
# same change, exactly (whitespace included, docs included), whatever their SHAs: a rebase
# that left the PR's own diff alone keeps it. deliver keys its step proofs on it. For an
# owner's approval, which tolerates doc-only hunks, use same-change.sh instead.
# An empty diff prints "<head> -". Exit 0: printed. 2: error (a missing object, a bad ref).
# Read-only; needs git >= 2.39 and every head and <base-ref> fetched.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: patch-id.sh <base-ref> <head>..." >&2; exit 2; }
base=$1
shift
for head in "$@"; do
  mb=$(git merge-base "$base" "$head" 2>/dev/null) || { echo "error: cannot find the merge-base of $head and $base" >&2; exit 2; }
  if git diff --quiet "$mb" "$head" 2>/dev/null; then
    echo "$head -"
    continue
  fi
  id=$(git diff --no-color --no-ext-diff --no-textconv --binary "$mb" "$head" | git patch-id --verbatim | cut -d' ' -f1) ||
    { echo "error: cannot diff $head" >&2; exit 2; }
  [ -n "$id" ] || { echo "error: empty patch-id for $head" >&2; exit 2; }
  echo "$head $id"
done
