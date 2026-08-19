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
- **Repo identity** — one call covers slug, default branch, and the audience the Phase 2b gate keys on:
  ```bash
  gh repo view --json nameWithOwner,defaultBranchRef,visibility,owner
  ```
- **PR reviewer bot** — from the `## Skill profile` (`reviewer`). Copilot needs two names, not one: `@copilot` to request it, `copilot-pull-request-reviewer` to recognise its reviews (see Phase 5).
- **ownerCanSelfMerge** — from the `## Skill profile`; gates whether `gh pr merge --admin` is acceptable (see Phase 8). Default: false (don't bypass required reviews).
- **Dev-server / port convention** — if the repo documents one (e.g. a worktree port rule), follow it whenever you need to start a service for a local test.
- **Tracker + its status vocabulary** — from the `## Skill profile` (`tracker`). If the repo documents which states mean *in progress*, *in review* and *done*, this skill moves the task along with the PR (Phases 4b and 8b). If it documents a tracker but no vocabulary, don't guess at state names — report the task's current state in Phase 9 instead.

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

### 2b. Confidentiality gate — only if this repo is not the sole audience

The audience came from the Phase 0 `gh repo view` — no extra call. The gate fires when the repo is **public**, or when its owner is not the client whose material the branch draws on (an FSH-internal repo, another client's repo, a shared library). It does not fire for a private repo owned by the same client the work is for — there, their own details are in their own house.

When it fires: **no client's non-public details may land in the push.** Names, staff, repo names, local paths (`~/src/<client>/…`), internal spec/ticket IDs, name-carrying identifiers (module and table prefixes, env-var prefixes, service names), infrastructure (hostnames, endpoints, account IDs), and their data (fixtures, seed data, screenshots, logs). This holds *even when the mention is flattering* — crediting where a pattern was proven ("ported from client X's field-tested module") is the most common way a name reaches a public diff. State the engineering claim, drop the address. The only exception is a detail already public in the client's own material, verified rather than assumed.

Scan the diff, the commit messages, and the PR body before they are published:

```bash
TERMS='acme|acmecorp|acme_|ACME-'                                  # from what the branch drew on
git diff "$DEFAULT_BRANCH"...HEAD | grep -inE "$TERMS"
git log "$DEFAULT_BRANCH"..HEAD --format='%B' | grep -inE "$TERMS"
```

Grep is the floor — also read the prose the branch adds (specs, READMEs, comments). On a hit before pushing: rewrite (amend/rebase is fine, nothing is published yet). On a hit in something already pushed or public: **stop and tell the user** — never force-push to hide it, and never decide alone whether to rewrite published history.

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

### 4b. Tracker — the work is now up for review

Skip entirely if the repo documents no tracker vocabulary (see Project specifics).

Resolve the task from the PR body's task line — the repo's own convention (`Closes X` / `Part of X` / `Relates to X`). Then, in one fetch of that task:

- **Assigned to someone other than the user you're working for → touch nothing.** Report it in Phase 9. You don't know what that person is doing with it.
- Still in a *not started* state → move it to *in progress*, then to *in review*. A pushed branch with a PR is unambiguously both; there's no point recording only the later one.
- Already in *in review* or a terminal state → leave it.

Move the task named by `Closes`. A `Part of` / `Relates to` task belongs to work wider than this PR — leave those alone at every phase.

### 5. Request reviewer

Assign all three up front — an unset `REVIEWER_AUTHOR` interpolates to `""`, which matches no review and fails exactly the silent-empty way this phase exists to prevent:

```bash
SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
REVIEWER=${PROFILE_REVIEWER:-@copilot}                          # what to request
REVIEWER_AUTHOR=${PROFILE_REVIEWER:-copilot-pull-request-reviewer}   # what reviews are authored by
```

`PROFILE_REVIEWER` is the `## Skill profile` `reviewer` knob, unset when the repo documents none. **A configured value replaces both names**, which works because a bot's own login is accepted by `gh pr edit` as well as its alias — so a repo running a different reviewer bot gets it requested *and* recognised, rather than Copilot requested and its own bot polled for.

**Why two variables and not one:** Copilot answers to a different name in each API. Measured on `gh` 2.95.0 against a repo where the bot works:

| Name | `gh pr edit --add-reviewer` | REST `POST .../requested_reviewers` | authors reviews as |
|---|---|---|---|
| `@copilot` | ✅ lands (documented alias) | — | — |
| `copilot-pull-request-reviewer` | ✅ lands | ❌ `422 … not a collaborator` | ✅ |
| `Copilot` | ❌ `Could not resolve user with login` | ✅ | — |

So this phase uses exactly two: `@copilot` to request, and `copilot-pull-request-reviewer` to recognise the review when it arrives. The REST **reviewers** endpoint is not used at all, which is what removes the need for the third spelling. (REST is still used later in this phase for review comments and thread replies.)

**Record a baseline first.** On a re-request the bot's previous review is already on the PR, so without this Phase 6's first poll returns instantly with the *old* review and Phase 7 addresses feedback written against an earlier HEAD:

```bash
PRIOR=$(gh pr view <N> --json reviews \
  --jq "[.reviews[] | select(.author.login == \"$REVIEWER_AUTHOR\")] | sort_by(.submittedAt) | last | .submittedAt // \"\"")
```

"A review exists" and "a review of this HEAD exists" are different questions, and only the second one may gate a merge.

**Request, or re-request, with the same command.** `gh pr edit --add-reviewer` both adds a reviewer and re-requests one who has already reviewed, and a re-request is what triggers a fresh review against the new HEAD:

```bash
gh pr edit <N> --add-reviewer "$REVIEWER"
```

**Do not verify by reading `reviewRequests` back — neither API can answer the question.** REST `requested_reviewers` returns only `{users, teams}` and omits bot reviewers entirely; the GraphQL form (`gh pr view <N> --json reviewRequests`) does see them, but a landed request **disappears from it the instant the reviewer submits**. Copilot often reviews within a minute or two, so the faster it works, the more certainly a read-back shows nothing.

The success signal is a review arriving, not a request being visible — and Phase 6 is already polling for exactly that.

**A failed request is not a missing review.** Many repos have Copilot reviewing automatically on open, with no request from anyone. So report the failure, keep polling, and only when Phase 6 times out with no bot review fall back to humans:

```bash
AUTHOR=$(gh pr view <N> --json author --jq .author.login)
gh pr list --state merged --limit 20 --json reviews \
  --jq "[.[].reviews[].author.login] | map(select(. != \"$AUTHOR\" and . != \"$REVIEWER_AUTHOR\")) | group_by(.) | max_by(length)[0]"
```

**No candidate → stop and ask.** `max_by(length)[0]` returns `null` on an empty list and exits 0, so an unguarded run would request a reviewer literally named `null` — a young repo, or one whose only reviewers so far are the author and the bot, hits this. Excluding the author is not cosmetic either: whoever runs this skill is usually the PR's author, and requesting the author returns `422 Review cannot be requested from pull request author` — failing in the same silent shape as the bug this phase exists to prevent. Prefer `reviewers` from the `## Skill profile` when it is set; the query above is the fallback's fallback. Never treat "no bot review" as "no review needed".

### 6. Wait for the review

The bot typically takes 1–5 minutes. Poll, don't busy-wait:

```bash
gh pr view <N> --json reviews \
  --jq "[.reviews[] | select(.author.login == \"$REVIEWER_AUTHOR\" and .submittedAt > \"$PRIOR\")] | sort_by(.submittedAt) | last"
```

Poll every ~60s for up to ~10 minutes, and require a review **newer than `$PRIOR`** — an earlier one is feedback against an earlier HEAD.

If nothing newer arrives by then, request a human as Phase 5 describes, report `awaiting-review`, and **stop**. The bot earns a ten-minute poll; a human does not — do not wait on one. Either way **a review is required**: never auto-merge without one.

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
- **Nothing is stacked on top of this PR's base** — that is the precise question, and "the base is the default branch" only approximates it: plenty of repos ship through a release or integration branch, and such a repo could never auto-merge under that rule.

  ```bash
  BASE=$(gh pr view <N> --json baseRefName --jq .baseRefName)
  DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
  # A PR onto the default branch cannot be stacked — skip the query entirely.
  [ "$BASE" = "$DEFAULT" ] || gh pr list --state open --head "$BASE" --json number,url
  ```

  The short-circuit is load-bearing, not an optimisation: `--head` matches on branch *name* and includes cross-repository PRs, so one open fork PR whose head branch is called `main` would otherwise mark **every** PR in the repo as stacked and disable auto-merge outright.

  A hit means the base is itself an open PR waiting to land. Merging into it folds this work into that PR, enlarging a diff someone is mid-review on, and ships nothing. Stop and tell the user to land the parent first. Never retarget the base yourself — that silently changes what the approvals on record applied to. AND
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

### 8b. Tracker — close the task

Only once the merge has actually succeeded, and only for the task named by `Closes`: move it to the *done* state. Same guard as 4b — never a task assigned to someone else.

If the PR only says `Part of` / `Relates to`, or the merge didn't happen, leave the task where 4b put it and say so in Phase 9. Never set an *abandoned* / *cancelled* / *won't do* state from this skill; that's a human judgement, not a consequence of a merge.

Acceptance criteria the merge can't prove (something observable only in a deployed environment) are yours to check *before* moving the task, not to assume. If you can't check them, leave the task in review and say what's outstanding.

### 9. Report

Final message to the user must include: PR URL, merge status (merged / awaiting-CI / awaiting-review / blocked-on-parent-PR / blocked), whether the reviewer bot was actually reachable, the tracker task and the state you left it in (or why you didn't move it), and any decisions you punted (e.g. "left thread #X unresolved because the suggestion conflicts with the documented convention — please weigh in").

## Hard rules

1. **Never `--no-verify`, never `--no-gpg-sign`.** If a pre-commit hook fails, fix the root cause.
2. **Never push to the default branch.** This skill operates on a feature branch only.
3. **Never run a full test suite locally** — not full e2e, not full unit/integration. Targeted runs only; CI owns full suites. A pre-push gate that takes >2 min defeats the point of front-loading.
4. **Never merge without CI green.** Even with `--admin`, wait for `gh pr checks` to be green. Bypassing required reviews is one thing; bypassing failing CI is not.
5. **Don't expand scope under cover of review feedback.** If a suggestion is a refactor beyond the PR's purpose, push back in the thread instead of doing it.
6. **Never publish a client's non-public details** into a public repo or one owned by anyone but that client — not in the diff, the commit messages, the PR body, or a review reply. See the Phase 2b gate. It's the one failure here a later commit can't undo.
7. **Follow the repo's dev-server/port convention** when you start a service for a local test. Don't auto-launch a whole-stack dev script.
8. **Never move a tracker task that belongs to someone else**, and never move one to *done* on anything but a successful merge of a PR that says it closes it. A wrong status is worse than a stale one — it's read as a fact by people who weren't in this session.
