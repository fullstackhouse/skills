---
name: deliver
description: Deliver the work on the current branch — run all relevant local checks (lint/typecheck/tests) and one fresh-context local review to front-load what CI and the reviewer would catch, open or update a PR, request a reviewer (or re-review if one already exists), address the feedback, then auto-merge if changes since invocation are minimal. Supports --no-merge to stop at ready-for-review instead, and --base to target a branch other than the repo default (stacked PRs). CI is slow; do not lean on it as a first pass.
---

# deliver

You are running the **deliver** skill. Goal: take whatever is on the current branch and get it merged with as few CI round-trips as possible.

CI is slow and every avoidable push is a real cost — front-load all checks locally before pushing.

**No-merge mode:** when invoked with `--no-merge` (how the **kickoff** skill calls this), everything through Phase 7/7b/7c runs unchanged — checks, confidentiality gate, PR, reviewer, feedback and CI loops, the tracker's move to *in review* — but Phase 8's merge condition is forced false: leave the PR ready for review, skip Phase 8b, and report. The merge decision stays with the human.

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

`.context/deliver/round-<PR>.json` lives here too — the loop's state: the round count Phase 7c budgets and Phase 5 spends, plus what the last review found and which commit it read. Don't reset it on a re-invocation; read why in 7c.

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

### 2c. Local review round — before anything is pushed

A bot reviewer reads hunks. The findings that cost the most rounds live in what the hunks touch — the consumer of a changed function, the environment a config key lands in, the script whose output another script parses. Read that once, locally, before the first review is requested, so the reviewer sees a hardened diff and the loop starts where round 2 would have.

- The repo carries `.ai/agentic.config.json` and `om-code-review` → run **`om-review-loop --quiet-rounds 1`**: it reviews with fresh-context subagents, verifies before fixing, hands up what it must not decide.
- Otherwise → one fresh-context reviewer subagent on `git diff "$BASE_REF"...HEAD`, told nothing of the branch's intent: whole files, callers and consumers, and per finding a severity, a concrete failure scenario and a fix. Verify each finding before acting (Phase 7's first step), fix what holds, commit.

Findings outside the diff are handed up in Phase 9, never fixed here. This round spends nothing from the 7c budget — no review was requested — and it replaces nothing downstream: a review is still required (Phase 6).

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

**Spend a round here — or find you shouldn't.** This is the only place in the skill a review is ever asked for, so it is the only honest place to count one and the only place a cap can prevent anything. Read the loop state Phase 7c maintains:

```bash
PR=$(cat .context/deliver/pr-number)
STATE=".context/deliver/round-$PR.json"
[ -f "$STATE" ] || echo '{"rounds":0,"severity":"none","verdict":"none","reviewed_oid":""}' > "$STATE"
eval "$(jq -r '@sh "ROUNDS=\(.rounds) SEVERITY=\(.severity) VERDICT=\(.verdict) REVIEWED=\(.reviewed_oid)"' "$STATE")"
HEAD_OID=$(git rev-parse HEAD)
if [ "$SEVERITY" = "blocking" ]; then CAP=5; else CAP=3; fi   # 7c: nits never buy round 4
```

Three answers, in order:

1. **`VERDICT=clean` and `REVIEWED` = `HEAD_OID`** → the PR already carries a current, clean review. Don't request one: re-requesting would spend a round to re-confirm a result you already have, which the budget exists to prevent as much as it prevents grinding.
2. **`ROUNDS` ≥ `CAP`** → exhausted. Don't request, and don't let Phase 6 poll — a ten-minute wait for a review you've already decided not to act on is the exact cost being capped. Phase 8 then takes 7c's budget-exhausted path.
3. Otherwise this request **is** the next round. Record it *before* issuing it, so a crash mid-round can't hand out a free one — and clear the previous round's findings in the same write, since they describe a review of an older HEAD:

   ```bash
   jq --argjson n $((ROUNDS + 1)) '.rounds = $n | .severity = "none" | .verdict = "none"' \
      "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
   ```

   Leaving them would let a round that timed out — spent, but never reviewed — inherit the *previous* round's `blocking` and quietly buy rounds 4 and 5 on the strength of a finding two rounds old. Phase 6 writes them back the moment a review actually lands; until then the state honestly says "this round returned nothing yet".

**Only the request and Phase 6's poll are ever skipped here.** Every one of these three paths still runs **Phase 7b** before Phase 8 — the budget caps *review* requests and nothing else. A check can go red or pending between invocations, and in `--no-merge` mode Phase 8 never evaluates CI at all, so a path that skipped 7b would report a failing PR as ready for review with nothing downstream to catch it.

The first review counts as round 1. Counting re-requests instead would make "3 rounds" mean four reviews and report a clean first review as zero rounds spent.

Assign both up front — an unset variable interpolates to `""`, which matches no review and fails exactly the silent-empty way this phase exists to prevent:

```bash
SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
export REVIEWER=${PROFILE_REVIEWER:-copilot-pull-request-reviewer}   # requested AND matched
export AUTHOR=$(gh pr view <N> --json author --jq .author.login)     # excluded everywhere
```

`PROFILE_REVIEWER` is the `## Skill profile` **`reviewer`** key (not `reviewers`, the human fallback list below), unset when the repo documents none. **It must be the login, never an alias**: `copilot-pull-request-reviewer` is the only spelling that both lands a `gh pr edit --add-reviewer` request *and* matches `.author.login` on the review. `@copilot` requests fine and then matches nothing — a poll that outlives a review which landed two minutes in. (`Copilot` works only on the REST reviewers endpoint, which this skill does not use.) A bot whose alias and login genuinely differ needs two profile values; say so rather than let one half-work.

**Record a baseline first.** On a re-request the bot's previous review is already on the PR, so without this Phase 6's first poll returns instantly with the *old* review and Phase 7 addresses feedback written against an earlier HEAD:

```bash
export REVIEWER
export PRIOR=$(gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login == env.REVIEWER)] | sort_by(.submittedAt) | last | .submittedAt // ""')
```

"A review exists" and "a review of this HEAD exists" are different questions, and only the second one may gate a merge.

Two details in that filter are load-bearing. `env.REVIEWER` inside a single-quoted filter: an interpolated `\"$REVIEWER\"` breaks on the re-quoting a loop or background watcher applies, and then matches nothing, silently. And the `// ""`: without it an empty array prints the literal `null`, and `"2026-…" > "null"` is false, so the first review on a fresh PR never matches.

**Request, or re-request, with the same command.** `gh pr edit --add-reviewer` both adds a reviewer and re-requests one who has already reviewed, and a re-request is what triggers a fresh review against the new HEAD:

```bash
gh pr edit <N> --add-reviewer "$REVIEWER"
```

**Do not verify by reading `reviewRequests` back — neither API can answer the question.** REST `requested_reviewers` returns only `{users, teams}` and omits bot reviewers entirely; the GraphQL form (`gh pr view <N> --json reviewRequests`) does see them, but a landed request **disappears from it the instant the reviewer submits**. Copilot often reviews within a minute or two, so the faster it works, the more certainly a read-back shows nothing.

The success signal is a review arriving, not a request being visible — and Phase 6 is already polling for exactly that.

**A failed request is not a missing review.** Many repos have Copilot reviewing automatically on open, with no request from anyone. So report the failure, keep polling, and only when Phase 6 times out with no bot review fall back to humans:

Use `reviewers` from the `## Skill profile` when the repo sets it. Otherwise derive a candidate — and **then actually request them**, which is the step whose absence started this whole phase:

```bash
HUMAN=$(gh pr list --state merged --limit 20 --json reviews \
  --jq "[.[].reviews[].author.login] | map(select(. != \"$AUTHOR\" and . != \"$REVIEWER\")) | group_by(.) | max_by(length)[0] // empty")

if [ -n "$HUMAN" ]; then
  gh pr edit <N> --add-reviewer "$HUMAN"
else
  : # no candidate — report it and ask the user who should review; do not guess
fi
```

`// empty` guards the empty candidate list — a bare `max_by(length)[0]` prints `null`, exits 0, and the run requests a reviewer literally named `null`. Excluding the author is required too: requesting the PR author returns `422`. Never treat "no bot review" as "no review needed".

### 6. Wait for the review

The bot typically takes 1–5 minutes. Poll, don't busy-wait:

```bash
export HEAD_OID=$(gh pr view <N> --json headRefOid --jq .headRefOid)
gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login == env.REVIEWER and .submittedAt > env.PRIOR and .commit.oid == env.HEAD_OID)] | sort_by(.submittedAt) | last'
```

Poll every ~60s for up to ~10 minutes — same single-quoted `env.` filter, for Phase 5's reason.

**`submittedAt` alone does not answer "reviewed at this HEAD".** A review requested before a push lands *after* it — newer than `$PRIOR`, and still written against superseded code. Each review carries the commit it read (`.commit.oid`), so gate on that; a "no new comments" verdict on the commit your fix replaced says nothing about the fix. Read such a review anyway — its findings may well still apply — but don't let it satisfy the gate, and re-request against the new HEAD.

A poll loop must also distinguish jq's `null` (no match yet) from an **empty** result (a failed call, a broken filter): `[ "$R" != "null" ]` alone treats the empty string as a hit and exits the loop on the first hiccup, reporting no review while the bot is still working. Test for both.

If nothing newer arrives by then, request a human as Phase 5 describes, report `awaiting-review`, and **stop**. The bot earns a ten-minute poll; a human does not — do not wait on one. Either way **a review is required**: never auto-merge without one.

**A human review, once it exists, is accepted the same way — check for one before polling.** A previous run that timed out requested a human and stopped; if this phase only ever matched `REVIEWER`, that human's approval could never satisfy anything, and the skill would re-request the bot forever on a PR a person had already read:

```bash
gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login != env.AUTHOR and .commit.oid == env.HEAD_OID and (.state == "APPROVED" or .state == "COMMENTED"))] | sort_by(.submittedAt) | last'
```

A hit — from anyone, bot or human — is the round's review: read its inline comments the same way, record it below, and don't spend a round re-requesting. This is what makes "whichever review you accepted" a reachable instruction rather than a dead one.

Also pull inline review comments (most feedback is line comments, not the top-level review body):

```bash
gh api "repos/$SLUG/pulls/<N>/comments" --paginate
```

Filter to comments authored by the bot and posted at or after the review's `submittedAt`.

**A round's findings are its inline comments plus the "Suppressed comments" the review body folds into `<details>` — read both.** A body saying "Comments generated: 0" routinely sits above three to five suppressed findings; a loop that reads only inline comments calls such a round clean and merges over them.

**The verdict header is not a finding.** Copilot opens every review with 🟢 *Approval recommended* / 🟡 *Changes recommended* / 🔵 *Needs a closer look*. The yellow one counts *unresolved* threads, so a PR whose fixes are pushed but whose threads are still open stays 🟡 forever; the blue one on a broad change means "a human should read this" and no code fix turns it green. Judge the round by its findings alone: no actionable finding is `clean` whatever the colour. On 🔵, record the round, request the human from Phase 5's fallback, and don't spend a round asking the bot again.

**A quota refusal is not a review.** "Copilot was unable to review this pull request because the user … has reached their quota" arrives *as a review*, within seconds of the request. Match it in the poll (`.body | test("unable to review")`), stop polling at once, and take the no-bot path — request a human, report `awaiting-review`. Waiting the full ten minutes on it is the one cost the poll can avoid outright.

**Record what the round found**, before you start fixing — this is what Phase 5 reads on the next pass and what decides whether the cap is 3 or 5. Record it for **whichever review you accepted**, bot or human: Phase 5 falls back to a human when the bot times out, and a state file that only ever learns about bot reviews would leave `reviewed_oid` empty after a human approval, so Phase 8's coverage check would block a properly reviewed PR forever.

```bash
jq --arg oid "$HEAD_OID" --arg sev "$SEVERITY" --arg v "$VERDICT" \
   '.reviewed_oid = $oid | .severity = $sev | .verdict = $v' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
```

`VERDICT` is `clean` when nothing actionable came back and `open` otherwise. `SEVERITY` is `blocking` only if this round raised a correctness bug, a security or data-loss risk, a breaking change or a failing test — the classification 7c's 3-vs-5 decision turns on. Judge it now, while you're reading the findings; a later invocation sees only this file and cannot re-derive it. It is per round, not sticky: a round that returns only nits writes `nits` and the cap falls back to 3.

### 7. Address feedback

Pushing a fix alone is not enough — also respond on the thread. For every finding, inline or suppressed:

1. **Verify it before touching code.** Read what the comment points at and confirm the failure scenario holds. A bot finding can be flatly wrong — a glob that cannot match what it claims, a branch that is never taken — and a fix on a wrong premise is a new defect. A *refuted* finding is a disposition: reply with the reason and resolve the thread. A finding you *disagree* with on judgement (design, scope, taste) gets the reply and stays open for the user to settle.
2. Implement the fix locally.
3. Re-run the relevant local checks from Phase 2 for the files you touched (don't skip — CI re-running is slower than a 30s local lint).
4. Commit and push.
5. Reply to the comment thread explaining what changed (`gh api -X POST "repos/$SLUG/pulls/<N>/comments/<comment-id>/replies" -f body=...`) AND resolve the thread via the GraphQL `resolveReviewThread` mutation. Both — reply without resolve leaves a noisy unresolved thread; resolve without reply leaves the reviewer guessing. **Resolve before any re-request**: the bot's verdict counts unresolved threads, so a fixed-but-open thread buys another 🟡 and another lap.

A finding that comes back on the same line in a later round is a thread you didn't close, not a new finding: fix it or refute it on the thread now. One PR carried the same unanswered comment through seven rounds.

If the reviewer asks for something bigger than a fix — new tests, a harness, a redesign — stop and tell the user. Don't quietly expand scope.

Once the fixes are pushed, **don't re-request reflexively.** A push that contains only what this review asked for needs no fresh review to merge (Phase 7c says why) — handle the remaining threads and go to Phase 8. Loop back to Phase 5 only when the push carries something the reviewer has never seen. **Measure that; don't judge it** — the prose rule alone has not held:

```bash
REVIEWED=$(jq -r .reviewed_oid "$STATE")
git diff --shortstat "$BASE_REF"..."$REVIEWED"                 # what the reviewer read
git diff --shortstat "$REVIEWED"..HEAD                         # what you added since
git diff --name-status "$REVIEWED"..HEAD | grep -c '^A'        # new files
```

New files, or growth beyond a quarter of what was reviewed, is not a fixup. It is scope the review provoked — a harness built to answer "verification gaps", a redesign to answer a nit — and re-requesting on it starts a loop that reviews the growth: one PR went +444 → +1,979 lines between rounds 1 and 2 and spent rounds 3–5 on the addition. Stop and ask. Below that line, the loop-back spends the next round, and Phase 5 is where the budget is checked.

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
3. Push the fix. CI restarts; loop back to monitoring — **and if the fix changed shipped behaviour, re-enter Phase 5 before Phase 8.** Green checks are not a review: a behaviour-changing fix that goes straight from here to the merge decision carries code the reviewer never read, on a `reviewed_oid` for the old HEAD. Within budget that costs a round; out of budget it reports `blocked` (7c). A test-only, snapshot or workflow fix that changes no shipped behaviour keeps the direct path.

Hard stop conditions (escalate to user, don't keep grinding):
- Same failure recurs after 3 fix attempts on the same job — your hypothesis is wrong; stop and ask.
- The fix would require changes outside this branch's scope (e.g. updating a shared package, infra credentials).
- A test failure points at a real bug in code outside the diff (this branch surfaced it but didn't cause it).

Do not merge while any required check is failing or pending. `--admin` bypasses required reviews, not failing CI (see Hard rules).

### 7c. Round budget — when to stop looping

A **round** is one review you ask for and act on — request → review → fix → push. Each costs a review wait, a CI run and a re-read of the diff, and a bot reviewer will always find *something* — so left uncapped this loop doesn't converge, it just gets more expensive. Bound it.

**Budget: 3 rounds.** Extend to at most 5, and only while rounds keep surfacing **blocking** findings — a correctness bug, a security or data-loss risk, a breaking change, a failing test. Style nits, naming, doc wording, "consider extracting this" buy no extra round however many there are. At 5, stop regardless of what the last round said: a reviewer still finding real bugs on round 5 is telling you this change needs a human, not another lap.

**Rounds are counted and capped in Phase 5**, where reviews are actually requested — not at the end of the loop, which is one wasted review wait too late. A round therefore begins when you ask for a review, not when you act on one, and the very first review of the PR is round 1.

The state lives in `.context/deliver/round-<PR>.json`, keyed by PR so a branch reused for a second PR starts clean instead of inheriting a spent budget. It holds four things, and each one answers a question a bare counter cannot:

| Field | Written | Answers |
|---|---|---|
| `rounds` | Phase 5, before the request | is the budget spent? |
| `severity` | Phase 6, from the findings | is the cap 3 or 5? |
| `verdict` | Phase 6, from the findings | is there anything left to fix? |
| `reviewed_oid` | Phase 6, the HEAD reviewed | has the reviewer seen what's on the branch now? |

`severity` in particular has to be *written down*: "extend to 5 while blocking findings keep coming" is a judgement made while reading a review, and a later invocation that sees only a number cannot reconstruct it — it would stop at 3 through real blockers, or spend rounds 4 and 5 on nits. Recording it is what makes the cap enforceable rather than advisory.

It outlives the run, so re-invoking `deliver` on the same PR in the same workspace resumes the budget rather than granting a fresh one — the loop's cost belongs to the PR, not to the invocation. Reset it only when the user asks for another pass knowing the last one hit the cap.

`.context/` is gitignored and local, so this is workspace memory, not PR state: a fresh clone, or a different machine, starts at zero and at `reviewed_oid: ""` — which reads as "the reviewer has seen nothing", the safe direction, since Phase 8 then refuses to merge on a review it cannot tie to HEAD. That's the accepted limit of a file-based record; it means the count you report in Phase 9 is what *this* workspace spent, so say so if you know an earlier run happened elsewhere.

Stopping early is the normal outcome, not a shortcut: the first round whose review carries no actionable finding ends the loop. Never re-request just to confirm a clean review.

When the budget runs out:

- Still apply any fix that is trivially safe and self-evidently right (a typo, a null check you agree with) — but **don't loop back to Phase 5** afterwards. The push doesn't start a new round; the gate there would refuse it anyway.
- Reply on every thread you're leaving open with what you did or why you didn't, and leave those threads unresolved.
- **Keep handling CI** (Phase 7b) exactly as before. The budget caps review requests; it has nothing to say about a red pipeline, and an exhausted run that skipped CI would report a failing PR as ready for review — in `--no-merge` mode, where Phase 8 never evaluates the merge condition, nothing downstream would catch it.
- Go to Phase 8 unchanged. Unresolved *actionable* threads still block the merge condition, and so does a HEAD the reviewer never saw (Phase 8's `reviewed_oid` bullet). A budget exhausted with real findings open reports `blocked` — the cap ends the looping, it never lowers the merge bar.

**A fixup push does not invalidate the review that asked for it.** Phase 6's `.commit.oid == HEAD_OID` gate governs which review you may *accept as the review* — not whether every subsequent commit needs its own. Once a round's review has landed against the HEAD it actually read, fixes made **in response to it** don't need a fresh review to merge; that equivalence is what makes the loop terminate at all.

Read "in response to it" strictly, because it is the whole load-bearing width of the exception. New functionality, a redesign, a fix that reached well beyond the comment — and equally **a Phase 7b CI fix that changes behaviour**, which loops back only to CI monitoring and would otherwise reach Phase 8 carrying code no reviewer has seen — are all unseen changes. They go back through Phase 5's gate like any other round: within budget you spend one, out of budget you report `blocked`. A test-only or config-only CI fix that changes no shipped behaviour does not.

### 8. Auto-merge decision

In no-merge mode the *merge* is already decided against — the condition is false by definition, and Phase 8b never runs. **The assessment still happens.** `--no-merge` withholds the merge, not the truth about the PR: evaluate the conditions below anyway and report what they say — `ready-for-review` only when they all hold bar the merge itself, otherwise `awaiting-CI` or `blocked`, naming what blocks. Reporting ready-for-review unconditionally is how an exhausted budget with open findings, or a red pipeline, reaches a human as "done".

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
- The review is `APPROVED` or `COMMENTED` with no remaining unresolved actionable threads, AND
- **The review on record covers what is on the branch now** — `reviewed_oid` equals HEAD, or every commit since it is one this run made and 7c's equivalence covers: a fixup in response to that review, or a CI fix that changes no shipped behaviour (a lint autofix, a snapshot update, a workflow tweak). Those two exceptions are the same list 7c permits to skip Phase 5, and they have to match exactly — a rule that lets a commit through the loop and then blocks it at the merge is a deadlock, not a safeguard. Inside a run you know which commits are which; a re-invocation does not, so commits after `reviewed_oid` that this run didn't make are unreviewed code and report `blocked`. Without this the exhausted path becomes an auto-merge hole: skip Phases 5 and 6, and an old `APPROVED` with every thread resolved would satisfy every other condition above while HEAD carries a feature nobody reviewed.

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

Final message to the user must include: PR URL, the base it targets whenever that isn't the default branch (name the parent PR it stacks on), merge status (merged / awaiting-CI / awaiting-review / blocked-on-parent-PR / blocked), what the Phase 2c local round fixed and what it handed up (anything outside the diff, in particular), whether the reviewer bot was actually reachable, how many review rounds you spent and whether the Phase 7c budget ran out, the tracker task and the state you left it in (or why you didn't move it), and any decisions you punted (e.g. "left thread #X unresolved because the suggestion conflicts with the documented convention — please weigh in").

## Hard rules

1. **Never `--no-verify`, never `--no-gpg-sign`.** If a pre-commit hook fails, fix the root cause.
2. **Never push to the default branch.** This skill operates on a feature branch only.
3. **Never run a full test suite locally** — not full e2e, not full unit/integration. Targeted runs only; CI owns full suites. A pre-push gate that takes >2 min defeats the point of front-loading.
4. **Never merge without CI green.** Even with `--admin`, wait for `gh pr checks` to be green. Bypassing required reviews is one thing; bypassing failing CI is not.
5. **Don't expand scope under cover of review feedback.** If a suggestion is a refactor beyond the PR's purpose, push back in the thread instead of doing it. Phase 7's growth measure decides what counts, not your sense of it.
6. **Never publish a client's non-public details** into a public repo or one owned by anyone but that client — not in the diff, the commit messages, the PR body, or a review reply. See the Phase 2b gate. It's the one failure here a later commit can't undo.
7. **Follow the repo's dev-server/port convention** when you start a service for a local test. Don't auto-launch a whole-stack dev script.
8. **Never grind past the Phase 7c round budget.** 3 rounds, 5 if blocking findings keep coming. Past that the answer is a human, not another re-request — and the cap never relaxes Phase 8's merge condition.
9. **Never move a tracker task that belongs to someone else**, and never move one to *done* on anything but a successful merge of a PR that says it closes it. A wrong status is worse than a stale one — it's read as a fact by people who weren't in this session.
10. **A verdict header is not a finding; a suppressed comment is.** Read the folded findings, ignore the colour, verify before fixing, and never re-request the bot to turn 🔵 into 🟢.
