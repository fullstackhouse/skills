#!/usr/bin/env bash
# step-timing.sh — per-job and per-step minutes for one workflow: n, median, min, max.
#
#   step-timing.sh --workflow deploy-preview.yml            # last 25 successful runs
#   step-timing.sh --workflow ci.yml --job e2e              # one job only
#   step-timing.sh --workflow build.yml --branch main --since 2026-10-01 --runs 40
#   step-timing.sh --workflow build.yml --min-seconds 30    # hide steps shorter than 30 s
#
# ci-timing.sh says which workflow is slow; this says which step inside it is. A median
# and a min–max per step is what tells "the build got faster" apart from noise, and it
# is how a non-runner cost (an upload, a disk cleanup) shows up next to the compute.
# Successful runs and jobs only, so a failed attempt can't skew a step. Each job's own
# total is printed as the `(job)` row. Needs `gh`; read-only.
set -euo pipefail

REPO=""
WF=""
JOB=""
BRANCH=""
RUNS=25
MIN_SECONDS=6
SINCE="$(date -u -v-14d +%Y-%m-%d 2>/dev/null || date -u -d '14 days ago' +%Y-%m-%d)"

while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) WF="$2"; shift 2 ;;
    --job) JOB="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --min-seconds) MIN_SECONDS="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$WF" ] || { echo "--workflow is required" >&2; exit 1; }
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

query="/repos/$REPO/actions/workflows/$WF/runs?status=success&created=>$SINCE"
[ -z "$BRANCH" ] || query="$query&branch=$BRANCH"
# The API caps per_page at 100, so page until --runs ids are in hand (or runs run out).
per_page=$(( RUNS < 100 ? RUNS : 100 ))
run_ids=""
page=1
while [ "$(printf '%s' "$run_ids" | grep -c .)" -lt "$RUNS" ]; do
  got=$(gh api "$query&per_page=$per_page&page=$page" -q '.workflow_runs[].id')
  [ -n "$got" ] || break
  run_ids=$(printf '%s\n%s\n' "$run_ids" "$got" | grep .)
  page=$((page + 1))
done
run_ids=$(printf '%s\n' "$run_ids" | awk -v n="$RUNS" 'NF && NR <= n')
[ -n "$run_ids" ] || { echo "no successful runs of $WF since $SINCE" >&2; exit 1; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# job \t step \t seconds, one line per job total and per step.
for id in $run_ids; do
  gh api "/repos/$REPO/actions/runs/$id/jobs?per_page=100" -q '
    def secs(a; b): ((b | sub("\\.[0-9]+"; "") | fromdate) - (a | sub("\\.[0-9]+"; "") | fromdate));
    .jobs[] | select(.conclusion == "success") | . as $j
    | ([$j.name, "(job)", secs($j.started_at; $j.completed_at)] | @tsv),
      ($j.steps[] | select(.started_at and .completed_at)
        | [$j.name, .name, secs(.started_at; .completed_at)] | @tsv)' 2>/dev/null
done > "$tmp"

if [ -n "$JOB" ]; then
  awk -F'\t' -v j="$JOB" '$1 == j' "$tmp" > "$tmp.f"
  mv "$tmp.f" "$tmp"
fi

printf 'repo=%s  workflow=%s  since=%s  runs=%s%s\n\n' "$REPO" "$WF" "$SINCE" \
  "$(echo "$run_ids" | wc -l | tr -d ' ')" "${BRANCH:+  branch=$BRANCH}"
printf '%-24s %-48s %4s %8s %8s %8s\n' JOB STEP N MEDIAN MIN MAX

# Rows keep first-seen order, which is execution order: each job's total, then its
# steps. Values per row are sorted in awk (insertion sort; n is at most --runs).
awk -F'\t' -v min="$MIN_SECONDS" '
  { key = $1 SUBSEP $2
    if (!(key in n)) { order[++k] = key; job[key] = $1; step[key] = $2 }
    v[key, ++n[key]] = $3 }
  END {
    for (i = 1; i <= k; i++) {
      key = order[i]; c = n[key]
      for (a = 2; a <= c; a++) {
        x = v[key, a]
        for (b = a - 1; b >= 1 && v[key, b] > x; b--) v[key, b + 1] = v[key, b]
        v[key, b + 1] = x
      }
      if (step[key] != "(job)" && v[key, c] < min) continue
      med = (c % 2) ? v[key, (c + 1) / 2] : (v[key, c / 2] + v[key, c / 2 + 1]) / 2
      printf "%-24.24s %-48.48s %4d %8.1f %8.1f %8.1f\n", job[key], step[key], c, med / 60, v[key, 1] / 60, v[key, c] / 60
    }
  }' "$tmp"
