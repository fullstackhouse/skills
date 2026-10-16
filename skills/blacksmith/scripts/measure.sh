#!/usr/bin/env bash
# measure.sh — time a push-triggered workflow over N real rebuilds, one at a time.
#
#   measure.sh --workflow deploy-preview.yml --file apps/web/ci-measure.txt --label A --runs 5
#   measure.sh --workflow deploy-preview.yml --file apps/web/ci-measure.txt --label B --runs 5
#   measure.sh --workflow build.yml --file app/ci-measure.txt --label A --start 3 --runs 3   # resume
#   measure.sh --summary                                                           # medians so far
#   measure.sh --workflow deploy-preview.yml --file apps/web/ci-measure.txt --label A --dry-run
#
# Each run overwrites --file with one new line, commits, pushes, waits for --workflow's
# run on that commit and records it. The file must sit inside the Docker build context
# (and not be .dockerignored), so the push invalidates `COPY . .` and everything after
# it, the way a real PR does. A re-dispatch of an unchanged commit hits every layer and
# measures nothing (hard rule 6). Runs go strictly one at a time: two in flight would
# race on the sticky disk and on whatever the workflow deploys.
#
# When the run fails but --build-job succeeded, the failure is downstream of the build
# (a deploy, a migration): the failed jobs are re-run once and the build numbers kept;
# end-to-end time for that run is left blank. A failed build stops the loop.
#
# Records go to --out (default blacksmith-measure.tsv): label, run, run id, sha,
# conclusion, end-to-end min, build-job min, per-job min, and the install steps' state
# from build-steps.sh. It refuses to run unless the current branch has an open PR. Delete --file
# and the measurement commits (squash-merge) before the PR merges. Needs `gh`, `git`.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=""
WF=""
FILE=""
LABEL=""
RUNS=5
START=1
BUILD_JOB="build"
OUT="blacksmith-measure.tsv"
SUMMARY=0
DRY_RUN=0
POLL=30
MAX_WAIT_MIN=180

while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) WF="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --build-job) BUILD_JOB="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --summary) SUMMARY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

summary() {
  [ -s "$OUT" ] || { echo "no records in $OUT"; return; }
  printf '%-16s %3s %16s %16s\n' LABEL N "END_TO_END_MED" "BUILD_JOB_MED"
  # Column 6 is end-to-end (blank after a re-run), column 7 the build job.
  for l in $(tail -n +2 "$OUT" | cut -f1 | sort -u); do
    e2e=$(awk -F'\t' -v l="$l" '$1 == l && $6 != "" { print $6 }' "$OUT" | sort -n)
    bld=$(awk -F'\t' -v l="$l" '$1 == l && $7 != "" { print $7 }' "$OUT" | sort -n)
    med() { awk '{ v[NR] = $1 } END { if (NR == 0) { print "-"; exit } printf "%.1f (n=%d)", (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2, NR }'; }
    printf '%-16s %3s %16s %16s\n' "$l" "$(awk -F'\t' -v l="$l" '$1 == l' "$OUT" | wc -l | tr -d ' ')" \
      "$(echo "$e2e" | grep . | med)" "$(echo "$bld" | grep . | med)"
  done
}
if [ "$SUMMARY" = 1 ]; then summary; exit 0; fi

[ -n "$WF" ] && [ -n "$FILE" ] && [ -n "$LABEL" ] || { echo "need --workflow, --file and --label" >&2; exit 1; }
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
branch=$(git rev-parse --abbrev-ref HEAD)
default=$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name)
[ "$branch" != "$default" ] || { echo "refusing to push measurement commits to $default" >&2; exit 1; }
# Measurement commits belong on the migration PR and nowhere else. Checking for an open PR
# also stops a push from minting a new remote branch (push.autoSetupRemote) by accident.
pr=$(gh pr view "$branch" --repo "$REPO" --json number,state -q 'select(.state == "OPEN") | .number' 2>/dev/null || true)
[ -n "$pr" ] || { echo "branch $branch has no open PR; open the migration PR first" >&2; exit 1; }
if [ "$DRY_RUN" = 1 ]; then
  echo "dry run: would push $RUNS measurement commit(s) to $branch (PR #$pr), touching $FILE, timing $WF"
  exit 0
fi
[ -z "$(git status --porcelain --untracked-files=no -- . ":!$FILE")" ] || { echo "working tree has other changes; commit or set them aside first" >&2; exit 1; }
[ -s "$OUT" ] || printf 'label\trun\trun_id\tsha\tconclusion\te2e_min\tbuild_min\tjobs\tinstall_steps\n' > "$OUT"

minutes() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", (b - a) / 60 }'; }
epoch() { date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s; }

wait_completed() {   # run id → prints conclusion when done
  local waited=0
  while :; do
    s=$(gh api "/repos/$REPO/actions/runs/$1" -q '.status + " " + (.conclusion // "")' 2>/dev/null || echo "unknown ")
    case "$s" in completed*) echo "${s#completed }"; return ;; esac
    sleep "$POLL"; waited=$((waited + POLL))
    [ "$waited" -lt $((MAX_WAIT_MIN * 60)) ] || { echo "timeout"; return; }
  done
}

i=$START
while [ "$i" -lt $((START + RUNS)) ]; do
  echo "measurement $LABEL run $i, $(date -u +%Y-%m-%dT%H:%M:%SZ) — delete before merge" > "$FILE"
  git add "$FILE"
  git commit -q -m "chore(ci): measurement rebuild $LABEL run $i (drop before merge)"
  git push -q
  sha=$(git rev-parse HEAD)

  # The run appears a few seconds after the push; match on the workflow file, not its name.
  run_id=""
  for _ in $(seq 1 40); do
    run_id=$(gh api "/repos/$REPO/actions/runs?head_sha=$sha&per_page=50" \
      -q ".workflow_runs[] | select(.path | endswith(\"/$WF\")) | .id" 2>/dev/null | head -1)
    [ -z "$run_id" ] || break
    sleep 15
  done
  [ -n "$run_id" ] || { echo "STOP $LABEL $i: no $WF run for $sha" >&2; exit 1; }

  conclusion=$(wait_completed "$run_id")
  # A timed-out run is still in progress: re-running it would error, so stop here.
  [ "$conclusion" != "timeout" ] || { echo "STOP $LABEL $i: run $run_id still running after ${MAX_WAIT_MIN} min" >&2; exit 1; }
  rerun=0
  if [ "$conclusion" != "success" ]; then
    b=$(gh api "/repos/$REPO/actions/runs/$run_id/jobs?per_page=100" -q ".jobs[] | select(.name == \"$BUILD_JOB\") | .conclusion" | head -1)
    if [ "$b" = "success" ]; then
      echo "RERUN $LABEL $i: run $run_id $conclusion after a green $BUILD_JOB; re-running failed jobs once"
      gh run rerun "$run_id" --failed --repo "$REPO" >/dev/null
      sleep "$POLL"
      conclusion=$(wait_completed "$run_id")
      [ "$conclusion" != "timeout" ] || { echo "STOP $LABEL $i: re-run of $run_id still running after ${MAX_WAIT_MIN} min" >&2; exit 1; }
      rerun=1
    fi
  fi

  run=$(gh api "/repos/$REPO/actions/runs/$run_id" -q '[.run_started_at, .updated_at] | @tsv')
  e2e=""
  [ "$rerun" = 1 ] || e2e=$(minutes "$(epoch "${run%%$'\t'*}")" "$(epoch "${run##*$'\t'}")")
  jobs=$(gh api "/repos/$REPO/actions/runs/$run_id/jobs?per_page=100" -q '
    .jobs[] | select(.started_at and .completed_at)
    | "\(.name)=\((((.completed_at | fromdate) - (.started_at | fromdate)) / 60 * 100 | floor) / 100)"' | paste -sd, -)
  build_min=$(echo "$jobs" | tr ',' '\n' | awk -F= -v j="$BUILD_JOB" '$1 == j { print $2 }')
  installs=$("$HERE/build-steps.sh" --repo "$REPO" --run "$run_id" --job "$BUILD_JOB" --top 0 2>/dev/null \
    | awk '/^install steps:/ { on = 1; next } on && NF { printf "%s%s:%s", sep, $2, $1; sep = "," }' || true)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$LABEL" "$i" "$run_id" "${sha:0:9}" "$conclusion" "$e2e" "$build_min" "$jobs" "$installs" >> "$OUT"
  echo "$LABEL run $i: $conclusion e2e=${e2e:-re-run} $BUILD_JOB=${build_min:-?}min jobs=[$jobs] installs=[$installs]"

  [ "$conclusion" = "success" ] || { echo "STOP $LABEL $i: run $run_id concluded $conclusion" >&2; exit 1; }
  i=$((i + 1))
done
echo "DONE $LABEL"
summary
