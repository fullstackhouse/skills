---
name: deliver
description: Deliver the work on the current branch — run all relevant local checks (lint/typecheck/tests), get the change reviewed and fixed locally through the review-loop skill before anything is pushed, open or update a PR, work the CI loop, then auto-merge if changes since invocation are minimal. Supports --no-merge to stop at ready-for-review instead, --base to target a branch other than the repo default (stacked PRs), and --bot-review to additionally put a PR bot's review on the record. CI is slow and a bot reviewer is slower; do not lean on either as a first pass.
---

# deliver

You are running the **deliver** skill. Goal: take whatever is on the current branch and get it merged with as few CI round-trips as possible.

CI is slow and every avoidable push is a real cost — front-load everything locally before pushing. That includes the **review**: Phase 3 hands the change to the **review-loop** skill, which reviews and fixes it with fresh-context reviewers *before* the first push, so the diff that reaches GitHub is already hardened. A reviewer on the far side of the network — a bot, a person — is something this skill can put on the record (Phase 6b) but never waits on as a first pass.

**No-merge mode:** when invoked with `--no-merge` (how the **kickoff** skill calls this), everything through Phase 6b runs unchanged — checks, confidentiality gate, review, PR, CI loop, the tracker's move to *in review* — but Phase 7's merge condition is forced false: leave the PR ready for review, skip Phase 7b, and report. The merge decision stays with the human.

**Stacked mode:** when invoked with `--base <branch>`, that branch — not the repo's default branch — is what this PR targets and what every diff in this run is computed against. Its purpose is stacking: the parent branch is usually itself an open PR, so this PR's diff shows only the increment on top of it instead of replaying the parent's changes. Phase 0 resolves it once into `BASE_REF`; nothing downstream re-derives it. Phase 7's stacked-base check then does exactly what it always did — a base that is an open PR blocks auto-merge — which under `--base` is the expected outcome, not a surprise: land the parent first.

## Arguments

- **`--no-merge`** — stop at ready-for-review; Phase 7 assesses but never merges. How **kickoff** calls this.
- **`--base <branch>`** — target `<branch>` instead of the repo default, and compute every diff in the run against it. For stacking.
- **`--bot-review` / `--no-bot-review`** — force Phase 6b's on-record bot review on or off, overriding the `reviewer` profile knob for this run.

## Project specifics — read these first

This skill is repo-agnostic. The concrete commands, reviewer, and merge policy come from the repository you're running in. Before Phase 1, gather:

- **Check commands per package** — how to lint / typecheck / test / run codegen for each workspace. Derive from the repo's `AGENTS.md` / `CLAUDE.md`, per-package docs, and `package.json` (`scripts`) / `Makefile` / `justfile`. If the repo has a **`## Skill profile`** section in its root `AGENTS.md`, use that — it's the curated source.
- **Repo identity** — one call covers slug, default branch, and the audience the Phase 2b gate keys on:
  ```bash
  gh repo view --json nameWithOwner,defaultBranchRef,visibility,owner
  ```
- **PR base** — where this PR is meant to land. **The GitHub default branch is the last resort, not the first**: plenty of repos merge into `develop`, `next`, or a release line while `defaultBranchRef` still says `main`. First hit wins:
  1. the **`--base`** argument,
  2. the repo's agent config `baseBranch` (e.g. `.ai/agentic.config.json`),
  3. the `## Skill profile` key **`baseBranch`** in the root `AGENTS.md` / `CLAUDE.md`,
  4. what the PR template or CONTRIBUTING says ("Open PRs against `develop`"),
  5. the default branch from the `gh repo view` above.

  Same order `upstream-pr` uses, so the two skills cannot disagree about where a repo's work lands. Ignore a literal `"auto"` at tiers 2–3 — it means "detect", not a branch called `auto`. Phase 0 resolves it once into `BASE_REF`; every later phase reads that variable rather than re-deriving a base of its own, and the report states which tier the value came from whenever it was not the default branch.
- **Review on the record** — the `## Skill profile` key **`reviewer`** (singular): a PR review bot's **login** (`copilot-pull-request-reviewer` is the usual one), set only by repos that want a bot review attached to the PR. Its presence is what switches Phase 6b on; `--bot-review` / `--no-bot-review` override it for one run. It is not the reviewer that hardens the change — that is Phase 3, and it runs whether or not this key exists.
- **Human reviewers** — the `## Skill profile` key **`reviewers`** (plural), a distinct knob: who to request when the PR cannot merge without an approving review (Phase 7). Unset, a candidate is derived from recent merged PRs.
- **ownerCanSelfMerge** — from the `## Skill profile`; gates whether `gh pr merge --admin` is acceptable (see Phase 7). Default: false (don't bypass required reviews).
- **Dev-server / port convention** — if the repo documents one (e.g. a worktree port rule), follow it whenever you need to start a service for a local test.
- **Tracker + its status vocabulary** — from the `## Skill profile` (`tracker`). If the repo documents which states mean *in progress*, *in review* and *done*, this skill moves the task along with the PR (Phases 5b and 7b). If it documents a tracker but no vocabulary, don't guess at state names — report the task's current state in Phase 8 instead.

If a needed value isn't documented and you can't infer it, ask the user rather than guessing.

## Phases

### 0. Anchor

Before doing anything, record the starting SHA so the "not much changed since invocation" check at the end is meaningful:

```bash
mkdir -p .context/deliver
git rev-parse HEAD > .context/deliver/start-sha
git rev-parse --abbrev-ref HEAD > .context/deliver/branch
```

Resolve the PR base once, here, and export it — Phases 1, 2b and 5 all read it, and a base re-derived per phase is how a run ends up checking one range and publishing another:

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

Phase 3's `--gate scoped` resolves to this same set, from this same repo config — nothing is handed over, both derive it independently. So getting the repo's documented commands right is what keeps the loop from running a check the repo doesn't have, or the full suite hard rule 3 forbids.

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

The same gate applies to anything Phase 6b posts — see that phase.

### 3. Review — before anything is pushed

**This is the review.** Not a warm-up for one: the findings that cost the most rounds live in what the hunks touch — the consumer of a changed function, the environment a config key lands in, the script whose output another script parses — and all of that is readable locally, now, for the price of some tokens instead of a ten-minute wait and a CI run per lap.

Invoke the **review-loop** skill, passing the base Phase 0 resolved:

```
review-loop --source local --base "$BASE_REF" --quiet-rounds 1 --max-rounds 3 --gate scoped
```

`--base` is not optional. Phase 0 promised nothing downstream re-derives a base; that skill resolves its own from repo config when nobody passes one, and on a `--base` run it would then review the parent's entire diff instead of this branch's increment — burning the whole budget on code the parent's own PR already reviewed.

**If `review-loop` is not installed** — this repo supports symlinking a single skill — don't skip the review and don't improvise a rubric. Run one round of it inline: a fresh reviewer subagent on `git diff "$BASE_REF"...HEAD`, told nothing of the branch's intent, asked for whole files and callers and a severity, a concrete failure scenario and a fix per finding; verify each finding before acting on it; fix what holds; hand up the judgement calls and anything outside the diff. Then carry the same three facts forward by hand — what HEAD was reviewed, whether anything actionable is still open, and what was handed up — because Phase 7 needs them and there will be no `state.json` to read. Say in the report that the review was the inline fallback, not the loop.

Those arguments are deliberate and differ from that skill's standalone defaults:

- **`--quiet-rounds 1`** — one round that raises nothing new is enough here, because this is a front-load rather than a hardening run and the change still has CI and a human ahead of it. Pass `--quiet-rounds 2` when the branch warrants it (a migration, an auth path, a public contract); it roughly doubles the cost and is worth it there.
- **`--max-rounds 3`** — past three, the answer is a human, not another lap.
- **`--gate scoped`** — the checks from Phase 2, for the packages this diff touches. Not the repo's full gate: a full suite pre-push is slower than the CI it exists to front-load (hard rule 3), and CI owns the full one.

Both artifacts matter: `state.json` (the machine-readable result) and `report.md` (the curve, the rubric, the fixed/refuted counts) — both under the run directory the loop names. Phase 5's PR body needs the second; Phase 7 needs the first:

| Field | What this skill does with it |
|---|---|
| `reviewed_oid` | Phase 7's merge condition — has the review seen what is on the branch now? |
| `sources.local.exit` | `converged` is the only value that can satisfy Phase 7. `budget-exhausted` reports `blocked`. |
| `open[]` | blockers and majors still open block the merge; handed-up decisions go in the PR body and the Phase 8 report. |

**The loop's handed-up findings are not yours to decide.** They are the judgement calls it refused to make alone — a design disagreement, a scope question, a deprecation policy. Carry them into the PR body (Phase 5) and the report; don't quietly implement one, and don't quietly drop it.

**Findings outside the diff** come back handed up too. Report them; don't fix them here. Fixing them turns a reviewable branch into a tour of the repo.

### 4. Commit & push

**Re-run the Phase 2b scan first, if that gate fired.** It ran before Phase 3, and Phase 3 has since committed up to three rounds of code it wrote itself — a comment explaining where a pattern came from, a fixture named after a client system. Nothing is published yet, so a rewrite here is still free; after the push it is the one failure hard rule 6 says a later commit can't undo.

```bash
git diff "$BASE_REF"...HEAD | grep -inE "$TERMS"
git log "$BASE_REF"..HEAD --format='%B' | grep -inE "$TERMS"
```

Commit any work made during the checks and the review loop under the same authorship as the branch's existing commits. Use Conventional Commits.

The loop already committed its own rounds, one per round — leave those as they are rather than squashing them into a single "review fixes" commit; the per-round shape is what makes the curve legible in `git log`.

Keep the loop's run directory out of the commits. If the repo tracks `paths.runs`, exclude it explicitly; never `git add -A`.

If the branch isn't pushed yet, push with `-u`. If it is, just push.

### 5. PR open or update

```bash
gh pr view --json number,url,reviewDecision,reviews,headRefOid 2>/dev/null
```

- No PR → `gh pr create --base "$BASE_REF"`. Title in Conventional Commits style stating the plain-language outcome. Write the body top-down per the **pr-polish** skill's structure: context/task line → the problem (observable impact, no code identifiers) → the fix (root cause + what the PR does) → technical details → verification → follow-ups.
- PR exists → the push updated the code, but check the title/description still tell the truth: if the work drifted since they were written (rebase, review rework, scope change, a referenced PR merged), run the **pr-polish** skill — a stale description misleads whoever reads it next.

**The body carries the review evidence.** Moving the review off the PR removes the only public record that one happened, and a human arriving at this PR has no way to tell a reviewed branch from an unreviewed one. Under **Verification**, state it plainly: the rubric the loop used, how many rounds it ran, how many findings it fixed and refuted, and what gate passed. Then, if `open[]` is non-empty, an **Open questions** list — one line per handed-up finding, naming the decision rather than describing a problem. That list is the most useful thing in the body for the person who reviews next.

Everything in that section is published text and passes the Phase 2b gate first: quote no client identifier into a public PR body just because a reviewer's finding mentioned one.

Save the PR number to `.context/deliver/pr-number`.

**An existing PR's base is not yours to change.** If its `baseRefName` differs from `BASE_REF` — a stack re-run after the parent landed and the forge retargeted the child, or a `--base` that disagrees with what is on record — report the mismatch and continue against the base the PR already has. Retargeting silently changes what every approval and every review comment on that PR applied to; only a human may decide that.

### 5b. Tracker — the work is now up for review

Skip entirely if the repo documents no tracker vocabulary (see Project specifics).

Resolve the task from the PR body's task line — the repo's own convention (`Closes X` / `Part of X` / `Relates to X`). Then, in one fetch of that task:

- **Assigned to someone other than the user you're working for → touch nothing.** Report it in Phase 8. You don't know what that person is doing with it.
- Still in a *not started* state → move it to *in progress*, then to *in review*. A pushed branch with a PR is unambiguously both; there's no point recording only the later one.
- Already in *in review* or a terminal state → leave it.

Move the task named by `Closes`. A `Part of` / `Relates to` task belongs to work wider than this PR — leave those alone at every phase.

### 6. Handle CI failures

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

**A CI fix that changes shipped behaviour goes back through Phase 3.** Green checks are not a review: such a fix carries code no reviewer has read, on a `reviewed_oid` for the old HEAD, and Phase 7 will refuse it. Re-invoke `review-loop` — it resumes its ledger rather than starting over, so the second pass is cheap and dedupes against everything already raised. A test-only, snapshot or workflow fix that changes no shipped behaviour keeps the direct path.

Hard stop conditions (escalate to user, don't keep grinding):
- Same failure recurs after 3 fix attempts on the same job — your hypothesis is wrong; stop and ask.
- The fix would require changes outside this branch's scope (e.g. updating a shared package, infra credentials).
- A test failure points at a real bug in code outside the diff (this branch surfaced it but didn't cause it).

Do not merge while any required check is failing or pending. `--admin` bypasses required reviews, not failing CI (see Hard rules).

### 6b. Reviews on the PR

Phase 3 hardened the change. This phase is about the PR's own review surface — what is already on it, and whether this repo wants a bot's review added to it.

**Always: answer what is already there.**

```bash
gh pr view <N> --json reviews --jq '.reviews[] | "\(.author.login)\t\(.state)\t\(.commit.oid)"'
gh api "repos/$SLUG/pulls/<N>/comments" --paginate
```

Someone who took the time to comment gets an answer, and an unresolved actionable thread blocks the merge regardless of who left it or whether anyone requested them. Run each finding through the same discipline Phase 3's loop uses — verify it before touching code, fix what holds, reply on the thread, resolve it; reply with the reason and resolve when it doesn't hold; leave it open and hand it up when it's a judgement call. This runs on every invocation, including the ones where the rest of this phase is skipped.

**Conditionally: put a bot's review on the record.** Run this when the `## Skill profile` sets **`reviewer`**, or when the run carries `--bot-review`. Skip it when the profile sets nothing, or the run carries `--no-bot-review`. Skipping is the common case and is not a gap: Phase 3's review is recorded in the PR body, and Phase 7 requires it to have covered HEAD.

```
review-loop --source bot --pr <N> --base "$BASE_REF" --gate scoped
```

`--gate scoped` for hard rule 3's reason — that skill's default is the repo's *whole* check set, which is the full suite CI is already running on this PR.

It requests the bot, polls for a review of *this* HEAD, reads the inline comments **and** the ones the review body folds away, verifies each finding before spending a code change, fixes, replies, resolves, and caps itself at 3 rounds (5 while blocking findings keep arriving). It updates the same `state.json`, so Phase 7 reads one file whichever sources ran.

Two things belong to this skill, not that one:

- **The confidentiality gate applies to every reply posted here** — by the loop or by you. A thread reply is published text on a possibly-public PR; the Phase 2b rules hold there exactly as they hold for the diff.
- **A bot that never answers is not a blocker on its own.** `sources.bot.exit: awaiting-review` means the *record* is missing, not that the change is unreviewed — Phase 3's review still stands, and Phase 7's conditions decide what that's worth.

### 7. Auto-merge decision

In no-merge mode the *merge* is already decided against — the condition is false by definition, and Phase 7b never runs. **The assessment still happens.** `--no-merge` withholds the merge, not the truth about the PR: evaluate the conditions below anyway and report what they say — `ready-for-review` only when they all hold bar the merge itself, otherwise `awaiting-CI` or `blocked`, naming what blocks. Reporting ready-for-review unconditionally is how an exhausted review budget with open findings, or a red pipeline, reaches a human as "done".

If not much has changed since the skill started, just merge. "Not much" means the work since Phase 0's `start-sha` is mostly review fixups, not new functionality.

```bash
START=$(cat .context/deliver/start-sha)
git diff --shortstat "$START"...HEAD     # lines changed since invocation
git log --oneline "$START"..HEAD          # commits since invocation
```

Merge condition (ALL must hold):

- **The review covers what is on the branch now.** `sources.local.exit` is `converged` — that is the review this skill always runs, so it is the one that must have finished, not merely "some source did". And `reviewed_oid` equals HEAD, or every commit since it is one this run made that `review-loop`'s equivalence rule covers: a fix made in response to a finding, or a CI fix that changes no shipped behaviour (a lint autofix, a snapshot update, a workflow tweak). Inside a run you know which commits are which; a re-invocation does not, so commits after `reviewed_oid` that this run didn't make are unreviewed code and report `blocked`.

  `budget-exhausted` on any source reports `blocked` — the cap ends the looping, it never lowers the merge bar. `awaiting-review` on `bot` or `human` does **not** block on its own (Phase 6b says why); it is reported, and the unresolved-threads condition below is what actually holds the line. AND
- **No blocker or major sits open in `state.json`'s `open[]`**, and no actionable review thread on the PR is unresolved — whoever left it. AND
- **Nothing is stacked on top of this PR's base** — that is the precise question, and "the base is the default branch" only approximates it: plenty of repos ship through a release or integration branch, and such a repo could never auto-merge under that rule.

  ```bash
  BASE=$(gh pr view <N> --json baseRefName --jq .baseRefName)
  DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
  # A PR onto the default branch cannot be stacked — skip the query entirely.
  [ "$BASE" = "$DEFAULT" ] || gh pr list --state open --head "$BASE" --json number,url
  ```

  The short-circuit is load-bearing, not an optimisation: `--head` matches on branch *name* and includes cross-repository PRs, so one open fork PR whose head branch is called `main` would otherwise mark **every** PR in the repo as stacked and disable auto-merge outright.

  A hit means the base is itself an open PR waiting to land. Merging into it folds this work into that PR, enlarging a diff someone is mid-review on, and ships nothing. Stop and tell the user to land the parent first. Never retarget the base yourself. On a `--base` run this hit is the designed outcome, not an accident: a stack merges bottom-up. Report it as `blocked-on-parent-PR` with the parent's number — a healthy stack waiting its turn, not a failure. AND
- ≤ ~100 lines changed since `start-sha`, AND
- No new files outside what was already touched at `start-sha`, AND
- All CI checks on the PR are green (`gh pr checks <N>` — wait for them, and resolve any `[FAIL]` against the head commit's check-runs per Phase 6 before calling it red), AND
- **The remote carries what you reviewed and fixed:**

  ```bash
  [ "$(git rev-parse HEAD)" = "$(gh pr view <N> --json headRefOid --jq .headRefOid)" ]
  ```

  A squash merge ships the branch GitHub holds, and `--delete-branch` then deletes the local one. An unpushed fix is not merged, it is destroyed — and because CI and the reviewer both read the remote, every other condition above would have gone green on the code *without* it. Push, let CI settle, then re-evaluate.

**A forge that requires an approving review is a stop, not a condition to work around.**

```bash
gh pr view <N> --json mergeStateStatus,reviewDecision
```

`reviewDecision: REVIEW_REQUIRED` means branch protection wants a human's approval, and nothing this skill does locally can produce one. Request the reviewers — `review-loop --source human --pr <N> --gate none`, which uses the `reviewers` profile knob or derives a candidate — and report `awaiting-review`. `--gate none`: nothing is being fixed there that CI has not already checked. Don't wait on them: a human review arrives on human time. This is the only place this skill requests a person.

If the condition holds → merge:

```bash
gh pr merge <N> --squash --delete-branch        # add --admin only if ownerCanSelfMerge
```

Use `--admin` **only** when the `## Skill profile` says `ownerCanSelfMerge: true` (the user owns the repo and doesn't need peer approval). Otherwise merge normally and let required reviews apply.

**A non-zero exit is not proof the merge failed — check the PR, never retry blind.** `--delete-branch` also deletes the *local* branch, and that step fails when another worktree has the base checked out (`fatal: 'main' is already used by worktree at …`), long after the merge itself succeeded server-side:

```bash
gh pr view <N> --json state,mergedAt,mergeCommit
```

`MERGED` means done — finish Phase 7b and report it. Re-running `gh pr merge` on a merged PR instead pushes the deleted branch back and can leave a stray merge commit on the base, which is published history you must not clean up alone. The same read settles a merge that times out or drops its connection.

If the condition doesn't hold → don't merge. Surface the state to the user and stop.

### 7b. Tracker — close the task

Only once the merge has actually succeeded, and only for the task named by `Closes`: move it to the *done* state. Same guard as 5b — never a task assigned to someone else.

If the PR only says `Part of` / `Relates to`, or the merge didn't happen, leave the task where 5b put it and say so in Phase 8. Never set an *abandoned* / *cancelled* / *won't do* state from this skill; that's a human judgement, not a consequence of a merge.

Acceptance criteria the merge can't prove (something observable only in a deployed environment) are yours to check *before* moving the task, not to assume. If you can't check them, leave the task in review and say what's outstanding.

### 8. Report

Final message to the user must include: PR URL; the base it targets whenever that isn't the default branch (name the parent PR it stacks on); merge status (merged / awaiting-CI / awaiting-review / blocked-on-parent-PR / blocked); **the review loop's result** — rubric, rounds, fixed, refuted, and its `exit`; what it handed up, in full, since those are decisions waiting on the user; whether Phase 6b ran and what came back; the tracker task and the state you left it in (or why you didn't move it); and any thread you left unresolved, with why.

The handed-up findings are the part a reader most needs and most easily loses. List them as decisions, not as a summary of a summary.

## Hard rules

1. **Never `--no-verify`, never `--no-gpg-sign`.** If a pre-commit hook fails, fix the root cause.
2. **Never push to the default branch.** This skill operates on a feature branch only.
3. **Never run a full test suite locally** — not full e2e, not full unit/integration. Targeted runs only; CI owns full suites. This is why Phase 3 passes `--gate scoped`.
4. **Never merge without CI green.** Even with `--admin`, wait for `gh pr checks` to be green. Bypassing required reviews is one thing; bypassing failing CI is not.
5. **Never merge on a review that didn't cover HEAD.** "A review happened" and "a review of this code happened" are different facts, and only the second may gate a merge. `reviewed_oid` is the one that counts.
6. **Never publish a client's non-public details** into a public repo or one owned by anyone but that client — not in the diff, the commit messages, the PR body, or a review reply. See the Phase 2b gate. It's the one failure here a later commit can't undo.
7. **Don't expand scope under cover of review feedback.** If a finding asks for a refactor beyond the PR's purpose, it comes back handed up — carry it to the user, don't build it.
8. **Never re-invoke `review-loop` to get a different answer.** Its budget belongs to the change, not to the invocation; it resumes its ledger for a reason. Past its cap the answer is a human, and the cap never relaxes Phase 7's conditions.
9. **Follow the repo's dev-server/port convention** when you start a service for a local test. Don't auto-launch a whole-stack dev script.
10. **Never move a tracker task that belongs to someone else**, and never move one to *done* on anything but a successful merge of a PR that says it closes it. A wrong status is worse than a stale one — it's read as a fact by people who weren't in this session.
