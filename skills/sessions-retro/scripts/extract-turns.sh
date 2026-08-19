#!/bin/bash
# extract-turns.sh — prefilter for the sessions-retro skill.
#
# Extracts human-looking user turns from recent Claude Code transcripts
# (~/.claude/projects/*/*.jsonl), then a friction-candidate subset matching
# crude correction markers. The candidate set is a RECALL net — a classifier
# pass must separate genuine friction from false positives.
#
# Usage: extract-turns.sh [DAYS] [PROJECT_FILTER]
#   DAYS            recency window in days (default 7)
#   PROJECT_FILTER  substring match on the project dir name (default: all)
#
# Writes turns.tsv and candidates.tsv into a fresh temp dir and prints their
# paths + corpus stats. Columns (TAB-separated):
#   project-dir  session-id-prefix  turn-index  text (first 600 chars)
# turn-index counts human turns within the session; index 0 is usually the
# task brief, not friction.
#
# Read-only on transcripts; safe to re-run (new temp dir each time).

set -eu

DAYS="${1:-7}"
FILTER="${2:-}"

case "$DAYS" in
  ''|*[!0-9]*) echo "DAYS must be a positive integer, got: $DAYS" >&2; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
[ -d "$PROJECTS_DIR" ] || { echo "no transcripts dir at $PROJECTS_DIR" >&2; exit 1; }

OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sessions-retro.XXXXXX")"
TURNS="$OUT_DIR/turns.tsv"
CANDIDATES="$OUT_DIR/candidates.tsv"
: > "$TURNS"

FILES="$OUT_DIR/files.txt"
if [ -n "$FILTER" ]; then
  find "$PROJECTS_DIR" -name '*.jsonl' -mtime -"$DAYS" | grep -F -- "$FILTER" > "$FILES" || true
else
  find "$PROJECTS_DIR" -name '*.jsonl' -mtime -"$DAYS" > "$FILES"
fi

while read -r f; do
  proj=$(basename "$(dirname "$f")")
  sess=$(basename "$f" .jsonl | cut -c1-8)
  jq -rn --arg p "$proj" --arg s "$sess" '
    [inputs
     | select(.type=="user" and ((.isSidechain // false) | not))
     | .message.content as $c
     | (if ($c|type)=="string" then $c
        elif ($c|type)=="array" then ([$c[] | select(.type=="text") | .text] | join(" "))
        else "" end)
     | select(. != "" and (.|length) > 2 and (.|length) < 3000)
     | select(test("^\\s*(<system|<command-|<local-command|<task-notification|\\[Request interrupted|Caveat:|<hook|<user-prompt-submit)") | not)
     | select(test("<system_instruction>|<system-reminder>") | not)
    ]
    | to_entries[]
    | [$p, $s, (.key|tostring), (.value | gsub("[\\t\\n\\r]+"; " ") | .[0:600])]
    | @tsv
  ' "$f" 2>/dev/null >> "$TURNS" || true
done < "$FILES"

# Friction markers, EN + PL. Deliberately loose — precision is the classifier's job.
FRICTION_RE="\b(no|nope|don'?t|do not|stop|wrong|incorrect|not what|instead|revert|undo|why (did|do|are) you|i (said|asked|told)|actually|rewrite|redo|that'?s not|didn'?t ask|should(n'?t)? have|not needed|unnecessary|too (long|verbose|much)|nie|zle|źle|popraw|zamiast|bez sensu)\b"
grep -iE "$FRICTION_RE" "$TURNS" > "$CANDIDATES" || true

files_n=$(wc -l < "$FILES" | tr -d ' ')
turns_n=$(wc -l < "$TURNS" | tr -d ' ')
cand_n=$(wc -l < "$CANDIDATES" | tr -d ' ')

echo "window: last $DAYS days${FILTER:+, project filter: *$FILTER*}"
echo "transcripts: $files_n, human turns: $turns_n, friction candidates: $cand_n"
echo "turns: $TURNS"
echo "candidates: $CANDIDATES"
