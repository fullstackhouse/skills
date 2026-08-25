---
name: review-loop
description: Drive a change to "nobody finds anything anymore" — review, fix, then re-review with a reviewer that never sees why the fix was made, round after round, until N consecutive rounds come back empty. Use when asked to "review until it's clean", "loop the review until nothing's left", "harden this before I send it", or after a human review round on a change big or long-lived enough that each fix plausibly introduces the next finding. Works on the working tree, a branch, or a PR. Args: optional target (PR number / branch / nothing = current branch), --dry-rounds N, --max-rounds N. Local only — posts nothing, merges nothing.
---

# review-loop

You are running the **review-loop** skill. Goal: run review→fix→re-review until the change stops producing findings, and be honest about what that proves.

The naive version of this loop — review it, fix it, review it again — converges on the wrong thing. The context that wrote the fix knows why the fix is right, so its re-review checks the change against its own intent instead of against the code. It reliably catches self-contradiction and reliably misses whatever it never thought of. **The mechanism that makes this skill worth running is that the reviewer each round is a fresh context that never sees the fix rationale.** Everything else here exists to keep that loop terminating and cheap.

**Hard rule: local only.** Never push, never post a review or comment, never merge, never move a tracker task. This skill leaves a branch and a report; `deliver` ships it.

## Project specifics — read these first

This skill is repo-agnostic. Before phase 1, gather:

- **Check commands per package** — lint / typecheck / test / codegen, from the repo's `CLAUDE.md` / `AGENTS.md` / `package.json`, or the curated `## Skill profile` section if present. Fixes are verified with targeted runs of these, never full suites.
- **Repo rules a reviewer must apply** — the conventions, "Don'ts", tenancy/encryption rules and test doctrine in the repo's agent instructions, plus the `## Skill profile` **Review landmines** knob (perf-sensitive paths, known CI false-fails). These go into every reviewer prompt; without them the loop finds generic findings and misses the repo's own.
- **Specs location** — if the target adds or edits a spec, reviewers need the mandated sections and the sibling specs it must stay consistent with.
- **Scratch dir** — the profile's, else `.context/review-loop/` when a gitignored `.context/` exists, else `/tmp/review-loop-<slug>/`.

## Arguments

- **target** — a PR number, a branch, or nothing (default: the current branch's diff against its base, uncommitted changes included).
- **`--dry-rounds N`** — consecutive empty rounds required to exit. Default **2**.
- **`--max-rounds N`** — hard cap. Default **6**.
- **`--lenses a,b,c`** — override the default lens set (phase 2).

## Phases

### 1. Anchor the target and open the ledger

Resolve the diff once and record how:

```bash
# branch/worktree target
git merge-base HEAD "$BASE_REF" && git diff "$BASE_REF"...HEAD
# PR target
gh pr diff <N> && gh pr view <N> --json title,body,headRefOid,files,reviews
```

Create `<scratch>/<slug>/ledger.md`. It is the orchestrator's memory and the one artifact that survives re-invocation: target, base, and one row per finding — stable id, `path/file.ts:LINE`, the claim in the reviewer's words, status (`open` / `fixed` / `rejected` / `yours`), and for a rejected one, *why*.

**The ledger is never shown to a reviewer.** It contains rationale; rationale is the contaminant.

On a PR target, seed the ledger with the review comments already on it — human and bot, resolved threads excluded — as `inherited` findings. They enter the loop like any other finding: verified in phase 4, fixed in phase 5. A loop that ignores the review that prompted it is theatre.

### 2. Round — fan out blind reviewers

Launch one read-only subagent per lens, concurrently. Default lenses, each a genuinely different failure mode rather than the same reviewer three times:

1. **Correctness & data** — wrong results, lost writes, unhandled states, unbounded queries, concurrency.
2. **Security & tenancy** — authz, cross-tenant reads, secrets, injection, what leaves the machine.
3. **Tests** — would each new test fail against the pre-change code? Is a required path untested? Is a mock asserting itself?
4. **Repo conventions** — the instructions gathered above, applied literally.
5. **Claims vs code** — does the doc / spec / PR body / commit message describe what the diff actually does? On a docs- or spec-shaped diff this lens does the heavy lifting: check every internal cross-reference the document makes against the document's own other sections.

Each prompt carries: the diff, the repo rules, the target's genre, read access to the repo, and the **open** findings from the ledger as bare `file:line` + claim, so the same thing isn't re-litigated. Each returns findings as severity + `path/file.ts:LINE` + the claim + the evidence that establishes it + a suggested direction, or `None.` with a list of what it checked.

**What the prompt must not contain**, in any paraphrase:

- why the current code is the way it is, or what a previous round changed and why;
- the round number, or that earlier rounds came back empty — "round 5, nothing since round 3" is an instruction to find nothing;
- rejected findings, or the reasoning that rejected them;
- this skill's name, or that a fix loop is running at all.

Write the prompt, then re-read it hunting for those five. A leaked sentence doesn't bias the round slightly — it converts an independent pass back into the self-review this skill exists to replace, while still costing a full round.

### 3. Triage — dedupe against everything ever seen

Match each finding against the ledger by `(file, nearest stable anchor, claim)` — not by wording, which changes every round. Anything already there is dropped, **including findings previously rejected**.

That inclusion is the whole trick. Dedupe against only the *fixed* list and every rejected finding returns next round from a reviewer that has never heard the argument against it, and the loop runs to `--max-rounds` every time. The rejection is a decision; the ledger is where a decision is kept.

What survives is this round's **fresh** findings.

### 4. Verify — one skeptic per fresh finding

Spawn one subagent per fresh finding whose job is to **refute** it: read the surrounding code and establish that the claimed failure cannot happen. Instruct it to answer *refuted* when it cannot decide.

That default is deliberate. An unverified finding costs a code change, and a code change to satisfy a finding that was never real is how a hardening loop makes a change worse. Cheap to run, and it's what keeps rounds 3+ from being fix-work on plausible prose.

- **Confirmed** → phase 5.
- **Refuted** → ledger, status `rejected`, with the refutation. Never raised again.
- **A judgement call** — a design disagreement, a scope question, a trade-off the repo hasn't decided — → ledger, status `yours`. Not fixed, not silently dropped. These are the user's, and phase 7 hands them over.

### 5. Fix — narrowest correct change, and a test that fails first

Per confirmed finding: fix at the layer the defect is at, add the regression test where the repo puts them, and check that it fails against the pre-fix code. Run the targeted checks for the files touched — never a full suite.

One commit per round, subject naming what the round fixed. The round structure stays legible in the history, which is what makes the report checkable later.

Do not widen scope under cover of a finding. A finding that can only be fixed by a refactor beyond this change's purpose is a `yours`, not a fix.

### 6. Loop control — dry rounds, not a fixed count

Repeat from phase 2. **Exit when `--dry-rounds` consecutive rounds produce zero fresh confirmed findings.**

A single empty round is not convergence — it's one sample from a non-deterministic reviewer. A fixed iteration count is worse: it stops wherever the counter runs out, which is uncorrelated with whether the change is clean. Real curves decay (3 → 3 → 1 → 0 → 0); a cap of 3 would have cut that one off before the decay was visible, and a one-dry-round exit would have called it at the first zero.

Stop early and hand back when:

- **`--max-rounds` is reached** — report the curve; a curve that isn't decaying by then means the loop isn't the right tool.
- **A finding returns after two fixes.** The fix is wrong, or it isn't a defect but a disagreement. More rounds won't settle it.
- **A round's findings are all `yours`.** Nothing left that a fix can act on.
- **The rounds are rewriting the change rather than correcting it** — the diff is being redesigned under the loop's cover. Stop and run `zoom-out`.

One carve-out to the exit: **a round that changed a security boundary** — auth, credentials, a trust or permission decision, what a sandbox allows, what leaves the machine — always earns one more round, even at the cap. Every other class of miss can be corrected by a follow-up commit; that one is exposed the moment it merges.

### 7. Report — the curve, then the claim

- **Findings per round**, as a table: round, lenses that fired, fresh / confirmed / rejected. The shape of the decay is the result; a reader who sees `3 → 3 → 1 → 0 → 0` learns more than one who reads "converged".
- **Fixed**, one line each with the commit.
- **Rejected**, with the refutation — so the next reviewer doesn't spend the finding again.
- **Yours** — the judgement calls, stated as decisions to make, not as work to do.
- **The claim, exactly as strong as it is:** *N consecutive independent passes under these lenses found nothing.* Not *this change is clean*, and not *a reviewer will find nothing*. Name the lenses that ran and anything they structurally can't see (no browser, no production data, no runtime). On a change that has already had human review rounds each finding something new, say so — it's the honest prior on what round N+1 by a human would turn up.
- **Next step**: `deliver` to ship it, `review-queue` if someone else's eyes are the actual gate.

## Hard rules

1. **The reviewer never sees the rationale, the round number, or the ledger.** A leaked hint invalidates the round — rewrite the prompt rather than caveat the result.
2. **Dedupe against every finding ever seen, rejected included.** Otherwise the loop cannot go dry.
3. **Never fix an unverified finding.** Refutation is cheaper than the change it prevents.
4. **Nothing is posted, pushed, or merged** — not a comment, not a thread resolution, not a tracker move.
5. **Never widen scope under cover of a finding.** Beyond this change's purpose is a `yours`.
6. **A dry round is earned, not declared.** `None.` without a list of what was checked is a failed round — re-run that lens.
7. **Never run a full test suite.** Targeted runs on touched files; CI owns the rest.
8. **Report the curve, never just the verdict.** A loop that stopped at the cap, or on a disagreement, says so — "clean" and "out of rounds" are different outcomes and only one of them is finished.
