#!/usr/bin/env bash
# doc-audit.sh — deterministic documentation facts for the `docs-audit` skill.
#
#   doc-audit.sh [repo-path]      # defaults to the current directory
#
# Read-only. Reports facts, never verdicts: what the instruction chains weigh, which
# links are dead, which docs nothing points at. Judgment is the skill's job.
#
# Requires git, awk, sed, grep. Only tracked files are considered.
# Targets bash 3.2 (macOS default) — no nested `case` inside `$( )`, no associative arrays.
set -euo pipefail

CODEX_BUDGET=32768        # Codex `project_doc_max_bytes` — the shared root-to-leaf budget
ROOT_RESERVE=1536         # held back so the root cannot spend the whole budget
ROOT_MAX=$((CODEX_BUDGET - ROOT_RESERVE))

case "${1:-}" in
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

cd "${1:-.}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "doc-audit: not a git repository — run it inside the repo you are auditing." >&2
  exit 2
}
cd "$(git rev-parse --show-toplevel)"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/doc-audit.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

REPO=$(basename "$(pwd)")
git ls-files '*.md' '*.mdx' | grep -v '/node_modules/' > "$TMP/md" || true
grep -E '(^|/)(AGENTS|CLAUDE)\.md$' "$TMP/md" | sort > "$TMP/agentdocs" || true

bytes() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }
dirof() { dirname "$1"; }
count() { wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

# The file an agent actually loads for a directory: AGENTS.md when present (a CLAUDE.md
# beside it is expected to be a pointer to it), otherwise CLAUDE.md.
effective_doc() {
  if [ "$1" = "." ]; then p=""; else p="$1/"; fi
  if [ -f "${p}AGENTS.md" ]; then echo "${p}AGENTS.md"
  elif [ -f "${p}CLAUDE.md" ]; then echo "${p}CLAUDE.md"
  fi
}

# Resolve a relative link against the directory of the file containing it,
# collapsing "." and ".." segments. Prints nothing for an unresolvable path.
resolve_link() {
  from_dir=$1; link=$2
  case "$link" in
    /*) cand=".${link}" ;;
    *)  if [ "$from_dir" = "." ]; then cand="$link"; else cand="$from_dir/$link"; fi ;;
  esac
  out=""
  oldifs=$IFS; IFS='/'
  for seg in $cand; do
    case "$seg" in
      ""|".") ;;
      "..") out=$(dirname "/$out"); out=${out#/} ;;
      *) if [ -z "$out" ]; then out="$seg"; else out="$out/$seg"; fi ;;
    esac
  done
  IFS=$oldifs
  echo "$out"
}

# Every relative markdown link in the repo, one per line: STATUS <tab> file <tab> raw <tab> resolved
scan_links() {
  while read -r f; do
    [ -f "$f" ] || continue
    grep -oE '\]\([^)]+\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' > "$TMP/raw" || true
    while read -r raw; do
      case "$raw" in
        ""|http*|mailto:*|tel:*|file:*|data:*|\#*|'<'*|*'{{'*|*'$'*|*'…'*) continue ;;
      esac
      target=${raw%%#*}; target=${target%% *}
      [ -n "$target" ] || continue
      r=$(resolve_link "$(dirof "$f")" "$target")
      if [ -e "$r" ]; then printf 'OK\t%s\t%s\t%s\n' "$f" "$raw" "$r"
      else printf 'DEAD\t%s\t%s\t%s\n' "$f" "$raw" "$r"; fi
    done < "$TMP/raw"
  done < "$TMP/md"
}
scan_links > "$TMP/links" || true

echo "# doc-audit — $REPO ($(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD))"
echo "# tracked markdown: $(count "$TMP/md") files"
echo

# ------------------------------------------------------------- 1. instruction budget
echo "## 1. Agent-doc chains vs the instruction budget"
echo "# An agent loads the AGENTS.md files from the repo root down to its working directory"
echo "# and stops at $CODEX_BUDGET bytes (Codex's default). Everything past that offset is dropped"
echo "# silently — no warning, no truncation notice. Root hard limit here: ${ROOT_MAX}B."
echo
if [ "$(count "$TMP/agentdocs")" = "0" ]; then
  echo "NONE — no AGENTS.md or CLAUDE.md anywhere. Every agent starts this repo cold."
else
  while read -r f; do dirof "$f"; done < "$TMP/agentdocs" | sort -u > "$TMP/dirs"
  ROOT_DOC=$(effective_doc ".")
  if [ -z "$ROOT_DOC" ]; then
    echo "NO ROOT DOC — nested agent docs exist but nothing at the repo root."
  else
    rb=$(bytes "$ROOT_DOC")
    if [ "$rb" -gt "$ROOT_MAX" ]; then
      echo "root: $ROOT_DOC — ${rb}B / ${ROOT_MAX}B  [OVER by $((rb - ROOT_MAX))B]"
    else
      echo "root: $ROOT_DOC — ${rb}B / ${ROOT_MAX}B  [ok, $((ROOT_MAX - rb))B spare for nested files]"
    fi
  fi
  echo
  ndirs=$(count "$TMP/dirs")
  while read -r leaf; do
    deeper=$(awk -v p="$leaf/" 'index($0,p)==1' "$TMP/dirs" | wc -l | tr -d ' ')
    if [ "$leaf" != "." ] && [ "$deeper" -gt 0 ]; then continue; fi
    if [ "$leaf" = "." ] && [ "$ndirs" -gt 1 ]; then continue; fi

    : > "$TMP/chain"
    while read -r d; do
      keep=0
      [ "$d" = "." ] && keep=1
      [ "$d" = "$leaf" ] && keep=1
      case "$leaf" in "$d"/*) keep=1 ;; esac
      [ "$keep" = 1 ] || continue
      doc=$(effective_doc "$d"); [ -n "$doc" ] || continue
      printf '%s %s\n' "$(bytes "$doc")" "$doc" >> "$TMP/chain"
    done < "$TMP/dirs"

    total=$(awk '{s+=$1} END{print s+0}' "$TMP/chain")
    if [ "$total" -gt "$CODEX_BUDGET" ]; then
      echo "CHAIN OVER BUDGET: ${total}B — $((total - CODEX_BUDGET))B never reaches an agent working in $leaf"
    else
      echo "chain ok: ${total}B / ${CODEX_BUDGET}B  ($leaf)"
    fi
    awk '{printf "    %8dB  %s\n", $1, $2}' "$TMP/chain"
  done < "$TMP/dirs"
fi
echo

# ------------------------------------------------------------------- 2. doc wiring
echo "## 2. CLAUDE.md / AGENTS.md wiring"
echo "# House rule: AGENTS.md is canonical, CLAUDE.md is a pointer that imports it, so"
echo "# every agent reads one file and it cannot drift from itself."
echo
if [ "$(count "$TMP/agentdocs")" = "0" ]; then
  echo "n/a"
else
  while read -r f; do dirof "$f"; done < "$TMP/agentdocs" | sort -u > "$TMP/dirs2"
  while read -r d; do
    if [ "$d" = "." ]; then p=""; else p="$d/"; fi
    a="${p}AGENTS.md"; c="${p}CLAUDE.md"
    if [ -f "$a" ] && [ -f "$c" ]; then
      if [ -L "$c" ]; then
        echo "symlink        $d  (CLAUDE.md -> $(readlink "$c"))"
      elif [ -L "$a" ]; then
        echo "INVERTED       $d  (AGENTS.md -> $(readlink "$a") — the canonical name is the pointer)"
      elif grep -qE '^@AGENTS\.md[[:space:]]*$' "$c" && [ "$(bytes "$c")" -lt 512 ]; then
        echo "pointer        $d  (CLAUDE.md imports @AGENTS.md)"
      else
        echo "FORK           $d  (two independent files, $(bytes "$a")B / $(bytes "$c")B — they will drift)"
      fi
    elif [ -f "$c" ]; then
      echo "claude-only    $d  (no AGENTS.md — Codex and every non-Claude agent read nothing here)"
    elif [ -f "$a" ]; then
      echo "agents-only    $d"
    fi
  done < "$TMP/dirs2"
fi
echo

# ----------------------------------------------------------------- 3. skill profile
echo "## 3. Skill profile"
PROFILE_FILE=""
if [ "$(count "$TMP/agentdocs")" != "0" ]; then
  while read -r f; do
    if grep -q '^## Skill profile' "$f" 2>/dev/null; then echo "$f"; fi
  done < "$TMP/agentdocs" | head -1 > "$TMP/profile" || true
  PROFILE_FILE=$(cat "$TMP/profile" 2>/dev/null || true)
fi
if [ -n "$PROFILE_FILE" ]; then
  echo "present in $PROFILE_FILE"
  { awk '/^## Skill profile/{f=1;next} /^## /{f=0} f' "$PROFILE_FILE" | sed 's/^/    /' | head -30; } || true
else
  echo "ABSENT — every repo-agnostic skill has to ask for or guess the base branch, the"
  echo "check commands, the tracker, the reviewer and the merge policy."
fi
echo

# ------------------------------------------------------------- 4. command staleness
echo "## 4. Commands referenced in agent docs"
echo "# Only commands written as code (inline backticks or a fenced block) are checked, and"
echo "# each is resolved against the nearest package.json above the doc that names it."
echo
if [ "$(count "$TMP/agentdocs")" != "0" ]; then
  : > "$TMP/unresolved"; found=0
  while read -r f; do
    fdir=$(dirof "$f")
    # code content only: fenced blocks verbatim, plus every inline `code` span
    awk '
      /^[[:space:]]*```/ { inf = !inf; next }
      inf { print; next }
      { line=$0
        while (match(line, /`[^`]+`/)) {
          print substr(line, RSTART+1, RLENGTH-2)
          line=substr(line, RSTART+RLENGTH)
        } }
    ' "$f" 2>/dev/null | grep -E '^[[:space:]]*(\$ )?(yarn|pnpm|npm run|bun run) ' > "$TMP/cands" || true
    while read -r cand; do
      [ -n "$cand" ] || continue
      found=1
      rest=$(echo "$cand" | sed -E 's/^[[:space:]]*(\$ )?(yarn|pnpm|npm run|bun run)[[:space:]]+//')
      dir="$fdir"
      case "$rest" in
        "--dir "*|"--filter "*|"-C "*)
          dir=$(echo "$rest" | awk '{print $2}')
          rest=$(echo "$rest" | sed -E 's/^(--dir|--filter|-C)[[:space:]]+[^[:space:]]+[[:space:]]*//') ;;
      esac
      script=$(echo "$rest" | awk '{print $1}')
      case "$script" in
        ""|-*|install|add|remove|dlx|exec|why|run|create|init|link|up|outdated|publish|pack|audit|upgrade|global|workspace|workspaces) continue ;;
      esac
      pkg=""; d="$dir"
      while : ; do
        if [ "$d" = "." ] || [ -z "$d" ]; then
          [ -f package.json ] && pkg=package.json
          break
        fi
        if [ -f "$d/package.json" ]; then pkg="$d/package.json"; break; fi
        d=$(dirname "$d")
      done
      if [ -z "$pkg" ]; then
        echo "UNRESOLVED  $f: $cand   (no package.json above $dir)" >> "$TMP/unresolved"
      else
        pkgdir=$(dirof "$pkg")
        # a package manager also runs binaries from node_modules/.bin, not just scripts
        if grep -qE "\"$script\"[[:space:]]*:" "$pkg"; then :
        elif [ -e "$pkgdir/node_modules/.bin/$script" ] || [ -e "node_modules/.bin/$script" ]; then :
        else
          echo "UNRESOLVED  $f: $cand   (no \"$script\" script in $pkg, no node_modules/.bin/$script)" >> "$TMP/unresolved"
        fi
      fi
    done < "$TMP/cands"
  done < "$TMP/agentdocs"
  if [ -s "$TMP/unresolved" ]; then { sort -u "$TMP/unresolved" | head -30; } || true
  elif [ "$found" = "1" ]; then echo "clean — every command an agent doc prints still resolves to a real script"
  else echo "no package-manager commands found in the agent docs"
  fi
else
  echo "n/a — no agent docs"
fi
echo

# ------------------------------------------------------------------- 5. dead links
echo "## 5. Dead relative links"
awk -F'\t' '$1=="DEAD" && $2 !~ /\.mdx$/ {printf "DEAD  %s -> %s\n", $2, $3}' "$TMP/links" | sort -u > "$TMP/dead" || true
mdx_dead=$(awk -F'\t' '$1=="DEAD" && $2 ~ /\.mdx$/' "$TMP/links" | wc -l | tr -d ' ')
if [ -s "$TMP/dead" ]; then
  head -30 "$TMP/dead"
  n=$(count "$TMP/dead")
  if [ "$n" -gt 30 ]; then
    echo "    ($n total — worst files:)"
    { sed -E 's/^DEAD  ([^ ]+) .*/\1/' "$TMP/dead" | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'; } || true
  fi
else
  echo "clean — every relative link resolves on disk"
fi
if [ "$mdx_dead" != "0" ]; then
  echo "# plus $mdx_dead in .mdx files, not listed: a docs site resolves links by route, not by"
  echo "# path, so check those with the site's own link checker instead."
fi
echo

# ---------------------------------------------------------------------- 6. orphans
echo "## 6. Docs nothing links to"
awk -F'\t' '{print $4}' "$TMP/links" | sort -u > "$TMP/linked" || true
: > "$TMP/orphans"
while read -r f; do
  case "$f" in
    README.md|AGENTS.md|CLAUDE.md|CONTRIBUTING.md|CHANGELOG.md|LICENSE.md|SECURITY.md|SPEC.md) continue ;;
    */AGENTS.md|*/CLAUDE.md|*/README.md|*/SKILL.md) continue ;;
  esac
  grep -qxF "$f" "$TMP/linked" || echo "ORPHAN  $f  ($(bytes "$f")B)" >> "$TMP/orphans"
done < "$TMP/md"
if [ -s "$TMP/orphans" ]; then
  head -40 "$TMP/orphans"
  echo "    ($(count "$TMP/orphans") total)"
else
  echo "clean — every doc is reachable from an index"
fi
echo "# an orphan is reachable only by already knowing it exists: it wants an index row, or deletion"
echo

# ------------------------------------------------------------------------ 7. specs
echo "## 7. Specs"
SPEC_DIR=""
for d in docs/specs .ai/specs specs docs/rfcs docs/adr; do
  if [ -d "$d" ]; then SPEC_DIR="$d"; break; fi
done
if [ -z "$SPEC_DIR" ]; then
  echo "no spec directory (looked for docs/specs, .ai/specs, specs, docs/rfcs, docs/adr)"
else
  git ls-files "$SPEC_DIR/*.md" | grep -vE '/(README|AGENTS|CLAUDE)\.md$' > "$TMP/specs" || true
  echo "directory: $SPEC_DIR — $(count "$TMP/specs") specs"
  if ls "$SPEC_DIR" 2>/dev/null | grep -qiE '^(SPEC-000|template|_template|000-)'; then
    echo "template: present"
  else
    echo "TEMPLATE MISSING — each new spec starts from whatever the author last happened to read"
  fi
  if [ -f "$SPEC_DIR/README.md" ]; then
    : > "$TMP/notindexed"
    while read -r s; do
      [ -n "$s" ] || continue
      grep -qF "$(basename "$s")" "$SPEC_DIR/README.md" || echo "NOT IN INDEX  $s" >> "$TMP/notindexed"
    done < "$TMP/specs"
    if [ -s "$TMP/notindexed" ]; then head -20 "$TMP/notindexed"; else echo "index: complete"; fi
  else
    echo "NO INDEX — $SPEC_DIR/README.md absent, so the spec set has no entry point"
  fi
  : > "$TMP/naming"
  while read -r s; do
    [ -n "$s" ] || continue
    b=$(basename "$s")
    if echo "$b" | grep -qE '^SPEC-[0-9]{3}[a-z]?-[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$'; then :
    elif echo "$b" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$'; then echo "    date-first   $b" >> "$TMP/naming"
    else echo "    OFF-PATTERN  $b" >> "$TMP/naming"
    fi
  done < "$TMP/specs"
  if [ -s "$TMP/naming" ]; then echo "naming:"; head -20 "$TMP/naming"; else echo "naming: consistent"; fi
  while read -r s; do basename "$s"; done < "$TMP/specs" | grep -oE '^SPEC-[0-9]{3}' | sort | uniq -d > "$TMP/dupes" || true
  if [ -s "$TMP/dupes" ]; then sed 's/^/    NUMBER REUSED  /' "$TMP/dupes"; fi
  echo "statuses:"
  while read -r s; do
    [ -n "$s" ] || continue
    line=$(grep -m1 -iE '^\*\*status\*\*' "$s" 2>/dev/null || true)
    if [ -n "$line" ]; then echo "$line" | sed -E 's/^\*\*[Ss]tatus\*\*:?[[:space:]]*//'; else echo "(no status field)"; fi
  done < "$TMP/specs" | sort | uniq -c | sort -rn | sed 's/^/    /'
fi
echo

# ---------------------------------------------------------- 8. state-vs-record smells
echo "## 8. State-vs-record candidates"
echo "# Heuristic, for the reviewer to judge. A state doc (contract, runbook, README, spec"
echo "# body, code comment) describes the system as it is now; git holds the history. These"
echo "# lines look like a doc narrating its own revisions."
echo
git grep -n -iE '(corrected [0-9]{4}-[0-9]{2}-[0-9]{2}|an earlier (revision|draft|version)|this (section|doc|file|page) used to|previously (this|it) (said|was)|used to say|before (PR )?#[0-9]+|correction to earlier|~~[^~]{12,}~~)' -- '*.md' 2>/dev/null \
  | grep -viE '(^|/)(CHANGELOG|HISTORY)' \
  | grep -viE '/(archive|runs|analysis|postmortem)/' \
  | grep -viE '/(rca|postmortem)-' \
  | grep -viE '/(sources|vendor|_archive)/' \
  | grep -vE ':[[:space:]]*[-*0-9.]+[[:space:]]*\[[x ]\]' \
  | head -30 > "$TMP/smells" || true
if [ -s "$TMP/smells" ]; then cat "$TMP/smells"; else echo "clean — no state doc is narrating its own past"; fi
echo

# --------------------------------------------------------------------- 9. outliers
echo "## 9. Largest docs"
while read -r f; do
  [ -f "$f" ] && printf '%s %s\n' "$(bytes "$f")" "$f"
done < "$TMP/md" > "$TMP/sizes" || true
{ sort -rn "$TMP/sizes" | head -10 | awk '{printf "    %8dB  %s\n", $1, $2}'; } || true
echo

# ------------------------------------------------------------------ 10. enforcement
echo "## 10. Enforcement"
git ls-files | grep -iE 'check-agents(-md)?-budget|agents-budget|docs?-lint|markdown-?lint|check-lessons' > "$TMP/gates" || true
if [ -s "$TMP/gates" ]; then { sed 's/^/    gate: /' "$TMP/gates" | head -10; } || true; else
  echo "    NONE — no documentation or agent-instruction rule is enforced by CI in this repo,"
  echo "    so every rule here holds only as long as someone re-reads it."
fi
echo
echo "# end of doc-audit"
