---
name: ticket-polish
description: Restructure a tracker ticket that has grown hard to read — collapse accreted sections and parallel numbering into one state-first body, compress history to the reasoning that must survive, rewrite the Done-when as a short checkable DoD covering only remaining work, and re-true the title. Form only, facts unchanged — run ticket-refresh first if they aren't current. Use when a ticket has accreted through refreshes or scope changes, reads as a journal, or someone says "this ticket got complex — clean it up". Args: a ticket URL/ID, or nothing to use the current branch's PR task line.
---

# ticket-polish

You are running the **ticket-polish** skill. Goal: make a ticket readable top-down again, so the next person to open it gets the open work in the first screen and meets history only where it still earns its place.

This is `pr-polish` one artifact over, and `ticket-refresh`'s complement: refresh makes a body *true*, polish makes it *legible*. A ticket that has survived several refreshes is usually accurate and unreadable at once — every correction landed in the right paragraph, and the paragraphs no longer add up to a shape.

**Scope: body, title, and one comment.** Never change Status, Assignee, Priority, or dates — propose them. **Never change facts.** If a claim looks stale mid-polish, stop and run `ticket-refresh` (or say so) before restructuring: polishing wrong facts makes them more convincing.

No confidentiality gate here: this writes to the team's or the client's own tracker, not to anything public.

## 1. Resolve the ticket

As in `ticket-refresh` §1: explicit URL/ID → use it; nothing given → the current branch's PR body task line; the tracker and how to reach it from the repo's `## Skill profile` (`tracker`).

## 2. Gate: are the facts current?

A polish rearranges; it must not launder. Check the body's own "checked" date and spot-verify two or three state assertions (one `gh pr view` / tracker fetch each). Anything contradicted → this is a refresh-then-polish job, not a polish. Fresh enough → proceed, and carry the checked date through unchanged: polishing is not checking.

## 3. Diagnose the decay

Read the whole body — and the comment thread, which often holds structure the body should have absorbed — then name what the body suffers from. Accretion produces recurring shapes:

- **Parallel numbering systems.** "Items 1–3" (the proposed changes) running against "instances 1–5" (the bugs) with a non-obvious mapping between them. The cross-referencing is most of the felt complexity. Collapse to **one canonical enumeration**, usually a table with a current-state column.
- **History told as narrative.** A saga of PRs taken over, republished, merged — kept because each step was once news. Compress each resolved thread to the *reasoning that must survive*: why a rejected approach must not be re-raised, why a counter-intuitive state is correct. The mechanics (who, which PR, when) shrink to a citation.
- **Trailing accretion.** "Also, since then…" bullets appended below the structure they belong inside. Fold them in.
- **Buried lede.** Open work sitting below screens of closed history. Invert: **what's left leads**, resolved items follow as compressed context.
- **Stale DoD.** A "Done when" mixing satisfied, obsolete, and open conditions can't be checked. Rewrite it as a short numbered list of only the remaining work, each condition independently verifiable; conditions owned by sibling tickets point there instead.
- **Title drift.** Counts, scope, or framing the body has outgrown ("3 bugs" over a table of five). Re-true it.

## 4. Rewrite

Top-down, general to specific, exactly as `pr-polish` orders a PR body: what this is → what's left → why the closed things are closed → evidence → DoD.

- A full-body replace is appropriate here — unlike a refresh, restructuring *is* the job — but only after you have read the entire body; anything you didn't read, you're about to delete.
- **Budget:** an accreted body should shrink, often by half. If the polish doesn't reduce size, question whether it was needed. Never pad, never add sections.
- Keep every link, in fewer words.

## 5. Comment and comment hygiene

Post **one short comment** (per `ticket-refresh` §6): what was restructured, "no facts changed; page history holds the long form". It points, never contains.

Then look at the thread: record-comments fully superseded by the body are safe to resolve — propose that in the comment or report (most tracker APIs can't resolve; the human clicks).

## 6. Report

- Before/after size and the one-line structural story ("dual numbering → one table; what's-left now leads; DoD 4 stale conditions → 2 open ones").
- Anything that smelled stale during the gate — hand it to `ticket-refresh` rather than fixing it silently.
- Proposed Status / Assignee / title-convention changes needing a human.

## Hard rules

1. **Never change a fact.** Same claim, better shape. A polish that alters a state assertion has become an unverified refresh.
2. **Never delete evidence** — effects, measurements, repro steps, spec citations. Compress narration, keep findings.
3. **Never touch Status, Assignee, or Priority.** Propose them.
4. **Never polish over a stale body.** Gate first (§2); refresh-then-polish when in doubt.
5. **One comment, pointing at the body** — never a summary long enough to become a second body.
