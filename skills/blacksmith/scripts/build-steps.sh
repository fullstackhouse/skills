#!/usr/bin/env bash
# build-steps.sh — the BuildKit steps inside one image-build job: which were CACHED, which
# ran, and how long the slowest took.
#
#   build-steps.sh --job-id 116444928714            # a job id from the run's jobs list
#   build-steps.sh --run 38741745018 --job build    # or a run id plus the job's name
#   build-steps.sh --run 38741745018 --job build --top 20
#
# Read it twice. On the second warm build after a migration, the dependency-install
# steps must say CACHED; if they ran, something above them invalidates the cache on
# every commit (a per-commit ARG, a COPY of the whole tree) and no runner fixes that.
# And the slowest steps are where the build time actually goes — it is often not
# compute (a source-map upload, a registry push). Prints ENOSPC hits too. Needs `gh`;
# read-only. Plain BuildKit progress only, which is what CI logs carry.
set -euo pipefail

REPO=""
JOB_ID=""
RUN_ID=""
JOB_NAME=""
TOP=12

while [ $# -gt 0 ]; do
  case "$1" in
    --job-id) JOB_ID="$2"; shift 2 ;;
    --run) RUN_ID="$2"; shift 2 ;;
    --job) JOB_NAME="$2"; shift 2 ;;
    --top) TOP="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
if [ -z "$JOB_ID" ]; then
  [ -n "$RUN_ID" ] && [ -n "$JOB_NAME" ] || { echo "need --job-id, or --run and --job" >&2; exit 1; }
  JOB_ID=$(gh api "/repos/$REPO/actions/runs/$RUN_ID/jobs?per_page=100" \
    -q ".jobs[] | select(.name == \"$JOB_NAME\") | .id" | head -1)
  [ -n "$JOB_ID" ] || { echo "no job named '$JOB_NAME' in run $RUN_ID" >&2; exit 1; }
fi

# Job logs carry ANSI colour codes; gh refuses to print them without the flag. BSD sed
# has no \x1b escape, so the ESC byte goes in literally.
esc=$(printf '\033')
gh api --allow-escape-sequences "/repos/$REPO/actions/jobs/$JOB_ID/logs" \
  | sed -E "s/${esc}\[[0-9;]*m//g; s/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z //" \
  | awk -v top="$TOP" '
      # A step id first appears with its name ("#20 [builder 10/10] RUN yarn build",
      # "#31 exporting to image"); later lines are output ("#20 85.94 ...") or a
      # terminal state ("#20 DONE 366.8s", "#20 CACHED", "#20 ERROR: ...").
      /ENOSPC|no space left on device/ { enospc++ }
      match($0, /^#[0-9]+ /) {
        id = substr($1, 2); rest = substr($0, RLENGTH + 1)
        if (rest ~ /^CACHED/) { state[id] = "CACHED"; next }
        if (rest ~ /^DONE [0-9.]+s/) { split(rest, p, " "); secs[id] = p[2] + 0; if (!(id in state)) state[id] = "ran"; next }
        if (rest ~ /^ERROR/) { state[id] = "ERROR"; next }
        if (rest ~ /^[0-9.]+ / || rest ~ /^(sha256|resolve|extracting|writing|naming|pushing|preparing|done|exporting layers|exporting manifest|exporting config)/) next
        if (!(id in name)) { name[id] = rest; ids[++k] = id }
      }
      END {
        cached = 0; ran = 0
        for (i = 1; i <= k; i++) {
          id = ids[i]
          if (state[id] == "CACHED") cached++; else if (id in secs) ran++
          line[i] = sprintf("%9.1f  %-7s %s", secs[id] + 0, (id in state) ? state[id] : "-", substr(name[id], 1, 110))
          s[i] = secs[id] + 0
        }
        # Slowest first (selection sort; a build has tens of steps, not thousands).
        for (i = 1; i <= k; i++) { m = i; for (j = i + 1; j <= k; j++) if (s[j] > s[m]) m = j
          t = s[i]; s[i] = s[m]; s[m] = t; t = line[i]; line[i] = line[m]; line[m] = t }
        printf "steps=%d  cached=%d  ran=%d  enospc=%d\n\n%9s  %-7s %s\n", k, cached, ran, enospc + 0, "SECONDS", "STATE", "STEP"
        for (i = 1; i <= k && i <= top; i++) print line[i]
        # Dependency installs are the steps that must come back CACHED on a warm build.
        printf "\ninstall steps:\n"
        for (i = 1; i <= k; i++) { id = ids[i]
          if (name[id] ~ /RUN.*(yarn( workspaces focus| install)|npm (ci|install)|pnpm install|bun install|pip install|poetry install|uv sync|bundle install|go mod download|cargo fetch)/)
            printf "%9.1f  %-7s %s\n", secs[id] + 0, (id in state) ? state[id] : "-", substr(name[id], 1, 110) }
      }'
