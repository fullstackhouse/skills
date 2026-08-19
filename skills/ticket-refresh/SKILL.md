---
name: ticket-refresh
description: Re-verify a tracker ticket's body against reality and rewrite whatever no longer holds — resolve every PR/issue it links (following supersessions), check whether an "upstream" fix already ships in the version the repo installs, and correct claims the world has overtaken. Use when picking up an older ticket, before assigning or estimating one, or when asked "what's the status here / should this ticket be updated?". Args: a ticket URL/ID, or nothing to use the current branch's PR task line.
---

# ticket-refresh

You are running the **ticket-refresh** skill. Goal: make a tracker ticket's body true again, so the next person to open it can act on it without re-deriving its state.

This is `pr-polish` one artifact over: same job (a description that drifted from reality), different source of truth. There, the diff. Here, the outside world — merged PRs, superseded PRs, shipped releases, sibling tickets.

**Scope: the ticket's body, plus one comment recording what you changed (§6).** Never change Status, Assignee, Priority, or dates — propose those in the comment and the report, and let a human apply them. `deliver` owns moving a task's status along with its PR; this skill does not move anything. A wrong status is read as fact by people who weren't in the session.

No confidentiality gate here: this skill writes to the team's or the client's own tracker, not to anything public. If your findings need to reach a public issue, that's `upstream-pr`'s gate, not this one.

## 1. Resolve the ticket

- Explicit URL/ID → use it.
- Nothing given → the current branch's PR body task line (the repo's own convention: `Closes X` / `Part of X`). Several, or none → ask.
- Read the repo's `## Skill profile` (`tracker`) for which tracker and how to reach it (Notion MCP, Linear MCP, `gh issue`).

## 2. Extract every claim that can rot

Read the body and list, explicitly:

- Every link: PR, issue, commit, sibling ticket, spec.
- Every **state assertion** — "merged", "closed without merge", "no PR opened", "blocked on X", "still fails", "not yet filed".
- Every **dependency**: what this ticket says it waits on.
- Every acceptance criterion in its "Done when".

A ticket with a dated "checked on ..." section is not thereby current. That date tells you when someone last looked, not that nothing moved since. Re-verify it anyway — a stale section written in a confident voice is the most expensive kind.

## 3. Resolve each reference — follow the graph, don't just read state

`gh pr view <N> --repo <slug> --json state,title,mergedAt,closedAt,url,labels`, `gh issue view`, tracker fetches for sibling tickets.

Three traps, in the order they'll bite you:

**A closed PR is not a dead end.** Work gets republished, not abandoned: a maintainer takes it over, a fork push is rejected, a duplicate is consolidated. Read the closing comments (`gh pr view <N> --json comments`) for *superseded by*, *promoted upstream as*, *replaced by*, *continues in*, *closing in favour of* — then resolve the successor and report **that** state. A ticket that says "closed without merge" about a PR whose successor merged is telling the reader the exact opposite of the truth.

**A merged PR may have resolved the item by rejecting its premise.** Read the merged body for the *decision*, not just the green tick. If the ticket asked for X and upstream deliberately shipped not-X, that item is **obsolete, not pending** — and it must say so in as many words, with the reasoning. This is the single most valuable output of the skill: it's the case where the ticket actively sends the next person to redo rejected work.

**A merged fix upstream is not a shipped fix downstream.** For anything in a dependency, check all three:

```bash
grep '"<package>"' package.json                      # which version do we install?
grep -rl "<symbol from the fix>" node_modules/<pkg>   # does that version carry it?
git log --oneline -S "<local workaround symbol>" -- <path>   # is our workaround gone?
```

Only when the fix ships in the installed version *and* the local workaround is deleted is the item closed end to end. Report which of the three is outstanding.

Also resolve: sibling tickets the body names (their current status may already answer an "open item" here), and any newer issue that supersedes this ticket's own argument.

## 4. Classify before you write

Per claim: **confirmed** / **stale** (true once, overtaken) / **contradicted** (states the opposite of the current truth) / **unverifiable** (say so; don't quietly drop it).

Lead the rewrite and the report with contradicted claims. Stale is a cost; contradicted is a trap.

If every open item turns out closed, say that plainly at the top — the ticket's real news is that it's done.

## 5. Rewrite in place

Follow the consuming repo's documented doc conventions first; these are the defaults when it has none.

A ticket body is **state** — it describes the situation as it now stands. Its changelog and comment thread are the **record**. So:

- **Edit the paragraph that's wrong.** Don't append a correction under it, don't strike it through, don't add "an earlier revision said". The tracker's version history holds the old text; a body carrying its own patch stack makes every reader apply the diff by hand.
- Keep the *reason* behind a counter-intuitive finding — that's current-state knowledge someone needs in order not to "fix" it back.
- Preserve evidence, measurements and reproduction steps. They don't rot; state assertions do.
- Update the section's "checked" date to today.
- Keep it the same size. A refresh that doubles a ticket has stopped refreshing and started journaling. A body that ends up accurate but shapeless is `ticket-polish`'s job — restructuring is not this skill's license.
- If the refresh closes an item, prune its condition from the "Done when" — a DoD mixing satisfied and open conditions can't be checked.

Then apply via the tracker's update tool with a targeted content edit, not a whole-page rewrite — a full-body replace risks silently dropping content you never read.

## 6. Post one comment — the record half of the change

§5 erases the wrong version without a trace, which is right for a body but leaves
everyone who already read it carrying the old claims; a tracker's page history notifies
nobody. The comment thread is the **record** — dated, closed, and the only part of a
ticket that reaches watchers. The edit and the comment are two halves of one change.

- **One comment per run, only when something was contradicted or materially changed.** A
  run that confirms everything edits nothing and comments nothing. A thread that fills
  with "checked, still true" trains people to skip it.
- **The comment points; it never contains.** Every fact in it is already in the body:
  *"the trail section now says X — it said Y, which was wrong because Z."* A finding that
  lives only in a comment is how a ticket comes to read as unstarted work while the
  implementation sits finished on a branch, recorded in a comment nobody re-read.
- **Carry what the body is forbidden to hold**: the correction narration §5 keeps out,
  the date you checked, and the **decisions you're handing back** — proposed
  Status/Assignee/re-scope, sibling tickets needing the same refresh, spin-off work.
  Those are asks, not state.
- **@-mention the assignee when there's a decision.** An unmentioned comment notifies
  roughly nobody.
- No usable comment API on this tracker (`tracker` profile knob) → skip it, say so in the
  report, and do **not** compensate by moving the narration into the body.

## 7. Report

- **Contradicted claims first**, each with the evidence that overturned it — anyone who read the old body is still carrying them.
- What you changed, what you deliberately left, and a link to the comment you posted (or why you didn't).
- **Proposed** Status / Assignee / scope changes, with the reasoning, flagged as needing their decision. Say what the ticket now means: e.g. "three of four items are closed; what's left is item 3, unowned, no PR — this is a re-scope or a park, not 'In progress'."
- Anything that deserves its own ticket rather than a line in this one.

## Hard rules

1. **Never change Status, Assignee, or Priority.** Propose them. That's `deliver`'s job on merge, and a human's otherwise.
2. **Never delete evidence** — measurements, repro steps, blast-radius numbers — to make a body shorter. Correct assertions; keep findings.
3. **Never record a resolution you haven't seen.** "Presumably merged by now" is how the ticket got wrong in the first place. Unverifiable stays labelled unverifiable.
4. **Never treat a closed PR as the end of the story** without reading its closing comments for a successor.
5. **Never leave a contradicted claim in place** because rewriting it is awkward. That claim is why the skill ran.
6. **Never let a comment be a finding's only home.** Comment after the body is correct, pointing at it — a shadow body rots the same way, unwatched.
