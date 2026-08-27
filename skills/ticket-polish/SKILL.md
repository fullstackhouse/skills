---
name: ticket-polish
description: Restructure a tracker ticket that has grown hard to read — pick the body shape its situation calls for (problem-first when the ticket is the only record of the problem, hub when a spec or sibling artifact carries it), collapse accreted sections and parallel numbering, compress history to the reasoning that must survive, guarantee a checkable DoD of only the remaining work, and re-true the title. Form only, facts unchanged — runs ticket-refresh itself first when the body's facts have gone stale. Use when a ticket has accreted through refreshes or scope changes, reads as a journal, opens mid-plan with no statement of what's actually broken, has nothing anyone can check off, or someone says "this ticket got complex — clean it up" or "this reads strangely". Args: a ticket URL/ID, or nothing to use the current branch's PR task line.
---

# ticket-polish

You are running the **ticket-polish** skill. Goal: make a ticket readable top-down again, so the next person to open it can tell within one screen what is broken and what is left, and meets history only where it still earns its place.

This is `pr-polish` one artifact over, and `ticket-refresh`'s complement: refresh makes a body *true*, polish makes it *legible*. A ticket that has survived several refreshes is usually accurate and unreadable at once — every correction landed in the right paragraph, and the paragraphs no longer add up to a shape.

Most of the work is subtraction. The exception §4 makes explicit: a body can also be illegible because it is **missing** the two things that make a ticket judgeable — a problem and a Definition of Done. Adding those is this skill's only licence to grow a body.

**Scope: body, title, and one comment.** Never change Status, Assignee, Priority, or dates — propose them. **Never change facts** — when they've gone stale, §2 runs `ticket-refresh` to correct them *before* any restructuring, and the same applies to a claim that only starts to smell mid-polish. Polishing wrong facts makes them more convincing.

No confidentiality gate here: this writes to the team's or the client's own tracker, not to anything public.

## 1. Resolve the ticket

As in `ticket-refresh` §1: explicit URL/ID → use it; nothing given → the current branch's PR body task line; the tracker and how to reach it from the repo's `## Skill profile` (`tracker`).

## 2. Gate: are the facts current? Refresh them if not

A polish rearranges; it must not launder. Two checks:

- **Age.** The body's own "checked on …" stamp — missing, or more than **12 hours** old → stale. A date-only stamp (what runs before this convention wrote) can't answer a same-day question: anything but today's date is stale, and today's falls through to the spot-check.
- **Spot-check.** Two or three state assertions, one `gh pr view` / tracker fetch each. Anything contradicted → stale, whatever the date says.

Twelve hours is deliberately short: it makes refreshing the **default path** and proceeding the exception. A ticket accreted enough to be worth restructuring has almost always sat long enough for its linked PRs to move, and the cost of the refresh is small against restructuring around a claim that turned false overnight. In practice only a body refreshed earlier the same working session skips it.

**Stale → run `ticket-refresh` on this ticket now**, in the same run, and polish what it returns. Don't invert the order: refresh edits in place at constant size, so restructuring first only means reshaping claims that are about to change.

Two amendments while it runs as this gate — it posts **no comment of its own** (§5 folds both halves into one) and **no separate report** (§6 carries it). Everything else runs unchanged: the full claim sweep, closed PRs followed to their successors, upstream fixes checked against the installed version, the checked stamp set to now.

**Fresh → proceed**, carrying the checked stamp through unchanged: polishing is not checking.

## 3. Diagnose the decay

Read the whole body — and the comment thread, which often holds structure the body should have absorbed — then name what the body suffers from. Accretion produces recurring shapes:

- **Parallel numbering systems.** "Items 1–3" (the proposed changes) running against "instances 1–5" (the bugs) with a non-obvious mapping between them. The cross-referencing is most of the felt complexity. Collapse to **one canonical enumeration**, usually a table with a current-state column.
- **History told as narrative.** A saga of PRs taken over, republished, merged — kept because each step was once news. Compress each resolved thread to the *reasoning that must survive*: why a rejected approach must not be re-raised, why a counter-intuitive state is correct. The mechanics (who, which PR, when) shrink to a citation.
- **Trailing accretion.** "Also, since then…" bullets appended below the structure they belong inside. Fold them in.
- **Buried lede.** Open work sitting below screens of closed history. Invert: **what's left leads**, resolved items follow as compressed context.
- **Opens mid-plan.** The body starts at "one task, two steps…" and nothing in it — or under any live link — says what is broken. The reader is asked to agree to a solution before meeting the problem. Usually a body written as a hub (§4) whose upstream artifact was retired or absorbed, taking the problem statement with it. This is the one decay shape whose repair is *adding* text.
- **Missing or stale DoD.** Nothing to check off, or a "Done when" mixing satisfied, obsolete, and open conditions. Rewrite it as a short numbered list of only the remaining work, each condition independently verifiable; conditions owned by sibling tickets point there instead.
- **Title drift.** Counts, scope, or framing the body has outgrown ("3 bugs" over a table of five). Re-true it.

## 4. Rewrite

### Pick the shape first

One test: **is there a linked artifact — a spec, RFC, design doc, brief, or parent ticket — that states the problem and the reasoning, and is it still live?**

- **No → the originating body.** This ticket is the only record of the problem, so it opens with one: problem → approach → what's left → why it's scoped this way → evidence → Done when → references. Skeleton: [`templates/originating.md`](./templates/originating.md).
- **Yes → the hub body.** Restating the problem forks it, and the fork rots. Open with the link and track progress instead: what this tracks → what belongs here → steps → open questions → implementation history. Skeleton: [`templates/hub.md`](./templates/hub.md).

A ticket **changes mode** when its upstream artifact is retired, absorbed, or closed. That is the usual cause of a body that opens mid-plan (§3) — it was a correct hub until the thing it hubbed onto went away. Check the link before trusting the shape: an artifact that has been parked is not carrying the problem any more.

### Two invariants, whichever shape

1. **The problem is stated somewhere** — in this body, or one click away under a link you have confirmed is live. Never nowhere.
2. **A checkable DoD exists** — `Done when` in an originating body, the `Steps` checkboxes in a hub body. **Never both**; two lists of remaining work is the parallel-numbering decay of §3 rebuilt by hand.

### Budget

An accreted body should shrink, often by half. If the polish doesn't reduce size, question whether it was needed.

**Never pad — one exception:** a missing problem statement and a missing DoD are always added. They are the *only* sections this skill invents; a ticket without them can't be judged or closed, so supplying them is repair, not padding. Everything else in the skeletons is optional and gets deleted when the body doesn't need it — a three-line ticket stays three lines.

### Writing rules

As `pr-polish` §4, one artifact over:

- **Each section stands on the ones above it.** A reader who stops early is left with a correct picture, just a less detailed one.
- **No code identifiers in the problem statement** — a non-engineer reads that section. Identifiers belong below it.
- **No journal narration** ("an earlier revision…", "after review we…") except where it changed the direction and a future reader needs the lesson — then one tight paragraph.
- **No strikethroughs, no "edit:" patches.** Rewrite the paragraph; the tracker keeps page history.
- **Headers only when the body needs them.** Empty headings under a two-sentence ticket are the cruft this skill removes.
- **A full-body replace is appropriate** — unlike a refresh, restructuring *is* the job — but only after you have read the entire body; anything you didn't read, you're about to delete.
- **Keep every link, in fewer words**, and keep the checked stamp at the foot — it is provenance, not a lede.

## 5. Comment and comment hygiene

Post **one short comment** (per `ticket-refresh` §6): what was restructured, and — **only if the gate found the body fresh** — "no facts changed; page history holds the long form". It points, never contains.

Refreshed at the gate? Then facts *did* change, and the comment may not say otherwise. Still **one** comment, leading with the corrections — which claim was wrong and why — because that's the half watchers are still carrying; the restructuring is a closing clause. Two comments for one run is how a thread stops being read.

Then look at the thread: record-comments fully superseded by the body are safe to resolve — propose that in the comment or report (most tracker APIs can't resolve; the human clicks).

## 6. Report

- **Whether the gate refreshed, and what it contradicted — first**, each with the evidence that overturned it. A reshaped body is a nicety; a corrected claim is news, and anyone who read the old body still holds the wrong one.
- **The shape, and whether it changed** — hub → originating means an upstream artifact stopped carrying the problem; name which one, because that is a fact about the project, not about the body.
- Before/after size and the one-line structural story ("dual numbering → one table; what's-left now leads; DoD 4 stale conditions → 2 open ones").
- Proposed Status / Assignee / title-convention changes needing a human.

## Hard rules

1. **Never change a fact.** Same claim, better shape. A polish that alters a state assertion has become an unverified refresh.
2. **Never delete evidence** — effects, measurements, repro steps, spec citations. Compress narration, keep findings.
3. **Never touch Status, Assignee, or Priority.** Propose them.
4. **Never polish over a stale body.** Gate first (§2), and refresh in the same run when it fails — never restructure a claim you haven't confirmed.
5. **One comment, pointing at the body** — never a summary long enough to become a second body.
6. **Never leave a body with no problem and no checkable DoD.** Those two are the only things this skill may add; everything else it rearranges, compresses, or deletes.
