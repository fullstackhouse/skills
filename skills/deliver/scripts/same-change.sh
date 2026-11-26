#!/bin/bash
# same-change.sh — does a PR carry the same change at two heads?
#
#   same-change.sh <base-ref> <approved-sha> <head-sha>
#
# Compares the PR's own diff (merge-base with <base-ref> .. head) at both heads, not the
# SHAs, so a rebase or a merge of the base that leaves the change alone still matches.
# Hunks in docs/spec files (*.md, docs/, .ai/) may differ: a doc-only conflict resolution
# counts as unchanged. Agent instructions (AGENTS.md, CLAUDE.md, SKILL.md, .ai/skills/,
# .agents/) count as code. Everything else must match exactly, whitespace included.
# Prints the files whose own diff differs between the heads (what the update touched).
# Exit 0: same change. 1: different. 2: error (a missing object, a bad ref).
# Read-only; run it in any checkout that has fetched both heads and <base-ref>.
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: same-change.sh <base-ref> <approved-sha> <head-sha>" >&2; exit 2; }
base=$1 approved=$2 head=$3
fail() { echo "error: $*" >&2; exit 2; }

own_diff() { # <head> [git diff args...]: the PR's own change at that head
  local mb
  mb=$(git merge-base "$base" "$1") || return 1
  git diff --no-color --no-ext-diff --no-textconv --binary "$mb" "$1" "${@:2}"
}
id() { # <head> [pathspec...]
  own_diff "$1" -- "${@:2}" | git patch-id --verbatim
}

files=$({ own_diff "$approved" --name-only && own_diff "$head" --name-only; } | sort -u) ||
  fail "cannot diff $approved or $head against $base"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  a=$(id "$approved" ":(literal)$f") && b=$(id "$head" ":(literal)$f") || fail "cannot diff $f"
  [ "$a" = "$b" ] || echo "differs: $f"
done <<<"$files"

code=(. ':(exclude,glob)**/*.md' ':(exclude,glob)**/docs/**' ':(exclude,glob)**/.ai/**')
agent=(':(glob)**/AGENTS.md' ':(glob)**/CLAUDE.md' ':(glob)**/SKILL.md' ':(glob)**/.ai/skills/**' ':(glob)**/.agents/**')
a=$(id "$approved" "${code[@]}") && b=$(id "$head" "${code[@]}") || fail "cannot diff the code"
c=$(id "$approved" "${agent[@]}") && d=$(id "$head" "${agent[@]}") || fail "cannot diff the agent instructions"
if [ "$a" = "$b" ] && [ "$c" = "$d" ]; then
  echo "same change"
else
  echo "changed"
  exit 1
fi
