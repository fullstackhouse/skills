# deliver: move the review local (drop the Copilot round-trip)

## Problem

`deliver` outsources its review to a GitHub bot: request → poll 10 min → read inline +
suppressed comments → fix → reply → resolve → re-request. Roughly half the skill (Phases
5, 6, 7, 7c, ~180 lines) is machinery for that round-trip: `submittedAt` vs `.commit.oid`
gates, `env.REVIEWER` jq quoting traps, quota-refusal detection, verdict-colour rules, a
3-vs-5 round budget keyed on a severity written to disk so a later invocation can
reconstruct a judgement. All of it exists because the reviewer lives on the other side of
a network boundary, reviews an old HEAD, and costs ten minutes per lap.

The repo already owns a better reviewer: `om-review-loop` — fresh-context subagents, a
ledger, refute-by-default verification, exit on N consecutive quiet rounds. Today
`deliver` uses it only as a warm-up (Phase 2c) and still defers to the bot.

## Change

Make the local loop **the** review, run **before** the push. Keep GitHub for what only
GitHub can do: CI, the PR, the merge, and a human's comments if a human leaves any.

## Plan

- [ ] Phase 2c + 5 + 6 + 7 + 7c collapse into a new **Phase 3 — Review (local, looped)**
  - [ ] OM repo (`.ai/agentic.config.json` + `om-code-review`) → delegate to `om-review-loop`
  - [ ] otherwise → same loop inline, rubric = built-in `code-review` skill, spec'd in
        `skills/deliver/references/review-loop.md`
  - [ ] budget: `--quiet-rounds N` (default 1), hard cap 3 rounds — replaces 7c's 3/5
  - [ ] loop state → `.context/deliver/review-<PR|branch>.json`: `reviewed_oid`,
        `rounds`, `quiet`, open findings, handed-up decisions
- [ ] **Phase 5 (PR body)** carries the review evidence — rounds, fixed count, refuted
      count, and the handed-up decisions as an "Open questions" list. Dropping the bot
      removes the only public record that a review happened; the body replaces it.
- [ ] **Phase 6b** — read whatever review threads already exist on the PR (human or an
      auto-running bot), verify, fix, reply, resolve. Read, never poll, never wait.
- [ ] **Phase 7 merge condition** — bot approval bullet → "the local loop converged at
      HEAD (or every commit since is one this run made under the 7c equivalence)"; keep
      CI-green, unresolved-threads, stacked-base, ≤100-lines-since-start
  - [ ] a required-approval block (branch protection, `ownerCanSelfMerge: false`) →
        request the human `reviewers` and report `awaiting-review`
  - [ ] `--no-merge` → request the human reviewers so a person actually sees it
- [ ] Behaviour-changing CI fix (Phase 6) re-enters Phase 3, not a bot re-request
- [ ] Hard rules: drop the verdict-colour/suppressed-comment rule, rewrite the round-budget
      rule, keep confidentiality / no-`--no-verify` / no-full-suite / CI-green
- [ ] Profile knobs: drop **`reviewer`** (bot login); keep **`reviewers`** (humans)
- [ ] Sync callers: `kickoff` (l.63 "reviewer request, the review-feedback loop"),
      `README.md` (skill table row, knob list l.120), `overnight` if it names the loop
- [ ] `plugin.json` 1.10.0 → **1.11.0** (minor: capability change)

## Decisions taken

1. Human reviewer requested **only when required** — `reviewDecision: REVIEW_REQUIRED` at the
   merge gate. Not in `--no-merge`; kickoff hands back a PR a human will open anyway.
2. Local loop defaults: `--quiet-rounds 1 --max-rounds 3 --gate scoped` under `deliver`
   (standalone defaults are 2 / 6 / full).
3. Copilot hatch kept — but as a **source of one shared skill**, not a second deliver.
   `review-loop --source bot`, switched on by the `reviewer` profile knob or `--bot-review`.

## Review

**Shipped as PR #60** — https://github.com/fullstackhouse/skills/pull/60 — **not merged.**

`deliver` 448 → ~370 lines; the review machinery it carried is now `review-loop`
(+ `references/bot-review.md`), shared and source-swappable. `om-review-loop` deleted.
Version 1.11.0 → 2.0.0 after merging main (a new `video-brief` skill had landed).

### The loop did not converge

Delivered through its own new procedure: 3 rounds of `review-loop --source local`,
3 fresh reviewer contexts per round, none told a loop existed.

| Round | Raised | Blockers | Majors | Fixed |
|---|---|---|---|---|
| 1 | 15 | 1 | 5 | 15 |
| 2 | 20 | 0 | 8 | 20 |
| 3 | 14 | 2 | 10 | 14 |

Flat, not decaying — each round's fixes opened new surface. Hit the 3-round cap with
round 3 still finding blockers, so `exit: budget-exhausted` → **`blocked`**, and Phase 7
forbids auto-merge. Left for a human, which is the rule working rather than failing.

The rounds justified the change: all three round-1 reviewers independently found that the
PR-attached sources poll the *remote* head while the skill forbade pushing — a bot round
would have merged the unfixed remote head and destroyed the local fix via `--delete-branch`.

### Verified

CI green (`version-bumped` pass; `[code]smith` *skipping*, not failing — the exact case
Phase 6 warns about). Version gate simulated, all README links resolve, every skill has a
table row, all `Phase N` cross-references resolve, no surviving `om-review-loop` reference,
confidentiality gate re-scanned over the whole branch on a public repo — clean.

### Handed up

- `skills/docs-audit/SKILL.md` frontmatter fails a strict YAML parser (unquoted colon in
  `description`). Pre-existing on main, out of diff — not fixed here.
- `.claude-plugin/marketplace.json` description has drifted from `plugin.json`'s.
- A 4th review round would very likely find more. The curve says so.

### Install

User-scope `fsh` was already at main (1.11.0, `eae2447`) via `autoUpdate`. The new skills
arrive when #60 merges and the version string moves to 2.0.0 — the exact mechanism
AGENTS.md describes. Nothing to do locally until then.
