---
name: deliver
description: Deliver the work on the current branch, or an existing PR, to a level — run all relevant local checks (lint/typecheck/tests), get the change reviewed and fixed locally through the review-loop skill before anything is pushed, open or update a PR, work the CI loop, then stop at `ready` with one Deliver ask offering each level the repo's own workflows reach (e.g. dev, staging, prod). `--pr <N> --to <level>` carries out the owner's click on that ask: it is resumable, re-runs only the steps whose proof no longer matches the PR's patch-id, merges, and promotes the merge up to that level. Supports --base to target a branch other than the repo default (stacked PRs), --bot-review / --no-bot-review to force a PR bot's on-record review on or off, and --review-rounds N (0-10) to cap the local review loop — 0 skips it. CI is slow and a bot reviewer is slower; do not lean on either as a first pass. `--merge-only --pr <N> --expect-head <sha>` is a deprecated alias of `--pr <N> --to <first level>`, kept for one release.
---

# deliver

You are running the **deliver** skill. Goal: take whatever is on the current branch to `ready` with as few CI round-trips as possible, and, on the owner's Deliver click, on up the repo's [levels](#levels) to the one they clicked.

CI is slow and every avoidable push is a real cost — front-load everything locally before pushing. That includes the **review**: Phase 3 hands the change to the **review-loop** skill, which reviews and fixes it with fresh-context reviewers *before* the first push, so the diff that reaches GitHub is already hardened. A reviewer on the far side of the network — a bot, a person — is something this skill can put on the record (Phase 6b) but never waits on as a first pass.

**Without a click, stop at `ready`.** This is every run without `--to` (how **kickoff**, **pickup** and **overnight** call this): everything through Phase 6b runs — checks, confidentiality gate, review, PR, CI loop, the tracker's move to *in review* — then Phase 7 assesses `ready`, opens [the Deliver ask](#the-deliver-ask), skips Phase 7b, and reports. Nothing is merged; the decision of how far to deliver stays with the owner. `--no-merge` is accepted and means the same. `--review-rounds 0` stops at `ready` too, and its ask says no local review ran.

**No review is requested without a click.** Requesting one exists to unblock a merge, and there is no merge to unblock; a human is going to open this PR anyway, which is the whole point of handing it back. Requesting one from here would page a colleague per item on an unattended `overnight` run — for a PR whose author has not yet looked at it. A click on a `REVIEW_REQUIRED` PR is what requests one ([Deliver to a level](#deliver-to-a-level), step 8).

**Stacked mode:** when invoked with `--base <branch>`, that branch — not the repo's default branch — is what this PR targets and what every diff in this run is computed against. Its purpose is stacking: the parent branch is usually itself an open PR, so this PR's diff shows only the increment on top of it instead of replaying the parent's changes. Phase 0 resolves it once into `BASE_REF`; nothing downstream re-derives it. Phase 7's stacked-base check then does exactly what it always did — a base that is an open PR blocks the merge — which under `--base` is the expected outcome, not a surprise: land the parent first.

**Deliver to a level:** `--pr <N> --to <level>` carries out the owner's click on the Deliver ask: it takes an existing PR up the repo's levels to `<level>` and stops there. deliver is resumable: it runs [its own procedure](#deliver-to-a-level), which works through the phases and skips every step whose [proof](#proof) still holds, so "Deliver to prod" the day after "Deliver to dev" only runs the promotion. It is also the executor behind a batched approval such as `overnight` track mode's merge train.

## Arguments

- **`--pr <N> [--to <level>] [--parent <P> --parent-head <psha>]`** — deliver an existing PR, resolving its head yourself. Without `--to` (or with `--to ready`) it re-proves `ready` and refreshes the ask. With a higher level it needs the owner's click and runs [Deliver to a level](#deliver-to-a-level). `--parent` is for a PR that was stacked on PR `<P>` at head `<psha>`.
- **`--no-merge`** — the default: stop at `ready`. Accepted so existing callers keep working.
- **`--merge-only --pr <N> --expect-head <sha> [--parent …]`** — deprecated, accepted for one release: the same as `--pr <N> --to <the first level above ready>`, with `<sha>` as the approved head. Unlike the old mode, that waits for the merge level's deploy too, and may push CI fixes below the material-change measure.
- **`--base <branch>`** — target `<branch>` instead of the repo default, and compute every diff in the run against it. For stacking.
- **`--bot-review` / `--no-bot-review`** — force Phase 6b's on-record bot review on or off, overriding the `reviewer` profile knob for this run.
- **`--review-rounds N`** — cap Phase 3's local review at `N` rounds. **0–10, default 3.** Raise it for a change whose review keeps finding real defects. **Don't lower it to 1 or 2 to save time** — Phase 3 fixes what round 1 raises, and with `--quiet-rounds 1` a confirming round then has to fit inside the budget. (That confirming round is cheap: one reviewer on the fix commits, and it only has to come back free of blockers and majors, not free of nits. It runs only when round 1 fixed a blocker or major; a round 1 that confirmed nothing worse than a minor ends the loop.) At `N=1` any finding at all guarantees `budget-exhausted`, which Phase 7 reports as `blocked`, and the loop's own rules forbid buying more rounds by re-invoking. If you have already reviewed the work, pass `0`, not `1`. **`0` skips the review entirely**, so the run stops at `ready` with no review proof, and a later click runs the review first — see Phase 3. A value outside 0–10 is a stop, not a clamp: silently reviewing three times when someone asked for thirty is worse than refusing.

## Project specifics — read these first

This skill is repo-agnostic. The concrete commands, reviewer, and merge policy come from the repository you're running in. Before Phase 1, gather:

- **Check commands per package** — how to lint / typecheck / test / run codegen for each workspace. Derive from the repo's `AGENTS.md` / `CLAUDE.md`, per-package docs, and `package.json` (`scripts`) / `Makefile` / `justfile`. If the repo has a **`## Skill profile`** section in its root `AGENTS.md`, use that — it's the curated source. The CI workflow outranks docs and script names, but not a `## Skill profile` (curated on purpose, and what `upstream-pr` and `review-loop` read first): when docs or scripts disagree with the `run:` steps of the lint / format / typecheck jobs in `.github/workflows/*`, run what CI runs, flags included (a `--check` the `package.json` script lacks, a type-aware lint mode). Docs and scripts drift; CI is what turns the PR red.
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
- **Human reviewers** — the `## Skill profile` key **`reviewers`** (plural), a distinct knob: who to request when a Deliver click meets a missing approval the clicker cannot bypass ([Deliver to a level](#deliver-to-a-level), step 8). Unset, a candidate is derived from recent merged PRs.
- **Levels** — read from the repo's workflows, never configured: see [Levels](#levels). An `ownerCanSelfMerge` profile key is ignored; the owner's click is what authorizes `--admin` ([Deliver to a level](#deliver-to-a-level), step 8).
- **Its own delivery skills** — a repo whose agent docs route PRs through its own delivery skills (an Open Mercato app that carries the `om-*` pipeline in `.ai/skills`) delivers through those. There, this skill may still take a change to `ready` when another skill calls it, but it never merges or promotes, and opens no Deliver ask: the merge belongs to that pipeline, so name it in the report instead.
- **Dev-server / port convention** — if the repo documents one (e.g. a worktree port rule), follow it whenever you need to start a service for a local test.
- **Tracker + its status vocabulary** — from the `## Skill profile` (`tracker`). If the repo documents which states mean *in progress*, *in review* and *done*, this skill moves the task along with the PR (Phases 5b and 7b). If it documents a tracker but no vocabulary, don't guess at state names — report the task's current state in Phase 8 instead.

If a needed value isn't documented and you can't infer it, ask the user rather than guessing.

## Levels

A **level** is how far a change has gone. `ready` is built in and always first: checks, review loop, QA evidence when the PR needs it, CI green, nothing merged. Every level above it is a stage the repo's own pipeline reaches, read from the repo, never configured. Derive them once per run, from the release target's copy (`git show origin/<release target>:.github/workflows/<file>`; the release target is defined under [Deliver to a level](#deliver-to-a-level)), in this order; the first source that yields a level wins:

1. **Workflows.** Read each file's `on:`, `name:`, its jobs' `environment:` and their `uses: ./.github/workflows/…` calls. A workflow is a candidate when it deploys or releases: a job has an `environment:`, or its name or file says deploy, release or publish. These are never levels: CI, lint and test workflows; preview workflows (triggered by `pull_request`); cleanup (a closed PR, a reaper); image builds; scheduled jobs; and a workflow only another one calls (`workflow_call`), which belongs to its caller. A candidate whose trigger ties it to the default branch is a level:
   - **Reached by the merge:** a `push` to the default branch, or a `workflow_run` of a non-level workflow (CI) on it. Several such workflows are one level. When a `paths` / `paths-ignore` filter excludes every file in this PR's diff, the workflow will not run for this merge: leave it out for this PR.
   - **Follows a level by itself:** a `workflow_run` of a level's workflow.
   - **Dispatched:** only `workflow_dispatch`, with an input that takes a commit SHA or a ref. deliver dispatches it for the merge commit, then watches it. A dispatch with no such input (no inputs, a choice of environment, a release tag) is not a level; name it in the ask as skipped.
2. **Prose.** A repo with no such workflow that describes its deploy in its `AGENTS.md` or README ("merging to main deploys to staging") takes its levels from that text.
3. **Default.** Otherwise there is one level, `merged`.

**Names.** A level is named by the stage word in its workflow's `name:` or file name: `dev`, `staging`, `prod` (also `production`), `released` (also `release`). Without one, use the farthest stage word in its environment names, else the file name without `.yml`. Environment names often name a credential scope (`om-preview` on a dev deploy), so they come second. A merge level of several workflows takes the farthest name, in the order `dev` < `staging` < `prod` / `released`; a workflow without a stage word never names it while another has one. A merge level that none of the PR's workflows reach is `merged`. Order: `ready`, the merge level, each level that follows it, then the dispatched ones.

**Proof.** A level is reached when its workflow run succeeded for the merge commit, or for a later commit on the default branch that contains it (`git merge-base --is-ancestor <merge> <run headSha>`), since a later push deploys the merge too. For a dispatched level, `headSha` is the branch the run started on, not the input, so only a run this session dispatched for the merge commit, or one whose `displayTitle` names a commit that contains it, is proof. Otherwise dispatch it again: a repeated deploy of the same commit costs a run, a promotion skipped on a guess ships nothing.

Worked readings: a dev deploy on push, a staging deploy on `workflow_run` of it, and a prod deploy dispatched with a `sha` input give `dev` → `staging` → `prod`. Dev and prod deploys that both run on push give one level, `prod`: merging reaches both. A release workflow on `workflow_run` of CI gives `released`. A path-filtered push deploy of a side service (`paths: apps/<service>/**`) is part of the merge level only for a PR that touches those paths. A workflow that doesn't fit these rules can be misread; that is why every ask lists the levels it read and where each came from. The fix for a wrong read is the workflow or a sentence in `AGENTS.md`, not a setting.

## Proof

deliver writes no state of its own. Every step is skipped when proof that it already covered this change still holds, and every proof is something that already exists: what this session did, review-loop's state, or GitHub. **This change** means the PR's own diff, keyed on its patch-id, so a rebase that leaves the diff alone keeps every proof:

```bash
"${CLAUDE_SKILL_DIR}/scripts/patch-id.sh" origin/<baseRefName> HEAD <proven-sha>   # equal second columns: same change
```

- **Phase 2, local checks:** this session ran them on a head with the same patch-id; or CI is green on the PR's head and that head's patch-id equals HEAD's. CI runs the same gates.
- **Phase 3, review:** this session's own review of a head with the same patch-id; or review-loop's `state.json` with `sources.local.exit: converged` at a `sources.local.reviewed_oid` whose patch-id equals HEAD's, with no blocker or major open. No such proof (a fresh session without that file): the review runs again.
- **QA evidence:** a PR comment with the QA result (pass/fail, screenshots) that names the head it tested, and that head's patch-id equals HEAD's.
- **Phase 4, push:** the PR's `headRefOid` equals HEAD.
- **Phase 5, PR:** the PR exists; its update path runs.
- **Phase 6, CI:** never skipped. CI has to be green on the head being merged, and a green run already on it is that proof.
- **The merge:** the PR is `MERGED` with this change (step 1 of [Deliver to a level](#deliver-to-a-level)).
- **Each level above the merge:** its proof under [Levels](#levels).

A missing proof means the step runs; never skip on a guess. A skip never weakens the merge gate, because CI still has to pass on the head being merged. The report lists each skipped step and the proof it reused.

## The Deliver ask

The owner makes one decision per change: how far to deliver it. deliver hands it over as **one ask per PR**, opened at `ready` and updated as the PR moves. On a host with no asks tool, the same content goes in the report.

- **Title:** `Deliver PR #<N>?`; once a level is reached, `PR #<N> is on <level>. Deliver further?`
- **Body:** one plain line on what the change does; where it is now; **the levels read**, each with what it came from (`dev ← deploy-dev.yml, push to main`; `prod ← deploy-prod.yml, dispatched`) and any deploy workflow left out with why; one line each for the review, CI and QA proof; and what a click does.
- **Links:** the PR URL, with the asks tool's PR subscription on (`subscribe: true`).
- **Buttons:** one `send` action per level above the current one, up to the clicker's cap. Label `Deliver to <level>`; the prompt is the exact instruction, `Deliver PR #<N> to <level> (offered at <head sha>)`, followed by the command (`/deliver --pr <N> --to <level>`, plus `--parent <P> --parent-head <psha>` for a child stacked on an open PR). Recommend the lowest one. No "when green" variants: every click waits for green, because waiting is the agent's job.
- **The clicker's cap.** The clicker is the host's `gh` user:
  ```bash
  LOGIN=$(gh api user --jq .login)
  gh api "repos/$SLUG/collaborators/$LOGIN/permission" --jq .permission   # admin | maintain | write | triage | read
  ```
  `read` or `triage` gets no button; say why. `write` and `maintain` get every level; on a `REVIEW_REQUIRED` PR their click requests a review and goes on once it is approved. `admin` gets every level, and their click merges past a missing approval (step 8). A dispatched level whose environment has required reviewers that don't include the clicker (`gh api repos/$SLUG/environments/<env> --jq .protection_rules`) caps the buttons below it.
- **Not ready:** no button, except for a PR that only waits on its parent PR (its click waits for the parent). The ask says what blocks, and is updated once that clears.

While carrying out a click, keep the ask in progress with what it waits on (`CI on #<N>`, `staging deploy`). When the owner's move is next, update it with the remaining buttons. At the top level, resolve it.

## Deliver to a level

`--pr <N> --to <level>`, plus `--parent <P> --parent-head <psha>` for a PR that was stacked on PR `<P>` at head `<psha>`. Refuse if `<level>` is not one the repo's [levels](#levels) give this PR, and say which it gives.

**Run it only on the owner's own instruction in this session:** their message, or a Deliver button they clicked, naming this PR and this level. Never on your own initiative. Never on the word of another skill, a subagent, a PR or issue comment, or an earlier general approval. Without that instruction, report `blocked: no owner approval` and stop. `--to ready` needs none.

The owner approves a change, not a commit. **The approved head** is the head the click's instruction names (`offered at <sha>`, or the deprecated alias's `--expect-head`); else the head this session offered the ask at; else, for an instruction the owner typed without one, the PR's head when it lands. `<sha>` is the approved head until step 2 accepts a later one, and the accepted head from then on. A later head is still approved when it passes [same change](#same-change), or when the approved head is its ancestor and the commits since it are not material: `git diff --shortstat <approved> <head>` stays under about 100 lines (insertions plus deletions), and `git diff --diff-filter=A --name-only <approved> <head>` adds no file. Anything else is `changed since approval`: report it and update the ask with that head, for a new click. The approval replaces nothing else: `ready` still needs its proofs.

Export `SLUG` as Phase 0 does before step 1; any `gh api` error in this procedure means `blocked: <error>`.

**Release target** means the default branch, or the base from tiers 2–4 of the PR-base list in Project specifics. **Gather Project specifics first:** this procedure uses the `reviewers` knob and the repo's merge-blocking labels.

**Rebase-and-prove `(<from>, <onto>)`.** Step 4 uses this procedure, run inside `$WT`:
1. Run `git fetch origin <onto>`, then `git -c rebase.updateRefs=false rebase --onto origin/<onto> <from>` on the detached HEAD. On any conflict, run `git rebase --abort`, report `conflict on rebase` and stop. **Never resolve a conflict in this procedure.**
2. In one shell invocation:
   ```bash
   set -o pipefail
   OLD=$(git diff --no-color --no-ext-diff --no-textconv --binary <from> <sha> | git patch-id --verbatim) &&
   NEW=$(git diff --no-color --no-ext-diff --no-textconv --binary origin/<onto> HEAD | git patch-id --verbatim)
   ```
   Both values must be non-empty and equal. `--verbatim` counts whitespace and needs git ≥ 2.39. On any error, an empty value or a mismatch, report `blocked: patch changed on rebase` and stop.
3. If `baseRefName` is not `<onto>`, run `gh pr edit <N> --base <onto>`. If that fails, report `blocked: retarget failed` and stop. Retarget before pushing, so the CI the push triggers runs against the right base.
4. Push to the named ref, never with a bare refspec: `git push --force-with-lease=refs/heads/<headRefName>:<sha> origin HEAD:refs/heads/<headRefName>`. The lease fails if anyone else pushed. If the push fails, restore the old base when it still exists and differs from `<onto>` (`gh pr edit <N> --base <old baseRefName>`). Then report `changed since approval` if the lease was rejected (`stale info` or `rejected`), otherwise `blocked: push failed: <git message>`, and stop.
5. The rebased head is approved by the proof. Use it as `<sha>` from here on, and name it in every later report.

<a id="same-change"></a>**Same change `(<approved>, <head>)`.** Decides whether `<head>` carries the change the owner approved at `<approved>`, by comparing the PR's own diff at both heads instead of the SHAs. After `git fetch origin`, run:
```bash
"${CLAUDE_SKILL_DIR}/scripts/same-change.sh" origin/<baseRefName> <approved> <head>
```
It compares `git patch-id --verbatim` of `git diff <merge-base>..<head>` for each head. Hunks in `*.md` files and under any `docs/` or `.ai/` directory may differ, so a doc-only conflict resolution counts as unchanged. Agent instructions (`AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `.ai/skills/`, `.agents/`) count as code; every other hunk must match exactly. Its `differs:` lines name the files the update touched.
- Exit 0, `same change`: `<head>` is approved. Use it as `<sha>` from here on (once `$WT` exists, `git checkout --detach <sha>` in it), and keep the `differs:` lines for the report.
- Exit 1, `changed`: apply the material-change measure above.
- Exit 2: `blocked: <its error>`.

**Steps:**

1. **Read the PR:**
   ```bash
   gh pr view <N> --json state,isDraft,headRefName,headRefOid,baseRefName,reviewDecision,latestReviews,mergeStateStatus,labels,isCrossRepository,mergeCommit,body
   ```
   Then, in order:
   - **Already `MERGED`:**
     - `headRefOid` equals `<sha>`: the merge is proven. Run Phase 7b if it hasn't run (a run that died after the merge), then go to step 9.
     - Otherwise, with `--parent`: fetch `<sha>`, `<psha>` and `mergeCommit.oid`. If any is missing, report `blocked: cannot verify the merged change`. If all three are present, compare `git diff <mergeCommit.oid>^ <mergeCommit.oid>` with `<psha>..<sha>` by patch-id: equal means the merge is proven, run Phase 7b if it hasn't run, then go to step 9; different means `blocked: merged with a different change`.
     - Otherwise: report `blocked: merged with a different change`.
   - **Hard stop:** report `blocked: <reason>` and stop when any of these holds. A click never overrides one:
     - the PR is not open, or is a draft;
     - it carries `do-not-merge`, `blocked` or `qa-failed`, or a label the repo's docs name as merge-blocking;
     - a latest review by anyone but the clicker is `CHANGES_REQUESTED`;
     - a person (an author whose `__typename` is not `Bot`; GraphQL logins carry no `[bot]` suffix) opened a review thread that is unresolved: `gh api graphql -f query='query{repository(owner:"<o>",name:"<r>"){pullRequest(number:<N>){reviewThreads(first:100){totalCount nodes{isResolved comments(first:1){nodes{author{__typename login}}}}}}}}'`. If `totalCount` is above 100, report `blocked: too many threads to verify`. An unresolved bot thread is not a hard stop; Phase 6b works it in step 5.
   - **Not a feature branch:** `headRefName` is a release target, or a protected branch (`gh api repos/$SLUG/branches/<headRefName> --jq .protected`), or the PR comes from a fork. Report `blocked: head is not a feature branch` and stop.
2. **Head check.** If `headRefOid` differs from the approved head, apply the approval rule above. A rebase or a merge of the base that left the change alone carries on, and so do review and CI fixes below the material-change measure; anything else stops there.
3. **Setup.** When the current checkout is the PR's branch at `<sha>`, work in it. Otherwise:
   ```bash
   git fetch origin
   WT=$(mktemp -d)
   git worktree add --detach "$WT" <sha>
   ```
   Run every later git command inside `$WT`, and run `git worktree remove --force "$WT"` on every exit. The caller's checkout and the named branch are never touched. In `$WT`, every push the phases make goes to the named ref with a lease, as in rebase-and-prove step 4, and every `gh pr` call names `<N>`. review-loop's `state.json` stays in the caller's checkout's run directory: read it, and point the loop's run directory at it, from there.
4. **Base.**
   - **No `--parent`:** `baseRefName` must be a release target. If an open PR heads it instead, the click waits for that parent to merge, as it waits for CI: keep the ask in progress, waiting on `#<n> merged`, and report `blocked-on-parent-PR #<n>` until it lands. Any other base: `blocked: base is not a release target`, and stop.
   - **`--parent` given:** read the parent with `gh pr view <P> --json state,headRefName,baseRefName,headRefOid,mergeCommit`. Stop with the named report if any check fails:
     - the parent is not `MERGED`: `blocked-on-parent-PR #<P>`;
     - its `baseRefName` is not a release target: `blocked: base is not a release target`;
     - `<psha>` is not the parent's `headRefOid`: `blocked: parent head mismatch`. The train stacks one level deep and this procedure never rebases a PR that has children, so the parent's merged head is the one the owner approved;
     - the child's `baseRefName` is neither the parent's `headRefName` nor the parent's `baseRefName`: `blocked: not stacked on #<P>`;
     - `git fetch origin <base>` fails, or the parent's `mergeCommit.oid` is not an ancestor of `origin/<base>`: `blocked: parent not on <base>`. Here `<base>` is the parent's `baseRefName`.

     Then decide whether to rebase:
     - The parent's merge commit is already an ancestor of `<sha>`: a re-approved, already-rebased head. Skip the rebase; if `baseRefName` is still the parent's `headRefName`, retarget it to `<base>` (`gh pr edit <N> --base <base>`, and on failure `blocked: retarget failed`). A retarget does not re-run CI, so after one, re-run the head's latest workflow runs (`gh run rerun <id>`) before step 6.
     - `<psha>` is an ancestor of `<sha>`: run rebase-and-prove(`<psha>`, `<base>`).
     - Neither: report `blocked: not stacked on the parent's final head` and stop.
5. **Ready, from proof.** Work through Phases 1–6b in the working copy, skipping each step whose [proof](#proof) still holds and noting the proof it reused. A step without proof runs as its phase says, fixes included. After any new commit, repeat step 2 against the approved head. Then evaluate Phase 7's `ready` conditions; anything but `ready` (a review that ended `budget-exhausted`, a blocker or major still open, an unresolved bot thread) reports `blocked: <condition>` and stops.
6. **Every check green on `<sha>`.** This is hard rule 4. Wait as **Waiting on CI** says; its `no-checks` answer means report `awaiting-CI` and stop, and `head-moved` means step 2 on the new head, then step 6 again. `gh pr checks` covers every check, required or not, and commit statuses too. Confirm the result against the head commit's check-runs as Phase 6 does. A real failure goes to Phase 6, which fixes it; then step 2, since a material fix re-asks instead of merging.
7. **QA sign-off.** When the PR carries `needs-qa`, the click is the QA sign-off: with QA evidence on the head (its [proof](#proof)), add the label with `gh pr edit <N> --add-label qa-approved`. Without it, report `blocked: needs QA evidence` and stop. This skill does not run QA itself.
8. **Merge.**
   - Re-read the PR and repeat step 1's checks, since a label or review can arrive during the CI wait. Then read `mergeStateStatus`, waiting up to 5 minutes while it is `UNKNOWN`:
     - a different head: step 2 on it, then step 6 again;
     - `CLEAN` or `HAS_HOOKS`: merge;
     - `BLOCKED` with `reviewDecision: REVIEW_REQUIRED`, and the clicker can merge as an admin (`gh api graphql -f query='query{repository(owner:"<o>",name:"<r>"){pullRequest(number:<N>){viewerCanMergeAsAdmin}}}'`): first list the base's required checks, from classic protection (`gh api repos/$SLUG/branches/<baseRefName>/protection/required_status_checks`, where a 404 means none) and from rulesets (`gh api repos/$SLUG/rules/branches/<baseRefName>`). Each must have succeeded on `<sha>`. A required check that never ran, or ran late, is not a pass. Only then merge with `--admin`; otherwise report `blocked: branch protection`;
     - `BLOCKED` with `reviewDecision: REVIEW_REQUIRED`, and the clicker cannot: request the reviewers with `review-loop --source human --pr <N> --base <baseRefName> --gate none --no-fix`, which uses the `reviewers` profile knob or derives a candidate, and report `awaiting-review`. Keep the ask in progress, waiting on the review; once it is approved, run this procedure again, since the click still stands. `--no-fix` is what makes `--gate none` safe: a source that fixed and pushed from here would leave the PR's newest commit ungated, unreviewed and unwatched. This is the only place this skill requests a person;
     - any other `BLOCKED`: `blocked: branch protection`;
     - `UNSTABLE`: go back to step 6 once, since a late check may still be running; still `UNSTABLE` means `CI failed`;
     - `BEHIND`: bring it up to date in the working copy with `git fetch origin <baseRefName> && git merge --no-edit origin/<baseRefName>`. On a conflict, run `git merge --abort` and report `blocked: conflict with base`; never resolve one in this procedure. Then run same-change(`<sha>`, `HEAD`). If it says `changed`, report `blocked: base moved` instead: the update would change what the owner approved, nothing was pushed, and the owner re-approves the updated change. If it passes, push with `git push --force-with-lease=refs/heads/<headRefName>:<sha> origin HEAD:refs/heads/<headRefName>`; when the lease is rejected, go to step 2 on the new head, and on any other failure report `blocked: push failed: <git message>`. Use `HEAD` as `<sha>` and go back to step 6;
     - `DIRTY`: `blocked: conflict with base`;
     - anything else: `blocked: <status>`.
   - Run `gh pr merge <N> --squash --match-head-commit <sha>`, plus `--admin` only in the case above. Don't use `--delete-branch`: it also deletes the local branch, which may be checked out elsewhere.
   - **A non-zero exit is not proof the merge failed — check the PR, never retry blind:** `gh pr view <N> --json state,mergedAt,mergeCommit`. `MERGED` means done. Re-running `gh pr merge` on a merged PR can push a deleted branch back and leave a stray merge commit on the base, which is published history you must not clean up alone. The same read settles a merge that times out or drops its connection. Not merged: report `blocked: merge refused: <gh message>` and stop.
   - Then delete the remote branch with `git push origin --delete <headRefName>`. If it is already gone (the repo deletes head branches on merge), that counts as done. The forge retargets any PR stacked on it.
   - Run Phase 7b, using the PR `body` read in step 1.
9. **Promote.** Take the merge commit (`mergeCommit.oid`) up each level after `ready` until `<level>`, in order, skipping a level whose proof holds:
   - **The merge level:** wait for each of its workflows' runs for the merge commit: `gh run list --workflow <file> --commit <merge> --json databaseId,status,conclusion`, then `gh run watch <id> --exit-status`, through **Waiting on CI**. `merged` has nothing to wait for.
   - **A level that follows:** its run starts by itself; find it with `gh run list --workflow <file> --event workflow_run --json databaseId,headSha,status,conclusion` and wait the same way.
   - **A dispatched level:** `gh workflow run <file> --ref <release target> -f <input>=<merge>`, find the run that dispatch started (`gh run list --workflow <file> --event workflow_dispatch --limit 5 --json databaseId,createdAt`), and wait for it.

   A failed run is `blocked: <level> failed: <run url>`; never re-run a deploy on your own. After each level, update the ask as [The Deliver ask](#the-deliver-ask) says.
10. **Report** one of:
    - `delivered to <level>`
    - `changed since approval`
    - `blocked-on-parent-PR #<n>`
    - `conflict on rebase`
    - `CI failed`
    - `awaiting-CI`
    - `awaiting-review`
    - `blocked: <reason>`

    Name each step skipped on proof, and the proof. After any push or accepted head change, name the new head and the files same-change listed as differing, which is what the update touched. A re-approval names that head and keeps the same `--parent` arguments; step 4 recognises it as already rebased.

## Phases

### 0. Anchor

Before doing anything, record where the run starts:

```bash
mkdir -p .context/deliver
git rev-parse --abbrev-ref HEAD > .context/deliver/branch
export SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)   # Phases 6 and 6b interpolate this
```

Resolve the review budget here too, and **stop rather than clamp** on a value outside 0–10 — silently reviewing three times when someone asked for thirty is worse than refusing:

```bash
export REVIEW_ROUNDS="${ARG_REVIEW_ROUNDS:-3}"
case "$REVIEW_ROUNDS" in
  ''|*[!0-9]*) echo "--review-rounds must be an integer 0-10"; exit 1 ;;
esac
[ "$REVIEW_ROUNDS" -le 10 ] || { echo "--review-rounds must be 0-10"; exit 1; }
echo "$REVIEW_ROUNDS" > .context/deliver/review-rounds
```

`SLUG` is exported here because the `gh api` calls downstream are merge-gating reads: an unset variable interpolates to `""`, `repos//…` 404s, and the run can neither tell a skipped check from a failed one nor find a single review comment — while looking like it asked.

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

Refuse to run on the default branch, and refuse when `BASE_REF` is the branch you're on — a PR cannot target itself. Under `--pr`, the branch is the PR's head in [Deliver to a level](#deliver-to-a-level)'s working copy, not the caller's checkout. If the working tree has uncommitted changes, surface them and ask the user before continuing — don't silently `git add -A`.

### 1. Scope detection

Look at `git diff "$BASE_REF"...HEAD --name-only` and bucket the touched files by package/workspace (top-level dir, monorepo workspace, or whatever the repo's structure is). Only run the checks for packages that actually changed — don't run one package's tooling for a branch that didn't touch it.

On a stacked run that range is deliberately narrow: the parent's files were already checked on the parent's PR. Don't widen it back to the default branch to be safe — that re-runs the parent's whole check surface on every child in the stack, which is the cost stacking exists to avoid.

### 1b. Preview data — only if the repo asks for it

Some repos require that a new or changed screen be visible on a fresh install without anyone creating data by hand: a demo-data or preview-seed rule in their agent docs, or a preview-data section in the PR template. Look for one. No such rule → skip this phase.

When the rule exists and the Phase 1 diff adds or changes something a person sees (a page, a list, a dialog, a state of an existing screen):

1. List the states a reviewer needs to judge the change: the populated screen, plus each state this change adds or changes. Skip cosmetics, loading spinners and paging limits; aim for six lines or fewer.
2. For each state that seed data can reach, make sure the repo's seed mechanism creates a record showing it. Extend the seeds in this branch when they don't, following the repo's seeding rules (idempotent, the documented write path). A module with no seeds yet gets its first ones here; "there was nothing to extend" is not a reason to skip.
3. Prove it the cheapest way the repo offers: its seed tests, or a fresh init that you open.
4. Keep the list for Phase 5: one line per state with the record and the page path. A state seeds can't reach (an error, a permission denial, a whole-install state) is named with how to reach it.

When nothing new needs seeding to see the change (backend-only, refactor, docs, changed wording on an existing screen), write `N/A — <reason>` in that section instead, plus where to look if people see a difference. The repo's own definition of the section wins over this one. Never leave the section out when the template has it.

Seed data is published code: when the Phase 2b gate fires, the seeds pass it too. Invented names only, never a client's real data.

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

**Skip on proof:** a green CI on a head with this patch-id, or this session's own run of these checks on one, covers them ([Proof](#proof)).

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

**First, the skip gates.** When a review already covers this patch-id ([Proof](#proof)), don't run another: say which proof you reused. If Phase 0 resolved `REVIEW_ROUNDS` to `0`, **do not invoke `review-loop` at all** — go straight to Phase 4; the run stops at `ready` with no review proof. Never pass `--max-rounds 0`: that skill runs at least one round per invocation by design, so `0` there means "review once, then immediately exceed the cap", which reports `budget-exhausted` and lands the run on `blocked` — the opposite of what was asked for, after doing the work that was meant to be skipped.

Leaving no proof behind is the whole reason `0` is allowed. It lets someone who has already reviewed the work skip a redundant pass without also handing them a way to merge code no reviewer read: a later Deliver click finds no review proof and runs the review first. Everything else still runs: the checks, the confidentiality gate, the PR, the CI loop.

Otherwise invoke the **review-loop** skill, passing the base and the budget Phase 0 resolved:

```
review-loop --source local --base "$BASE_REF" --quiet-rounds 1 --max-rounds "$REVIEW_ROUNDS" --gate scoped
```

`--base` is not optional. Phase 0 promised nothing downstream re-derives a base; that skill resolves its own from repo config when nobody passes one, and on a `--base` run it would then review the parent's entire diff instead of this branch's increment — burning the whole budget on code the parent's own PR already reviewed.

**If `review-loop` is not installed** — this repo supports symlinking a single skill — don't skip the review and don't improvise a rubric. Run one round of it inline: a fresh reviewer subagent on `git diff "$BASE_REF"...HEAD`, told nothing of the branch's intent, asked for whole files and callers and a severity, a concrete failure scenario and a fix per finding; verify each finding before acting on it; fix what holds; hand up the judgement calls and anything outside the diff. There will be no `state.json`, so **Phase 7's review conditions read differently on this path, and you must say which path you took.** The fallback satisfies it when its single round left nothing actionable open *and* the HEAD its reviewer read is still HEAD — the same question the field answers, asked by hand. It is one round, so it can never be `converged`; don't write that word, and don't invent a `state.json` to hold it. Report it as *inline fallback, one round* in Phase 8, so a reader can tell a looped review from a single pass.

Those arguments are deliberate and differ from that skill's standalone defaults:

- **`--quiet-rounds 1`** — one round raising nothing blocking is enough here, because this is a front-load rather than a hardening run and the change still has CI and a human ahead of it. The minors and nits it lists travel in the PR body for the reviewer to pick up; spending fix-rounds on them is how a scoped change acquires defects it did not have. Pass `--quiet-rounds 2` when the branch warrants it (a migration, an auth path, a public contract); it adds a second single-reviewer follow-up round and is worth it there.
- **`--max-rounds "$REVIEW_ROUNDS"`** — default 3; past three, the answer is a human, not another lap. That skill caps a prose-only diff at 2 regardless. `--review-rounds N` overrides exactly this number and nothing else. The quiet-round threshold and the gate stay put, because they define what "reviewed" *means* rather than how long to keep at it.
- **`--gate scoped`** — the checks from Phase 2, for the packages this diff touches. Not the repo's full gate: a full suite pre-push is slower than the CI it exists to front-load (hard rule 3), and CI owns the full one.

**The reviewer prompts are that skill's, verbatim — do not improvise the emphasis lanes.** In particular never ask a reviewer what *else* in the repo states a fact this diff corrects, or whether the change is "complete" repo-wide. That question always returns something, none of it caused by this branch, and acting on it is how a scoped PR turns into a tour of the repository. Pre-existing drift is a follow-up; the loop's hard rule 6 hands it up, but only if the prompt didn't solicit it.

Both artifacts matter: `state.json` (the machine-readable result) and `report.md` (the curve, the rubric, the fixed/refuted counts) — both under the run directory the loop names. Phase 5's PR body needs the second; Phase 7 needs the first:

| Field | What this skill does with it |
|---|---|
| `sources.local.reviewed_oid` | Phase 7's `ready` condition, and the review's [proof](#proof) — has **the fresh-context review** seen what is on the branch now? Per-source for a reason: a bot round's own fix commits must not advance the field that answers for the local loop. |
| `sources.local.exit` | `converged` is the only value that can satisfy Phase 7. `budget-exhausted` reports `blocked`. |
| `open[]` | blockers and majors still open block `ready`; handed-up decisions go in the PR body and the Phase 8 report. |

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

If the branch isn't pushed yet, push with `-u`. If it is, just push; when the PR's head already equals HEAD, there is nothing to push.

### 5. PR open or update

```bash
gh pr view --json number,url,reviewDecision,reviews,headRefOid 2>/dev/null
```

- No PR → `gh pr create --base "$BASE_REF"`. Title in Conventional Commits style stating the plain-language outcome. Write the body in the [house format](../pr-polish/references/pr-description.md), after the context/task line: a short paragraph with no headings for a small PR; otherwise general-to-specific sections (🎯 problem → 🔧 fix → 🧭 impact → 🧩 how the pieces fit → 🔍 details → ✅ testing → ⚠️ worth knowing), dropping empty ones, whose heading words state this PR's actual problem, fix or impact, never `### 🎯 The problem`. Write 🧩 whenever the PR adds a flow or changes how parts work together, even inside one module: one `flowchart TD` Mermaid diagram per changed level, with labelled arrows. ✅ testing gives results and what wasn't verified, not a run log. A repo's own template or documented format wins. If Phase 1b ran, the preview-data section carries its list.
- PR exists → the push updated the code, but check the title/description still tell the truth: if the work drifted since they were written (rebase, review rework, scope change, a referenced PR merged), run the **pr-polish** skill — a stale description misleads whoever reads it next.

**The body carries the review evidence.** Moving the review off the PR removes the only public record that one happened, and a human arriving at this PR has no way to tell a reviewed branch from an unreviewed one. Under **✅ Testing**, state it plainly (a small PR without headings says it in a sentence or two): the rubric the loop used, how many rounds it ran, how many findings it fixed and refuted, and what gate passed. Then, under **⚠️ Worth knowing**, an **Open questions** list — one line per `handed up` entry in `open[]`, naming the decision rather than describing a problem. Key it on those specifically: `open[]` also carries deliberately-`left` nits and, after a `--no-fix` run, `proposed` ones, so a section triggered by "non-empty" would open with a heading and nothing under it. Put the rest under ⚠️ as follow-ups — including every `out-of-diff` finding, which belongs there and never under Open questions: it is not a decision about this change, and listing it as one invites the next reader to ask why the PR didn't fix it.

On the Phase 3 inline-fallback path there is no `open[]`: say "inline fallback, one round" and list what that round handed up directly.

Under `--review-rounds 0` there is no run directory at all — no `state.json`, no `report.md`, nothing to read. Don't hunt for one, and don't leave the section out: say plainly that **no local review ran**, that the caller asserted they had reviewed the work themselves, and that the merge is therefore left to a human. That sentence is the most useful thing in the body on such a run, because it is the only signal a later reader gets that this diff was never independently read. That list is the most useful thing in the body for the person who reviews next.

Everything in that section is published text and passes the Phase 2b gate first: quote no client identifier into a public PR body just because a reviewer's finding mentioned one.

Save the PR number to `.context/deliver/pr-number`.

**An existing PR's base is not yours to change.** If its `baseRefName` differs from `BASE_REF` — a stack re-run after the parent landed and the forge retargeted the child, or a `--base` that disagrees with what is on record — report the mismatch and continue against the base the PR already has. Retargeting silently changes what every approval and every review comment on that PR applied to; only a human may decide that. (Deliver to a level's rebase-and-prove is the one exception: the owner's approval covers that retarget.)

### 5b. Tracker — the work is now up for review

Skip entirely if the repo documents no tracker vocabulary (see Project specifics).

Resolve the task from the PR body's task line — the repo's own convention (`Closes X` / `Part of X` / `Relates to X`). Then, in one fetch of that task:

- **Assigned to someone other than the user you're working for → touch nothing.** Report it in Phase 8. You don't know what that person is doing with it.
- Still in a *not started* state → move it to *in progress*, then to *in review*. A pushed branch with a PR is unambiguously both; there's no point recording only the later one.
- Already in *in review* or a terminal state → leave it.

Move the task named by `Closes`. A `Part of` / `Relates to` task belongs to work wider than this PR — leave those alone at every phase.

### 6. Handle CI failures

Wait for CI as **Waiting on CI** (below Phase 8) says. Its result reads like `gh pr checks <N> --watch` output, and is checked the same way:

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

**Under `--review-rounds 0` there is no re-review** — Phase 3 was skipped, so there is no invocation to repeat and no `reviewed_oid` to invalidate. Fix CI as normal, and name the fix in Phase 8 as code no reviewer has read. The rest of this paragraph applies only when Phase 3 actually ran.

**A CI fix that changes shipped behaviour goes back through Phase 3.** Green checks are not a review: such a fix carries code no reviewer has read, on a `reviewed_oid` for the old HEAD, and Phase 7 will refuse it. Re-run **Phase 3's invocation verbatim** — `--base` and `--gate scoped` included; a bare `review-loop` picks up that skill's standalone defaults, which means the repo's whole check set (hard rule 3) and a base re-derived from config (wrong on a stacked run). It resumes its ledger rather than starting over, so the pass is cheap and dedupes against everything already raised. A test-only, snapshot or workflow fix that changes no shipped behaviour keeps the direct path.

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

**Read the review body as well as the inline comments.** A bot review folds findings into a `<details>` "Suppressed comments" block, and a body reading "Comments generated: 0" routinely sits above three to five of them — so the two API calls above are not the whole round. This matters most on exactly the path that skips the rest of this phase: plenty of repos have a bot reviewing automatically on open, with no request from anyone, so a `deliver` run that never sets `reviewer` still finds a review waiting here. Reading only the inline comments calls such a review clean and merges over it.

**The verdict header is not a finding either.** 🟡 counts unresolved threads, so a PR whose fixes are all pushed stays yellow; 🔵 on a broad change means a human should read it, and no code fix turns it green. Judge by the findings.

Someone who took the time to comment gets an answer, and an unresolved actionable thread blocks the merge regardless of who left it or whether anyone requested them. Run each finding through the same discipline Phase 3's loop uses — verify it before touching code, fix what holds, reply on the thread, resolve it; reply with the reason and resolve when it doesn't hold; leave it open and hand it up when it's a judgement call. This runs on every invocation, including the ones where the rest of this phase is skipped.

**If `review-loop` is not installed** — the case Phase 3 handles — neither part of this phase's loop is available. The *always* branch above still runs; do it by hand, it is only the two reads plus the reply-and-resolve discipline. Skip the bot round and record it as not run; Phase 7 treats a missing on-record review as non-blocking. At Deliver to a level's review request (step 8), request the human directly: take the login from the `reviewers` knob, or the most frequent reviewer of recent merged PRs excluding the author, then `gh pr edit <N> --add-reviewer`.

**Conditionally: put a bot's review on the record.** Run this when the `## Skill profile` sets **`reviewer`**, or when the run carries `--bot-review`. Skip it when the profile sets nothing, or the run carries `--no-bot-review`. Skipping is the common case and is not a gap: Phase 3's review is recorded in the PR body, and Phase 7 requires it to have covered HEAD.

```
review-loop --source bot --pr <N> --base "$BASE_REF" --gate scoped
```

`--gate scoped` for hard rule 3's reason — that skill's default is the repo's *whole* check set, which is the full suite CI is already running on this PR.

**If Phase 5 reported a base mismatch, pass the PR's own `baseRefName` here instead of `BASE_REF`.** Phase 5 continues against the base the PR already has; a review diffed against a different ref would reply to threads on a diff nobody is looking at — and after a stack's parent lands, `BASE_REF` may name a branch the forge has deleted.

It requests the bot, polls for a review of *this* HEAD, reads the inline comments **and** the ones the review body folds away, verifies each finding before spending a code change, fixes, replies, resolves, and caps itself at 3 rounds (5 while blocking findings keep arriving). It updates the same `state.json`, so Phase 7 reads one file whichever sources ran.

Two things belong to this skill, not that one:

- **The confidentiality gate applies to every reply *and every commit* posted here** — by the loop or by you. A thread reply is published text on a possibly-public PR, and the `bot` source pushes its own fix commits for up to five rounds. If the Phase 2b gate fired, re-run its `$TERMS` scan over what this phase added before it goes out, for the reason Phase 4 gives. (Only if it fired — `TERMS` is set inside that branch, and an unset one makes `grep -inE "$TERMS"` match every line of the diff.)
- **A bot that never answers is not a blocker on its own.** `sources.bot.exit: awaiting-review` means the *record* is missing, not that the change is unreviewed — Phase 3's review still stands, and Phase 7's conditions decide what that's worth.

### 7. Ready — and the Deliver ask

This phase never merges. It decides whether the PR is `ready` and hands the decision of how far to deliver it to the owner, as [the Deliver ask](#the-deliver-ask). A merge happens only on their click, through [Deliver to a level](#deliver-to-a-level). **The assessment is the truth about the PR:** report `ready-for-review` only when every condition below holds, otherwise `awaiting-CI` or `blocked`, naming what blocks. Reporting ready-for-review unconditionally is how an exhausted review budget with open findings, or a red pipeline, reaches a human as "done".

`ready` condition (ALL must hold):

- **A review ran at all.** `--review-rounds 0` skipped Phase 3, so this condition fails by construction. **Keep evaluating the rest**: an unresolved thread, a red pipeline or an open parent PR still decide whether this reports `blocked`, `awaiting-CI` or `blocked-on-parent-PR`, and the report and the ask must name the skipped review either way. Nothing substitutes for it: green CI is not a review, and neither is the author's word that they read it themselves. A click on such a PR runs the review first. AND
- **The review covers what is on the branch now.** `sources.local.exit` is `converged` — that is the review this skill always runs, so it is the one that must have finished, not merely "some source did". And `sources.local.reviewed_oid` equals HEAD, or has HEAD's patch-id (a rebase that left the diff alone), or every commit since it is one this run made that `review-loop`'s equivalence rule covers: a fix made in response to a finding, or a CI fix that changes no shipped behaviour (a lint autofix, a snapshot update, a workflow tweak). Inside a run you know which commits are which; a re-invocation does not, so commits after it that this run didn't make are unreviewed code and report `blocked`.

  `budget-exhausted` on **`sources.local`** reports `blocked` — that is the review this skill always runs, and its cap ending without convergence never lowers the bar. On `bot` it is reported, not blocking: the loop stopped asking a bot, which says nothing about the change that Phase 3's review and the open-threads condition below don't already answer. `awaiting-review` never blocks on its own either (Phase 6b says why). Judge the change by what is open, not by which source ran out of patience. AND
- **No blocker or major sits open in `state.json`'s `open[]`**, and no actionable review thread on the PR is unresolved — whoever left it. AND
- **Nothing is stacked on top of this PR's base** — that is the precise question, and "the base is the default branch" only approximates it: plenty of repos ship through a release or integration branch, and such a repo could never deliver under that rule.

  ```bash
  BASE=$(gh pr view <N> --json baseRefName --jq .baseRefName)
  DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
  # A PR onto the default branch cannot be stacked — skip the query entirely.
  [ "$BASE" = "$DEFAULT" ] || gh pr list --state open --head "$BASE" --json number,url
  ```

  The short-circuit is load-bearing, not an optimisation: `--head` matches on branch *name* and includes cross-repository PRs, so one open fork PR whose head branch is called `main` would otherwise mark **every** PR in the repo as stacked.

  A hit means the base is itself an open PR waiting to land. Merging into it folds this work into that PR, enlarging a diff someone is mid-review on, and ships nothing. Never retarget the base yourself. (Deliver to a level's rebase-and-prove is the one exception: the owner's approval covers that retarget.) On a `--base` run this hit is the designed outcome, not an accident: a stack merges bottom-up. Report it as `blocked-on-parent-PR` with the parent's number — a healthy stack waiting its turn, not a failure — and still open the ask: its buttons carry `--parent`, and a click waits for the parent to land. AND
- **QA evidence is on the head** when the PR carries `needs-qa` ([Proof](#proof)). This skill doesn't run QA; without the evidence, report `blocked: needs QA evidence`. AND
- All CI checks on the PR are green (`gh pr checks <N>` — wait for them as **Waiting on CI** says, and resolve any `[FAIL]` against the head commit's check-runs per Phase 6 before calling it red), AND
- **The remote carries what you reviewed and fixed:**

  ```bash
  [ "$(git rev-parse HEAD)" = "$(gh pr view <N> --json headRefOid --jq .headRefOid)" ]
  ```

  A squash merge ships the branch GitHub holds. An unpushed fix is not delivered, it is lost — and because CI and the reviewer both read the remote, every other condition above would have gone green on the code *without* it. Push, let CI settle, then re-evaluate.

Then read the [levels](#levels) for this PR and open or update [the Deliver ask](#the-deliver-ask): with buttons when the PR is `ready` (or only waits on its parent), with what blocks when it is not. In a repo that delivers through [its own skills](#project-specifics--read-these-first), skip the ask and name that pipeline instead.

### 7b. Tracker — close the task

Only once the merge has actually succeeded, and only for the task named by `Closes`: move it to the *done* state. Same guard as 5b — never a task assigned to someone else.

If the PR only says `Part of` / `Relates to`, or the merge didn't happen, leave the task where 5b put it and say so in Phase 8. Never set an *abandoned* / *cancelled* / *won't do* state from this skill; that's a human judgement, not a consequence of a merge.

Acceptance criteria the merge can't prove (something observable only in a deployed environment) are yours to check *before* moving the task, not to assume. If you can't check them, leave the task in review and say what's outstanding.

### 8. Report

Final message to the user must include: PR URL; the base it targets whenever that isn't the default branch (name the parent PR it stacks on); status (ready-for-review / delivered to `<level>` / awaiting-CI / awaiting-review / blocked-on-parent-PR / blocked); **the levels read** and where each came from; each step skipped on proof, with the proof it reused; the Deliver ask, or why there is none; **the review loop's result** — rubric, rounds, fixed, refuted, and its `exit`, or "no local review ran (`--review-rounds 0`)" when it was skipped; what it handed up, in full, since those are decisions waiting on the user; whether Phase 6b ran and what came back; the tracker task and the state you left it in (or why you didn't move it); and any thread you left unresolved, with why.

The handed-up findings are the part a reader most needs and most easily loses. List them as decisions, not as a summary of a summary.

## Waiting on CI

Every CI wait in this skill goes through here: Phase 6, Phase 7's green check, and Deliver to a level's steps 6 and 9 (a deploy run is waited on the same way). A wait costs nothing while it blocks. Each *wake* does cost, because a wake re-reads the whole conversation. A delivery session often carries a few hundred thousand tokens, so a wait that wakes the agent every minute can cost more than the CI run it watches. One wake when CI settles is the goal.

1. **Hand the wait to a subagent when the host has them.** Start one in the foreground on the host's cheapest model (in Claude Code: `model: "haiku"`), with this brief and nothing else:

   > Wait for CI on PR `<N>` in `<SLUG>`, head `<sha>`. Set every shell call's tool timeout to 600000 ms. First wait for a check to exist, since `gh pr checks --watch` exits at once while none is registered, which is normal for up to a minute after a push. Run this as one command: `for i in $(seq 20); do n=$(( $(gh api repos/<SLUG>/commits/<sha>/check-runs --jq .total_count) + $(gh api repos/<SLUG>/commits/<sha>/status --jq .total_count) )); [ "$n" -gt 0 ] && break; sleep 30; done; echo "$n"`. If it prints `0`, stop. Otherwise run `timeout 540 gh pr checks <N> --repo <SLUG> --watch --interval 30` and repeat it while checks are pending, for at most 45 minutes; if `timeout` is not installed, run the same command without it. Before each repeat, read `gh pr view <N> --repo <SLUG> --json headRefOid`. Never use a background job or anything that wakes you later. Reply with one line only: `green <sha>`; `failed <sha>:` followed by `<check> <run-id>` for each failing check; `no-checks <sha>`; `head-moved <new-sha>`; or `timeout <sha>`.

   The reply is the only thing that enters your context. Treat a `failed` as Phase 6 treats a `[FAIL]`: confirm it against the head's check-runs before acting on it.
2. **Without subagents, wait in the foreground yourself.** Run the same commands as the brief, each as one blocking call with the tool timeout raised to 600 s (Claude Code's Bash tool defaults to 120 s and kills anything longer). The `sleep` inside the first-check loop is fine there: the whole loop is one call and one wake. Never move the wait into a background job, and never use a timer or a separate call per poll that wakes you. Each such wake is a full turn.
3. **A host's PR notifications are not the wait.** Some hosts tell the agent when a PR's checks change (Paseo's asks tool, for one, with `subscribe: true`). Don't end your turn to wait for that message. It polls on its own schedule, does not say which commit passed, and stays silent when a fast run after a push ends in the same state as the run before. If a message like that arrives for a head you have already settled, it is a duplicate: note it in one line, without re-reading the PR.

## Hard rules

1. **Never `--no-verify`, never `--no-gpg-sign`.** If a pre-commit hook fails, fix the root cause.
2. **Never push to the default branch.** This skill operates on a feature branch only.
3. **Never run a full test suite locally** — not full e2e, not full unit/integration. Targeted runs only; CI owns full suites. This is why Phase 3 passes `--gate scoped`.
4. **Never merge without CI green.** Even with `--admin`, wait for `gh pr checks` to be green. Bypassing required reviews is one thing; bypassing failing CI is not.
5. **Never merge on a review that didn't cover this change.** "A review happened" and "a review of this code happened" are different facts, and only the second may gate a merge. `sources.local.reviewed_oid` is the one that counts — the fresh-context review's own coverage, not the newest HEAD some source happened to look at — at HEAD or at a head with the same patch-id. The owner's click never stands in for the review: with no proof of one, the review runs.
6. **Never publish a client's non-public details** into a public repo or one owned by anyone but that client — not in the diff, the commit messages, the PR body, or a review reply. See the Phase 2b gate. It's the one failure here a later commit can't undo.
7. **Don't expand scope under cover of review feedback.** If a finding asks for a refactor beyond the PR's purpose, it comes back handed up — carry it to the user, don't build it.
8. **Re-invoke `review-loop` only for a reason a phase names** — Phase 6's behaviour-changing CI fix is the one. Never re-invoke a source that came back `budget-exhausted` hoping for a different answer: that count resumes by design, and past the cap the answer is a human. A source that *converged* gets its budget back, because what brings you here is new commits and they deserve the same scrutiny the first pass got. The cap never relaxes Phase 7's conditions either way.
9. **A verdict header is not a finding; a folded one is.** Read the review body's suppressed comments alongside the inline ones, ignore the colour, verify before fixing, and never re-request a bot to turn 🔵 into 🟢. This applies whenever a PR carries a review — including the common case where a repo's bot reviews on open and nobody requested it.
10. **Follow the repo's dev-server/port convention** when you start a service for a local test. Don't auto-launch a whole-stack dev script.
11. **Never move a tracker task that belongs to someone else**, and never move one to *done* on anything but a successful merge of a PR that says it closes it. A wrong status is worse than a stale one — it's read as a fact by people who weren't in this session.
12. **Never merge or promote without the owner's click** naming the PR and the level, in this session. Without a click, stop at `ready`; a small or green change is no exception.
13. **A hard stop is never overridden** — `do-not-merge`, `blocked`, `qa-failed`, a `CHANGES_REQUESTED` review by anyone but the clicker, an unresolved human thread. Report it and ask again once it clears.
14. **Never deliver past a repo's own delivery skills.** Where the repo routes PRs through its own pipeline, the merge and promotion are that pipeline's.
