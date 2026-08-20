---
name: kickoff
description: Take an idea, a brainstorm brief, or a ticket and drive it autonomously to a ready-for-review PR — decide the plan depth yourself (spec first, or straight to code), implement with tests, then run deliver in no-merge mode so local checks, the PR, the reviewer, and the feedback loop are handled. Use when asked to "kick off X", "start work on X", or turn an idea into a PR that's ready for review. Never merges.
---

# kickoff

You are running the **kickoff** skill. Goal: from an idea to a PR sitting **ready for review** — reviewer requested, feedback addressed, CI green — with the human's remaining job being the review and the merge decision, nothing else.

This is `deliver`'s front half's missing counterpart: `deliver` ships a branch that already exists; `kickoff` starts from nothing and stops where the merge decision begins.

## Project specifics — read these first

This skill is repo-agnostic. Gather from the consuming repo's `CLAUDE.md` / `AGENTS.md` (the `## Skill profile` section is the curated source):

- **Specs** — where feature specs live (repo directory + naming pattern, or a tracker/Notion location) and how deep they're expected to go. No knob → look for a discoverable convention (`docs/specs/`, `specs/`, `rfcs/`, `design/`); none → the plan embeds in the tracker ticket (when a Tracker is configured) or the PR description.
- **Tracker** — used to link the ticket that spawned this work; status moves are `deliver`'s job, not yours.
- **Check commands, reviewer, baseBranch** — all consumed by `deliver`; you don't need to re-derive them, but the implementation must follow the same repo conventions its checks enforce.

## Arguments

One of:

- **A brainstorm brief path** (from the `brainstorm` skill) — the richest input: its Resolved unknowns and Non-goals are decisions already made; don't re-litigate them.
- **A tracker ticket URL/ID** — read it; treat its body as the goal and its claims as claims.
- **A free-text idea** — restate the goal in one sentence before proceeding.
- **Empty** — ask what to kick off. Do not guess.

## Phases

### 1. Ingest & scope

Read the input and the relevant code. Write down: the goal in one sentence, the observable outcome that proves it works (define verification *before* implementing), known constraints, and open unknowns.

For each unknown: if the repo/docs/ticket can answer it, answer it there. If it's a **product decision that materially forks the work** and the input doesn't settle it, ask the user now — one batched round of questions, then proceed. Everything else: pick the reasonable default and **record the assumption** (in the spec or the PR description) instead of asking. The point of this skill is that the user fed in an idea and walked away.

### 2. Depth decision — spec or straight to code?

Go **straight to code** when a reviewer wouldn't want a design to react to: the change is small and local, its shape is obvious from the input, and naming the affected areas took no real work.

**Write a spec first** when any of these hold: multiple plausible approaches with different trade-offs; new module/service/schema boundaries; naming the affected areas took actual investigation; or the brief/ticket flags design risk. Put it at the Specs location (see Project specifics). Keep it lean — problem, chosen approach and the alternative it beat, affected areas, verification plan, recorded assumptions. Carry the brief's Resolved unknowns in verbatim; they are answers, not suggestions.

A spec that lives in the repo gets committed on the work branch, so it ships (and gets reviewed) with the implementation.

### 3. Branch

Never work on the default branch. If the current checkout is already an isolated feature branch/worktree dedicated to this task (e.g. a Conductor workspace), use it; otherwise create a fresh branch off the base branch with a conventional name.

### 4. Implement

Work the plan: implementation plus the tests that prove the Phase 1 verification, in the repo's own idiom (match surrounding code, comment density, naming). Commit in coherent Conventional Commits as you go — not one squashed blob, not thirty fixups. Respect the input's Non-goals: no gold-plating, no scope beyond the brief.

If mid-implementation the approach turns out wrong (the plan fights the codebase, sunk steps keep needing patches), stop and re-derive rather than grinding — the `zoom-out` skill exists for exactly this.

### 5. Deliver — no-merge mode

Invoke the **deliver** skill with `--no-merge`. It owns everything from here: scoped local checks, the confidentiality gate, push, PR open with a top-down body (link the source ticket; name the spec if one was written), reviewer request, the review-feedback and CI loops, and the tracker's move to *in review* — stopping with the PR ready for review instead of merging.

Do not reimplement any of that here, and never merge from this skill — not even when the diff is tiny and green. The merge decision is the human's by design.

### 6. Report

Final message must include: the PR URL and its state (ready-for-review / awaiting-CI / blocked, per deliver's report), where the spec or plan lives, **every assumption made in the user's absence**, and anything deliberately left out (non-goals honored, follow-ups worth filing).

## Hard rules

1. **Never merge.** Ready-for-review is this skill's terminal state; ignoring that turns kickoff into an unattended `deliver`.
2. **Never work on or push to the default branch.**
3. **Ask once, early, only for forking product decisions.** Everything else is a recorded assumption. An unanswerable blocking question mid-flight → park cleanly: commit, push, report what's blocked and why.
4. **Don't silently expand scope** beyond the brief/ticket; new ideas discovered en route become follow-up notes in the report, not extra diff.
5. **All publishing goes through `deliver`** — which enforces the client-confidentiality gate. Don't push or open PRs by hand around it.
6. **A brief's Resolved unknowns are decisions.** Re-opening them without new evidence wastes the conversation that produced them.
