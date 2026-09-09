#!/usr/bin/env bash
# ci-timing.sh — GitHub Actions job time per workflow, split by runner label and priced
# at GitHub's and Blacksmith's per-minute rates.
#
#   ci-timing.sh                              # last 14 days, every active workflow
#   ci-timing.sh --since 2026-08-25           # explicit start date
#   ci-timing.sh --workflow ci.yml --workflow build.yml
#   ci-timing.sh --runs 30                    # runs sampled per workflow (default 25)
#   ci-timing.sh --repo owner/name            # default: the repo of the current directory
#
# Capture a window before a runner change and the same window after, then diff them.
# Wall-clock per job is what a developer waits on; the vCPU-weighted cost is what the
# invoice bills, so both are printed. Reusable (`workflow_call`) workflows report no runs
# of their own — their jobs bill under the caller — so query the calling workflow.
# Needs `gh` authenticated against the repo. Output is column-aligned text that pastes
# into a PR body inside a ``` block. Read-only.
set -euo pipefail

REPO=""
SINCE="$(date -u -v-14d +%Y-%m-%d 2>/dev/null || date -u -d '14 days ago' +%Y-%m-%d)"
RUNS_PER_WF=25
WORKFLOWS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --workflow) WORKFLOWS+=("$2"); shift 2 ;;
    --runs) RUNS_PER_WF="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# USD per minute. GitHub: the 2026-01 rates. Blacksmith: linear in vCPU off a $0.004
# 2-vCPU x64 base ($0.0025 arm). Matched on substrings because a job's label list may
# carry more than one label. Unknown labels are priced as a standard 2-core runner.
rate_for() {
  case "$1" in
    *self-hosted*)                          echo 0 ;;
    *blacksmith-32vcpu*arm*)                echo 0.04 ;;
    *blacksmith-16vcpu*arm*)                echo 0.02 ;;
    *blacksmith-8vcpu*arm*)                 echo 0.01 ;;
    *blacksmith-4vcpu*arm*)                 echo 0.005 ;;
    *blacksmith-2vcpu*arm*)                 echo 0.0025 ;;
    *blacksmith-32vcpu*)                    echo 0.064 ;;
    *blacksmith-16vcpu*)                    echo 0.032 ;;
    *blacksmith-8vcpu*)                     echo 0.016 ;;
    *blacksmith-4vcpu*)                     echo 0.008 ;;
    *blacksmith-2vcpu*)                     echo 0.004 ;;
    *-16-cores*)                            echo 0.042 ;;
    *-8-cores*)                             echo 0.022 ;;
    *-4-cores*)                             echo 0.012 ;;
    *)                                      echo 0.006 ;;
  esac
}

if [ "${#WORKFLOWS[@]}" -eq 0 ]; then
  # `mapfile` is bash 4+; macOS ships 3.2.
  while IFS= read -r wf_path; do
    WORKFLOWS+=("$wf_path")
  done < <(
    gh api "/repos/$REPO/actions/workflows?per_page=100" --paginate \
      -q '.workflows[] | select(.state=="active") | .path' | sed 's#.*/##'
  )
fi

printf 'repo=%s  since=%s  sample=%s runs/workflow\n\n' "$REPO" "$SINCE" "$RUNS_PER_WF"
printf '%-38s %-32s %6s %9s %9s\n' WORKFLOW RUNNER JOBS AVG_MIN USD_EST

total_usd=0
for wf in "${WORKFLOWS[@]}"; do
  run_ids=$(
    gh api "/repos/$REPO/actions/workflows/$wf/runs?per_page=$RUNS_PER_WF&created=>$SINCE" \
      -q '.workflow_runs[] | select(.status=="completed") | .id' 2>/dev/null | head -"$RUNS_PER_WF"
  ) || continue
  [ -n "$run_ids" ] || continue

  # label \t seconds, one line per job
  rows=$(
    for id in $run_ids; do
      gh api "/repos/$REPO/actions/runs/$id/jobs?per_page=100" \
        -q '.jobs[] | select(.started_at and .completed_at and .conclusion != "skipped")
            | [(.labels | join(",")), ((.completed_at|fromdate) - (.started_at|fromdate))] | @tsv' 2>/dev/null
    done
  )
  [ -n "$rows" ] || continue

  while IFS=$'\t' read -r label jobs secs; do
    [ -n "$label" ] || label='(unknown)'
    rate=$(rate_for "$label")
    mins=$(echo "scale=4; $secs / 60" | bc)
    avg=$(echo "scale=1; $mins / $jobs" | bc)
    # bc's scale= governs division only, so round the products explicitly.
    usd=$(printf '%.2f' "$(echo "$mins * $rate" | bc)")
    total_usd=$(printf '%.2f' "$(echo "$total_usd + $usd" | bc)")
    printf '%-38s %-32s %6s %9s %9s\n' "${wf%.yml}" "$label" "$jobs" "$avg" "$usd"
  done < <(
    echo "$rows" | awk -F'\t' '{n[$1]++; s[$1]+=$2} END {for (k in n) printf "%s\t%d\t%d\n", k, n[k], s[k]}' | sort
  )
done

printf '\n%-71s %9s\n' 'SAMPLED COST (not a monthly projection — scale by run volume)' "$total_usd"
