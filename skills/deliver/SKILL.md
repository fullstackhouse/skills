---
name: deliver
description: Deliver the work on the current branch — run all relevant local checks (lint/typecheck/tests) to front-load what CI would catch, open or update a PR, request a reviewer (or re-review if one already exists), address the feedback, then auto-merge if changes since invocation are minimal. Supports --no-merge to stop at ready-for-review instead, and --base to target a branch other than the repo default (stacked PRs). CI is slow; do not lean on it as a first pass.
---

# deliver

You are running the **deliver** skill. Goal: take whatever is on the current branch and get it merged with as few CI round-trips as possible.

CI is slow and every avoidable push is a real cost — front-load all checks locally before pushing.

**No-merge mode:** when invoked with `--no-merge` (how the **kickoff** skill calls this), everything through Phase 7/7b runs unchanged — checks, confidentiality gate, PR, reviewer, feedback and CI loops, the tracker's move to *in review* — but Phase 8's merge condition is forced false: leave the PR ready for review, skip Phase 8b, and report. The merge decision stays with the human.

**Stacked mode:** when invoked with `--base <branch>`, that branch — not the repo's default branch — is what this PR targets and what every diff in this run is computed against. Its purpose is stacking: the parent branch is usually itself an open PR, so this PR's diff shows only the increment on top of it instead of replaying the parent's changes. Phase 0 resolves it once into `BASE_REF`; nothing downstream re-derives it. Phase 8's stacked-base check then does exactly what it always did — a base that is an open PR blocks auto-merge — which under `--base` is the expected outcome, not a surprise: land the parent first.

## Project specifics — read these first

This skill is repo-agnostic. The concrete commands, reviewer, and merge policy come from the repository you're running in. Before Phase 1, gather:

- **Check commands per package** — how to lint / typecheck / test / run codegen for each workspace. Derive from the repo's `CLAUDE.md` / `AGENTS.md`, per-package docs, and `package.json` (`scripts`) / `Makefile` / `justfile`. If the repo has a **`## Skill profile`** section in its root `CLAUDE.md`, use that — it's the curated source.
- **Repo identity** — one call covers slug, default branch, and the audience the Phase 2b gate keys on:
  ```bash
  gh repo view --json nameWithOwner,defaultBranchRef,visibility,owner
  ```
- **PR base** — where this PR is meant to land. **The GitHub default branch is the last resort, not the first**: plenty of repos merge into `develop`, `next`, or a release line while `defaultBranchRef` still says `main`. First hit wins:
  1. the **`--base`** argument,
  2. the repo's agent config `baseBranch` (e.g. `.ai/agentic.config.json`),
  3. the `## Skill profile` key **`baseBranch`** in the root `CLAUDE.md` / `AGENTS.md`,
  4. what the PR template or CONTRIBUTING says ("Open PRs against `develop`"),
  5. the default branch from the `gh repo view` above.

  Same order `upstream-pr` uses, so the two skills cannot disagree about where a repo's work lands. Ignore a literal `"auto"` at tiers 2–3 — it means "detect", not a branch called `auto`. Phase 0 resolves it once into `BASE_REF`; every later phase reads that variable rather than re-deriving a base of its own, and the report states which tier the value came from whenever it was not the default branch.
- **PR reviewer bot** — the `## Skill profile` key **`reviewer`** (singular), which must be the bot's **login** (`copilot-pull-request-reviewer`, the default) and not an alias like `@copilot`. One value covers requesting and recognising: `gh pr edit` accepts a login, and `.author.login` is what a review carries.
- **Human reviewers** — the `## Skill profile` key **`reviewers`** (plural), a distinct knob: who to fall back to when no bot review arrives (Phase 5). Unset, Phase 5 derives a candidate from recent merged PRs.
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

Resolve the PR base once, here, and export it — Phases 1, 2b and 4 all read it, and a base re-derived per phase is how a run ends up checking one range and publishing another:

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
CONFIG_BASE=$(jq -r '.baseBranch // empty' .ai/agentic.config.json 2>/dev/null | grep -v '^auto$')
# --base → agent config → profile → PR template/CONTRIBUTING (read, not scripted) → default
export BASE_REF="${ARG_BASE:-${CONFIG_BASE:-${PROFILE_BASE_BRANCH:-$DEFAULT}}}"
git rev-parse --verify "$BASE_REF" >/dev/null || git fetch origin "$BASE_REF"
echo "$BASE_REF" > .context/deliver/base
```

**A `--base` that doesn't resolve is a stop, not a fallback.** Silently dropping back to the default branch would open a PR whose diff replays its parent's commits — reviewable-looking and wrong. If the branch exists on neither the local repo nor the remote, say so and stop.

Refuse to run on the default branch, and refuse when `BASE_REF` is the branch you're on — a PR cannot target itself. If the working tree has uncommitted changes, surface them and ask the user before continuing — don't silently `git add -A`.

### 1. Scope detection

Look at `git diff "$BASE_REF"...HEAD --name-only` and bucket the touched files by package/workspace (top-level dir, monorepo workspace, or whatever the repo's structure is). Only run the checks for packages that actually changed — don't run one package's tooling for a branch that didn't touch it.

On a stacked run that range is deliberately narrow: the parent's files were already checked on the parent's PR. Don't widen it back to the default branch to be safe — that re-runs the parent's whole check surface on every child in the stack, which is the cost stacking exists to avoid.

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
git diff "$BASE_REF"...HEAD | grep -inE "$TERMS"
git log "$BASE_REF"..HEAD --format='%B' | grep -inE "$TERMS"
```

Grep is the floor — also read the prose the branch adds (specs, READMEs, comments). On a hit before pushing: rewrite (amend/rebase is fine, nothing is published yet). On a hit in something already pushed or public: **stop and tell the user** — never force-push to hide it, and never decide alone whether to rewrite published history.

### 3. Commit & push

Commit any work made during local checks under the same authorship as the branch's existing commits. Use Conventional Commits.

If the branch isn't pushed yet, push with `-u`. If it is, just push.

### 4. PR open or update

```bash
gh pr view --json number,url,reviewDecision,reviews,headRefOid 2>/dev/null
```

- No PR → `gh pr create --base "$BASE_REF"`. Title in Conventional Commits style stating the plain-language outcome. Write the body top-down per the **pr-polish** skill's structure: context/task line → the problem (observable impact, no code identifiers) → the fix (root cause + what the PR does) → technical details → verification → follow-ups.
- PR exists → the push updated the code, but check the title/description still tell the truth: if the work drifted since they were written (rebase, review rework, scope change, a referenced PR merged), run the **pr-polish** skill before requesting review — a stale description misleads the reviewer.

**An existing PR's base is not yours to change.** If its `baseRefName` differs from `BASE_REF` — a stack re-run after the parent landed and the forge retargeted the child, or a `--base` that disagrees with what is on record — report the mismatch and continue against the base the PR already has. Retargeting silently changes what every approval and every review comment on that PR applied to; only a human may decide that.

Save the PR number to `.context/deliver/pr-number`.

### 4b. Tracker — the work is now up for review

Skip entirely if the repo documents no tracker vocabulary (see Project specifics).

Resolve the task from the PR body's task line — the repo's own convention (`Closes X` / `Part of X` / `Relates to X`). Then, in one fetch of that task:

- **Assigned to someone other than the user you're working for → touch nothing.** Report it in Phase 9. You don't know what that person is doing with it.
- Still in a *not started* state → move it to *in progress*, then to *in review*. A pushed branch with a PR is unambiguously both; there's no point recording only the later one.
- Already in *in review* or a terminal state → leave it.

Move the task named by `Closes`. A `Part of` / `Relates to` task belongs to work wider than this PR — leave those alone at every phase.

### 5. Request reviewer

Assign both up front — an unset variable interpolates to `""`, which matches no review and fails exactly the silent-empty way this phase exists to prevent:

```bash
SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
REVIEWER=${PROFILE_REVIEWER:-copilot-pull-request-reviewer}   # requested AND matched
```

`PROFILE_REVIEWER` is the `## Skill profile` **`reviewer`** key, unset when the repo documents none. One value serves both roles because `gh pr edit --add-reviewer` accepts a bot's **login**, not only its alias.

**Set it to the login, never an alias.** `@copilot` is accepted by `gh pr edit` and is what GitHub's own docs show — but reviews are authored by `copilot-pull-request-reviewer`, and `.author.login` never carries a leading `@`. A profile saying `reviewer: @somebot` would request correctly and then match nothing, timing out on a review that had already arrived. If a bot's alias and login differ and you must request by alias, the two roles genuinely need two values — say so in the profile rather than letting one silently half-work.

(Not to be confused with **`reviewers`**, plural, which is the human fallback list below.)

**Why the login and not the alias:** Copilot answers to a different name in each API, and only one of them is what a review is authored by. Measured on `gh` 2.95.0 against a repo where the bot works:

| Name | `gh pr edit --add-reviewer` | REST `POST .../requested_reviewers` | authors reviews as |
|---|---|---|---|
| `@copilot` | ✅ lands (documented alias) | — | — |
| `copilot-pull-request-reviewer` | ✅ lands | ❌ `422 … not a collaborator` | ✅ |
| `Copilot` | ❌ `Could not resolve user with login` | ✅ | — |

`copilot-pull-request-reviewer` is the only row that both lands a request *and* matches a review, which is why one variable suffices. The REST **reviewers** endpoint is not used at all, so its `Copilot`-only spelling never comes up. (REST is still used later in this phase for review comments and thread replies.)

**Record a baseline first.** On a re-request the bot's previous review is already on the PR, so without this Phase 6's first poll returns instantly with the *old* review and Phase 7 addresses feedback written against an earlier HEAD:

```bash
export REVIEWER
export PRIOR=$(gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login == env.REVIEWER)] | sort_by(.submittedAt) | last | .submittedAt // ""')
```

"A review exists" and "a review of this HEAD exists" are different questions, and only the second one may gate a merge.

**Read the login from `env`, in a single-quoted filter — never interpolate the shell variable into the `--jq` string.** A jq filter carrying `\"$REVIEWER\"` has to survive two levels of quoting, and it is re-quoted every time the query is pasted into a loop, a `watch`, or a background job. Get it wrong and the filter matches nothing, forever, in silence — indistinguishable from a bot that never reviewed, which is how a poll ends up outliving a review that landed two minutes in. `env.REVIEWER` needs no escaping and cannot be re-broken downstream.

**Keep the `// ""`, and never drop it as redundant.** Everything jq reads from `env` is a *string*, so the empty-array case has to be normalised before it leaves this command: without the default, jq prints the missing timestamp as the literal `null`, `PRIOR` becomes the four-character string `"null"`, and Phase 6 compares timestamps against it lexicographically — where `"2026-…" > "null"` is **false**, because `2` sorts below `n`. The first review on a fresh PR would then never match, silently, which is the failure this whole pattern exists to remove. `""` sorts below every timestamp and is the only value that behaves.

**Request, or re-request, with the same command.** `gh pr edit --add-reviewer` both adds a reviewer and re-requests one who has already reviewed, and a re-request is what triggers a fresh review against the new HEAD:

```bash
gh pr edit <N> --add-reviewer "$REVIEWER"
```

**Do not verify by reading `reviewRequests` back — neither API can answer the question.** REST `requested_reviewers` returns only `{users, teams}` and omits bot reviewers entirely; the GraphQL form (`gh pr view <N> --json reviewRequests`) does see them, but a landed request **disappears from it the instant the reviewer submits**. Copilot often reviews within a minute or two, so the faster it works, the more certainly a read-back shows nothing.

The success signal is a review arriving, not a request being visible — and Phase 6 is already polling for exactly that.

**A failed request is not a missing review.** Many repos have Copilot reviewing automatically on open, with no request from anyone. So report the failure, keep polling, and only when Phase 6 times out with no bot review fall back to humans:

Use `reviewers` from the `## Skill profile` when the repo sets it. Otherwise derive a candidate — and **then actually request them**, which is the step whose absence started this whole phase:

```bash
AUTHOR=$(gh pr view <N> --json author --jq .author.login)
HUMAN=$(gh pr list --state merged --limit 20 --json reviews \
  --jq "[.[].reviews[].author.login] | map(select(. != \"$AUTHOR\" and . != \"$REVIEWER\")) | group_by(.) | max_by(length)[0] // empty")

if [ -n "$HUMAN" ]; then
  gh pr edit <N> --add-reviewer "$HUMAN"
else
  : # no candidate — report it and ask the user who should review; do not guess
fi
```

`// empty` rather than a bare `max_by(length)[0]`: on an empty candidate list that expression returns `null` and exits 0, so an unguarded run would request a reviewer literally named `null`. A young repo with no merged PRs, or one whose only reviewers so far are the author and the bot, hits this — and the failure would be silent, in the same shape as the bug this phase exists to prevent.

Excluding the author is not cosmetic either: whoever runs this skill is usually the PR's author, and requesting the author returns `422 Review cannot be requested from pull request author`. Never treat "no bot review" as "no review needed".

### 6. Wait for the review

The bot typically takes 1–5 minutes. Poll, don't busy-wait:

```bash
export HEAD_OID=$(gh pr view <N> --json headRefOid --jq .headRefOid)
gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login == env.REVIEWER and .submittedAt > env.PRIOR and .commit.oid == env.HEAD_OID)] | sort_by(.submittedAt) | last'
```

Poll every ~60s for up to ~10 minutes. All three values come from `env` — `REVIEWER` and `PRIOR` exported in Phase 5, `HEAD_OID` just above — so the filter stays single-quoted: this query gets copied into a loop or a background watcher, which is exactly where an interpolated, escaped filter breaks and then fails silently.

**`submittedAt` alone does not answer "reviewed at this HEAD".** A review requested before a push lands *after* it — newer than `$PRIOR`, and still written against superseded code. Each review carries the commit it read (`.commit.oid`), so gate on that; a "no new comments" verdict on the commit your fix replaced says nothing about the fix. Read such a review anyway — its findings may well still apply — but don't let it satisfy the gate, and re-request against the new HEAD.

A poll loop must also distinguish jq's `null` (no match yet) from an **empty** result (a failed call, a broken filter): `[ "$R" != "null" ]` alone treats the empty string as a hit and exits the loop on the first hiccup, reporting no review while the bot is still working. Test for both.

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

**Confirm a "failed" entry against the head commit before believing it.** `gh pr checks` renders a job's `skipped` conclusion in the same bucket as a failure, so a workflow's `if: failure()` notification job — which is skipped on every successful run, by design — prints as `[FAIL]` on a perfectly green PR:

```bash
gh api --paginate \
  "repos/$SLUG/commits/$(gh pr view <N> --json headRefOid --jq .headRefOid)/check-runs?per_page=100" \
  --jq '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion)"'
```

Read that list both ways: a `skipped` alert job is not a failure, and a *required* gate that was filtered out of this run (a path filter, a `paths-ignore`) is not a pass — it's a green banner over a job that never ran. Neither is a reason to stop; both change what you do next.

If a check genuinely fails, **fix it and keep going** — don't stop and hand back to the user. Workflow:

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

In no-merge mode this decision is already made: the condition is false by definition — surface the PR's state as ready-for-review and stop (Phase 8b never runs).

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

  A hit means the base is itself an open PR waiting to land. Merging into it folds this work into that PR, enlarging a diff someone is mid-review on, and ships nothing. Stop and tell the user to land the parent first. Never retarget the base yourself — that silently changes what the approvals on record applied to.

  On a `--base` run this hit is the designed outcome, not an accident: a stack merges bottom-up, and each child's base is retargeted by the forge as its parent lands. Report it as `blocked-on-parent-PR` with the parent's number — that is a healthy stack waiting its turn, not a failure. AND
- ≤ ~100 lines changed since `start-sha`, AND
- No new files outside what was already touched at `start-sha`, AND
- All CI checks on the PR are green (`gh pr checks <N>` — wait for them, and resolve any `[FAIL]` against the head commit's check-runs per Phase 7b before calling it red), AND
- The review is `APPROVED` or `COMMENTED` with no remaining unresolved actionable threads.

If the condition holds → merge:

```bash
gh pr merge <N> --squash --delete-branch        # add --admin only if ownerCanSelfMerge
```

Use `--admin` **only** when the `## Skill profile` says `ownerCanSelfMerge: true` (the user owns the repo and doesn't need peer approval). Otherwise merge normally and let required reviews apply; if a required review blocks, surface that and stop.

**A non-zero exit is not proof the merge failed — check the PR, never retry blind.** `--delete-branch` also deletes the *local* branch, and that step fails when another worktree has the base checked out (`fatal: 'main' is already used by worktree at …`), long after the merge itself succeeded server-side:

```bash
gh pr view <N> --json state,mergedAt,mergeCommit
```

`MERGED` means done — finish Phase 8b and report it. Re-running `gh pr merge` on a merged PR instead pushes the deleted branch back and can leave a stray merge commit on the base, which is published history you must not clean up alone. The same read settles a merge that times out or drops its connection.

If the condition doesn't hold (substantial new code, failing checks, unresolved threads, or no review yet) → don't merge. Surface the state to the user and stop.

### 8b. Tracker — close the task

Only once the merge has actually succeeded, and only for the task named by `Closes`: move it to the *done* state. Same guard as 4b — never a task assigned to someone else.

If the PR only says `Part of` / `Relates to`, or the merge didn't happen, leave the task where 4b put it and say so in Phase 9. Never set an *abandoned* / *cancelled* / *won't do* state from this skill; that's a human judgement, not a consequence of a merge.

Acceptance criteria the merge can't prove (something observable only in a deployed environment) are yours to check *before* moving the task, not to assume. If you can't check them, leave the task in review and say what's outstanding.

### 9. Report

Final message to the user must include: PR URL, the base it targets whenever that isn't the default branch (name the parent PR it stacks on), merge status (merged / awaiting-CI / awaiting-review / blocked-on-parent-PR / blocked), whether the reviewer bot was actually reachable, the tracker task and the state you left it in (or why you didn't move it), and any decisions you punted (e.g. "left thread #X unresolved because the suggestion conflicts with the documented convention — please weigh in").

## Hard rules

1. **Never `--no-verify`, never `--no-gpg-sign`.** If a pre-commit hook fails, fix the root cause.
2. **Never push to the default branch.** This skill operates on a feature branch only.
3. **Never run a full test suite locally** — not full e2e, not full unit/integration. Targeted runs only; CI owns full suites. A pre-push gate that takes >2 min defeats the point of front-loading.
4. **Never merge without CI green.** Even with `--admin`, wait for `gh pr checks` to be green. Bypassing required reviews is one thing; bypassing failing CI is not.
5. **Don't expand scope under cover of review feedback.** If a suggestion is a refactor beyond the PR's purpose, push back in the thread instead of doing it.
6. **Never publish a client's non-public details** into a public repo or one owned by anyone but that client — not in the diff, the commit messages, the PR body, or a review reply. See the Phase 2b gate. It's the one failure here a later commit can't undo.
7. **Follow the repo's dev-server/port convention** when you start a service for a local test. Don't auto-launch a whole-stack dev script.
8. **Never move a tracker task that belongs to someone else**, and never move one to *done* on anything but a successful merge of a PR that says it closes it. A wrong status is worse than a stale one — it's read as a fact by people who weren't in this session.
