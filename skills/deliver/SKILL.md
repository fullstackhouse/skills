---
name: deliver
description: Deliver the work on the current branch — run all relevant local checks (lint/typecheck/tests) to front-load what CI would catch, open or update a PR, request a reviewer (or re-review if one already exists), address the feedback, then auto-merge if changes since invocation are minimal. CI is slow; do not lean on it as a first pass.
---

# deliver

You are running the **deliver** skill. Goal: take whatever is on the current branch and get it merged with as few CI round-trips as possible.

CI is slow and every avoidable push is a real cost — front-load all checks locally before pushing.

## Project specifics — read these first

This skill is repo-agnostic. The concrete commands, reviewer, and merge policy come from the repository you're running in. Before Phase 1, gather:

- **Check commands per package** — how to lint / typecheck / test / run codegen for each workspace. Derive from the repo's `CLAUDE.md` / `AGENTS.md`, per-package docs, and `package.json` (`scripts`) / `Makefile` / `justfile`. If the repo has a **`## Skill profile`** section in its root `CLAUDE.md`, use that — it's the curated source.
- **Repo slug** — `gh repo view --json nameWithOwner -q .nameWithOwner`.
- **Default branch** — `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
- **PR reviewer bot** — from the `## Skill profile` (`reviewer`), default `copilot-pull-request-reviewer`.
- **ownerCanSelfMerge** — from the `## Skill profile`; gates whether `gh pr merge --admin` is acceptable (see Phase 8). Default: false (don't bypass required reviews).
- **Dev-server / port convention** — if the repo documents one (e.g. a worktree port rule), follow it whenever you need to start a service for a local test.

If a needed value isn't documented and you can't infer it, ask the user rather than guessing.

## Phases

### 0. Anchor

Before doing anything, record the starting SHA so the "not much changed since invocation" check at the end is meaningful:

```bash
mkdir -p .context/deliver
git rev-parse HEAD > .context/deliver/start-sha
git rev-parse --abbrev-ref HEAD > .context/deliver/branch
```

Refuse to run on the default branch. If the working tree has uncommitted changes, surface them and ask the user before continuing — don't silently `git add -A`.

### 1. Scope detection

Look at `git diff <default-branch>...HEAD --name-only` and bucket the touched files by package/workspace (top-level dir, monorepo workspace, or whatever the repo's structure is). Only run the checks for packages that actually changed — don't run one package's tooling for a branch that didn't touch it.

### 2. Local checks (front-load CI)

Run the touched packages' checks IN PARALLEL where independent. These are the same gates CI runs — if any fail, fix locally before pushing. For each touched package, run its documented:

- **Codegen** (e.g. GraphQL/types) — only if the relevant source changed; never hand-edit generated files.
- **Typecheck.**
- **Lint with autofix** — run the real linter, not just a formatter. A formatter (prettier and friends) does NOT catch what the linter (ESLint and friends) catches; run both if the repo separates them.
- **i18n extraction / translation** — only if user-facing strings changed.
- **Targeted tests** — the unit/integration tests closest to the diff. **Never run a full suite as a pre-push gate** — it's far too slow; CI owns full suites. Pick the test files closest to the change.
- **e2e** — run ONLY the spec(s) directly related to the change. The full e2e suite is too slow for a pre-push gate. If this is a user-facing feature change and there's no e2e spec for it, the change isn't ready — write one (don't ship user-facing behavior without an e2e, and don't mark a planned e2e "optional").
- **Infra** (if touched) — format + validate the changed config (e.g. `tofu fmt`/`tofu validate`). Never `apply` from this skill.

If any check fails: fix it, re-run, then commit. Keep history clean — squash fixups into the commit they belong to where reasonable.

### 3. Commit & push

Commit any work made during local checks under the same authorship as the branch's existing commits. Use Conventional Commits.

If the branch isn't pushed yet, push with `-u`. If it is, just push.

### 4. PR open or update

```bash
gh pr view --json number,url,reviewDecision,reviews,headRefOid 2>/dev/null
```

- No PR → `gh pr create --base <default-branch>`. Title in Conventional Commits style stating the plain-language outcome. Write the body top-down per the **pr-polish** skill's structure: context/task line → the problem (observable impact, no code identifiers) → the fix (root cause + what the PR does) → technical details → verification → follow-ups.
- PR exists → the push updated the code, but check the title/description still tell the truth: if the work drifted since they were written (rebase, review rework, scope change, a referenced PR merged), run the **pr-polish** skill before requesting review — a stale description misleads the reviewer.

Save the PR number to `.context/deliver/pr-number`.

### 5. Request reviewer

`SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)`, `REVIEWER` = the configured bot (default `copilot-pull-request-reviewer`). Determine state first:

```bash
gh pr view <N> --json reviews --jq ".reviews[] | select(.author.login == \"Copilot\" or .author.login == \"$REVIEWER\")"
```

- **No prior review by the bot** → request one:
  ```bash
  gh pr edit <N> --add-reviewer "$REVIEWER"
  ```
  If that errors with "not a collaborator", fall back to:
  ```bash
  gh api -X POST "repos/$SLUG/pulls/<N>/requested_reviewers" -f "reviewers[]=$REVIEWER"
  ```
- **Prior review exists** → request a re-review (re-requesting a reviewer who already reviewed triggers a fresh review against the new HEAD):
  ```bash
  gh api -X POST "repos/$SLUG/pulls/<N>/requested_reviewers" -f "reviewers[]=$REVIEWER"
  ```

### 6. Wait for the review

The bot typically takes 1–5 minutes. Poll, don't busy-wait:

```bash
gh pr view <N> --json reviews --jq "[.reviews[] | select(.author.login == \"Copilot\" or .author.login == \"$REVIEWER\")] | sort_by(.submittedAt) | last"
```

Poll every ~60s for up to ~10 minutes. If nothing arrives after 10 minutes, surface that to the user and stop — don't auto-merge without a review.

Also pull inline review comments (most feedback is line comments, not the top-level review body):

```bash
gh api "repos/$SLUG/pulls/<N>/comments" --paginate
```

Filter to comments authored by the bot and posted at or after the review's `submittedAt`.

### 7. Address feedback

Pushing a fix alone is not enough — also respond on the thread. For every actionable comment:

1. Implement the fix locally.
2. Re-run the relevant local checks from Phase 2 for the files you touched (don't skip — CI re-running is slower than a 30s local lint).
3. Commit and push.
4. Reply to the comment thread explaining what changed (`gh api -X POST "repos/$SLUG/pulls/<N>/comments/<comment-id>/replies" -f body=...`) AND resolve the thread via the GraphQL `resolveReviewThread` mutation. Both — reply without resolve leaves a noisy unresolved thread; resolve without reply leaves the reviewer guessing.
5. For feedback you disagree with: reply explaining why, but don't resolve unilaterally — leave it for the user to settle.

If the reviewer raises issues big enough to need new tests or a substantive redesign, stop and tell the user. Don't quietly expand scope.

### 7b. Handle CI failures

In parallel with waiting for the review, monitor CI:

```bash
gh pr checks <N> --watch
```

If any check fails, **fix it and keep going** — don't stop and hand back to the user. Workflow:

1. Pull the failing job's logs: `gh run view <run-id> --log-failed` (use `gh pr checks <N> --json` to find the run id).
2. Diagnose the root cause. Common buckets:
   - **Lint / typecheck / format** — a Phase 2 check that should have been caught locally. Run it locally now, fix, push. Then ask why Phase 2 missed it (skipped a package? formatted but didn't lint?) so it doesn't recur this run.
   - **Unit / integration tests** — reproduce locally with the exact same command CI ran, fix the underlying code or test, push.
   - **e2e flake** — re-run the failed job once (`gh run rerun <run-id> --failed`). If it fails a second time on the same spec with the same fingerprint, it's not a flake — diagnose properly (a `flake-hunt` skill exists for this; invoke it if the failure looks genuinely race-y). Never paper over with retries/skip/timeout.
   - **Migration / DB** — run the repo's migration check; if a manual migration is missing a snapshot/state update, fix per the repo's docs.
   - **Infra** — fix the config, re-run format + validate locally.
3. Push the fix. CI restarts; loop back to monitoring.

Hard stop conditions (escalate to user, don't keep grinding):
- Same failure recurs after 3 fix attempts on the same job — your hypothesis is wrong; stop and ask.
- The fix would require changes outside this branch's scope (e.g. updating a shared package, infra credentials).
- A test failure points at a real bug in code outside the diff (this branch surfaced it but didn't cause it).

Do not merge while any required check is failing or pending. `--admin` bypasses required reviews, not failing CI (see Hard rules).

### 8. Auto-merge decision

If not much has changed since the skill started, just merge. "Not much" means the work since Phase 0's `start-sha` is mostly review-feedback fixups, not new functionality.

Compute:

```bash
START=$(cat .context/deliver/start-sha)
git diff --shortstat "$START"...HEAD     # lines changed since invocation
git log --oneline "$START"..HEAD          # commits since invocation
```

Merge condition (ALL must hold):
- ≤ ~100 lines changed since `start-sha`, AND
- No new files outside what was already touched at `start-sha`, AND
- All CI checks on the PR are green (`gh pr checks <N>` — wait for them), AND
- The review is `APPROVED` or `COMMENTED` with no remaining unresolved actionable threads.

If the condition holds → merge:

```bash
gh pr merge <N> --squash --delete-branch        # add --admin only if ownerCanSelfMerge
```

Use `--admin` **only** when the `## Skill profile` says `ownerCanSelfMerge: true` (the user owns the repo and doesn't need peer approval). Otherwise merge normally and let required reviews apply; if a required review blocks, surface that and stop.

If the condition doesn't hold (substantial new code, failing checks, unresolved threads, or no review yet) → don't merge. Surface the state to the user and stop.

### 9. Report

Final message to the user must include: PR URL, merge status (merged / awaiting-CI / awaiting-review / blocked), and any decisions you punted (e.g. "left thread #X unresolved because the suggestion conflicts with the documented convention — please weigh in").

## Hard rules

1. **Never `--no-verify`, never `--no-gpg-sign`.** If a pre-commit hook fails, fix the root cause.
2. **Never push to the default branch.** This skill operates on a feature branch only.
3. **Never run a full test suite locally** — not full e2e, not full unit/integration. Targeted runs only; CI owns full suites. A pre-push gate that takes >2 min defeats the point of front-loading.
4. **Never merge without CI green.** Even with `--admin`, wait for `gh pr checks` to be green. Bypassing required reviews is one thing; bypassing failing CI is not.
5. **Don't expand scope under cover of review feedback.** If a suggestion is a refactor beyond the PR's purpose, push back in the thread instead of doing it.
6. **Follow the repo's dev-server/port convention** when you start a service for a local test. Don't auto-launch a whole-stack dev script.
